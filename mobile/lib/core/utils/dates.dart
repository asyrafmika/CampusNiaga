const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `16 Nov 2026`, in the phone's local time.
String formatDay(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// `16 Nov 2026, 3:05 PM`, in the phone's local time.
String formatDayTime(DateTime time) {
  final t = time.toLocal();
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '${formatDay(t)}, $hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}
