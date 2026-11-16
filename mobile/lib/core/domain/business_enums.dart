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
enum ApplicationActor {
  applicant('applicant', 'You'),
  reviewer('reviewer', 'Reviewer'),
  admin('admin', 'Administrator');

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
