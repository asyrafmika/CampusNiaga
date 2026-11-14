/// `profiles.account_status` (docs/data-dictionary.md).
enum AccountStatus {
  active('active'),
  suspended('suspended');

  const AccountStatus(this.wireName);

  /// The value stored in the database.
  final String wireName;

  static AccountStatus fromWire(String value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => throw FormatException('Unknown account status: $value'),
  );
}
