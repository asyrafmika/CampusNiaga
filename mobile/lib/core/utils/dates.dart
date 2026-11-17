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

/// `3:05 PM` today, `Yesterday`, otherwise `16 Nov 2026`; for chat lists and
/// message times. [now] is the phone's local time.
String formatChatTime(DateTime time, DateTime now) {
  final t = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  if (today.difference(day).inDays == 1) return 'Yesterday';
  return formatDay(t);
}
