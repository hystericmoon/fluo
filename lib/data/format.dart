/// Short relative date for list rows: "Today", "Yesterday", "Mon",
/// "Last week" (the previous Monday to Sunday), then "Oct 28".
String relativeDay(DateTime when, {required DateTime now}) {
  // Calendar days in UTC so a daylight-saving change cannot shift the count.
  DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final today = day(now);
  final that = day(when);
  final days = today.difference(that).inDays;
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return weekdays[when.weekday - 1];
  final thisWeek = today.subtract(Duration(days: today.weekday - 1));
  final lastWeek = thisWeek.subtract(const Duration(days: 7));
  if (!that.isBefore(lastWeek) && that.isBefore(thisWeek)) return 'Last week';
  return '${months[when.month - 1]} ${when.day}';
}

String screensLabel(int n) => n == 1 ? '1 screen' : '$n screens';
