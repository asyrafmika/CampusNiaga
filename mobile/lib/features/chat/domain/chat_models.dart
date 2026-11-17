/// The deal chat (ADR 0004): text between the buyer and seller of an
/// accepted reservation or a confirmed business order.
library;

/// What a chat belongs to.
enum ChatKind {
  reservation('reservation', 'Booking'),
  order('order', 'Order');

  const ChatKind(this.wireName, this.label);

  final String wireName;
  final String label;

  static ChatKind fromWire(String value) => values.firstWhere(
    (k) => k.wireName == value,
    orElse: () => throw FormatException('Unknown chat kind: $value'),
  );
}

/// The deal a chat is opened for: exactly one of the two ids.
class ChatDeal {
  const ChatDeal.reservation(String this.reservationId) : orderId = null;
  const ChatDeal.order(String this.orderId) : reservationId = null;

  final String? reservationId;
  final String? orderId;

  @override
  bool operator ==(Object other) =>
      other is ChatDeal &&
      other.reservationId == reservationId &&
      other.orderId == orderId;

  @override
  int get hashCode => Object.hash(reservationId, orderId);
}

/// One row of the chat list (`conversation_card`).
class ConversationCard {
  const ConversationCard({
    required this.id,
    required this.kind,
    required this.listingId,
    required this.listingTitle,
    required this.otherPartyName,
    required this.iAmBuyer,
    required this.unreadCount,
    required this.canSend,
    required this.closed,
    required this.createdAt,
    this.listingPhoto,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageMine = false,
  });

  final String id;
  final ChatKind kind;
  final String listingId;
  final String listingTitle;
  final String? listingPhoto;
  final String otherPartyName;
  final bool iAmBuyer;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool lastMessageMine;
  final int unreadCount;

  /// False once the deal has ended or the chat was closed: read-only.
  final bool canSend;
  final bool closed;
  final DateTime createdAt;

  /// The other person's role, as the chat shows it.
  String get otherPartyRole => iAmBuyer ? 'Seller' : 'Buyer';

  /// The preview line in the chat list.
  String get preview => switch (lastMessage) {
    null => 'No messages yet',
    final text when lastMessageMine => 'You: $text',
    final text => text,
  };

  /// Why the chat can't send, or null while it can.
  String? get readOnlyReason {
    if (closed) return 'This chat was closed.';
    if (!canSend) {
      return 'This ${kind == ChatKind.order ? 'order' : 'booking'} has '
          'ended, so the chat is read-only.';
    }
    return null;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  /// Grows with every message, so it orders a chat.
  final int id;
  final String senderId;
  final String body;
  final DateTime createdAt;
}

enum ChatReportReason {
  scam('scam', 'Scam or asking for payment first'),
  offensive('offensive', 'Rude, offensive or harassing'),
  other('other', 'Something else');

  const ChatReportReason(this.wireName, this.label);

  final String wireName;
  final String label;
}

abstract final class ChatRules {
  static const int maxLength = 1000;

  /// Null when [body] can be sent, otherwise why not.
  static String? validate(String body) {
    final text = body.trim();
    if (text.isEmpty) return 'Write a message first.';
    if (text.length > maxLength) {
      return 'Messages can be up to $maxLength characters.';
    }
    return null;
  }

  /// [current] plus [incoming], each message once, oldest first. A message
  /// can arrive twice: from the send call and from the live update.
  static List<ChatMessage> merge(
    List<ChatMessage> current,
    Iterable<ChatMessage> incoming,
  ) {
    final byId = {for (final m in current) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }
}
