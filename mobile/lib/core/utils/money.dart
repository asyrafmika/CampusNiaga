// Money is stored and calculated in whole sen (`int`). RM appears only in
// text produced here.

/// "RM 25", "RM 25.50", "RM 1,250".
String formatRm(int sen) {
  final negative = sen < 0;
  final abs = sen.abs();
  final ringgit = abs ~/ 100;
  final cents = abs % 100;
  final grouped = ringgit.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final decimals = cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}RM $grouped$decimals';
}

/// Reads a price typed by the user ("25", "25.5", "RM 25.50", "1,250") into
/// sen. Returns `null` if it isn't a non-negative amount with at most 2
/// decimals.
int? parseRmToSen(String input) {
  final cleaned = input
      .trim()
      .replaceFirst(RegExp(r'^rm\s*', caseSensitive: false), '')
      .replaceAll(',', '');
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final ringgit = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return ringgit * 100 + int.parse(fraction);
}

/// The price as the form shows it when editing: "25" or "25.50".
String senToInput(int sen) {
  final ringgit = sen ~/ 100;
  final cents = sen % 100;
  return cents == 0
      ? '$ringgit'
      : '$ringgit.${cents.toString().padLeft(2, '0')}';
}
