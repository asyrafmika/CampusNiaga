// Listing and reservation values from docs/data-dictionary.md. `wireName`
// is exactly what the database stores.

T _fromWire<T extends Enum>(
  List<T> values,
  String Function(T) wire,
  Object? value,
  String what,
) => values.firstWhere(
  (v) => wire(v) == value,
  orElse: () => throw FormatException('Unknown $what: $value'),
);

enum ListingStatus {
  draft('draft', 'Draft'),
  available('available', 'Available'),
  reserved('reserved', 'Reserved'),
  sold('sold', 'Sold'),
  closed('closed', 'Closed');

  const ListingStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static ListingStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'listing status');
}

/// Personal items are reserved; business products are ordered (Phase 4).
enum ListingMode {
  personal('personal'),
  business('business');

  const ListingMode(this.wireName);

  final String wireName;

  static ListingMode fromWire(Object? value) =>
      _fromWire(values, (m) => m.wireName, value, 'listing mode');
}

enum ListingCondition {
  brandNew('new', 'New'),
  likeNew('like_new', 'Like new'),
  good('good', 'Good'),
  fair('fair', 'Fair');

  const ListingCondition(this.wireName, this.label);

  final String wireName;
  final String label;

  static ListingCondition fromWire(Object? value) =>
      _fromWire(values, (c) => c.wireName, value, 'listing condition');
}

enum ReservationStatus {
  requested('requested', 'Requested'),
  accepted('accepted', 'Accepted'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Cancelled'),
  collected('collected', 'Collected'),
  expired('expired', 'Expired');

  const ReservationStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Still holding units.
  bool get isActive => this == requested || this == accepted;

  static ReservationStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'reservation status');
}

enum ReportReason {
  prohibitedItem('prohibited_item', 'Prohibited item'),
  scam('scam', 'Scam or fraud'),
  offensive('offensive', 'Offensive content'),
  misleading('misleading', 'Misleading or wrong details'),
  other('other', 'Something else');

  const ReportReason(this.wireName, this.label);

  final String wireName;
  final String label;
}
