// Business application and business values from docs/data-dictionary.md.
// `wireName` is exactly what the database stores.

T _fromWire<T extends Enum>(
  List<T> values,
  String Function(T) wire,
  Object? value,
  String what,
) => values.firstWhere(
  (v) => wire(v) == value,
  orElse: () => throw FormatException('Unknown $what: $value'),
);

enum ApplicationStatus {
  draft('draft', 'Draft'),
  submitted('submitted', 'Submitted'),
  underReview('under_review', 'Under review'),
  infoRequested('info_requested', 'Changes requested'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Not approved');

  const ApplicationStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static ApplicationStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'application status');
}

/// Who changed an application's status (`application_status_history`).
/// `reviewer` only appears in history from before ADR 0009, when the
/// reviewer role merged into the HDC administrator.
enum ApplicationActor {
  applicant('applicant', 'You'),
  reviewer('reviewer', 'Reviewer'),
  admin('admin', 'HDC administrator');

  const ApplicationActor(this.wireName, this.label);

  final String wireName;
  final String label;

  static ApplicationActor fromWire(Object? value) =>
      _fromWire(values, (a) => a.wireName, value, 'application actor');
}

enum BusinessStatus {
  approved('approved', 'Approved'),
  suspended('suspended', 'Suspended');

  const BusinessStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static BusinessStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'business status');
}

/// Orders (M3). The seller moves an order forward one step at a time;
/// either side may cancel before it is completed.
enum OrderStatus {
  pendingConfirmation('pending_confirmation', 'Awaiting confirmation'),
  confirmed('confirmed', 'Confirmed'),
  preparing('preparing', 'Preparing'),
  readyForPickup('ready_for_pickup', 'Ready for pickup'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const OrderStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Still in progress: not completed or cancelled.
  bool get isActive => this != completed && this != cancelled;

  static OrderStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'order status');
}

/// Pre-order campaigns (M3): draft -> open -> closed, or draft -> closed.
enum CampaignStatus {
  draft('draft', 'Draft'),
  open('open', 'Open'),
  closed('closed', 'Closed');

  const CampaignStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static CampaignStatus fromWire(Object? value) =>
      _fromWire(values, (s) => s.wireName, value, 'campaign status');
}
