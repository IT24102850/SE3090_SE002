/// Plain `YYYY-MM-DD` for the calendar day the user picked — the backend
/// treats `available-slots?date=` as a day boundary, not a precise instant,
/// so this must never be converted through UTC/local math.
String toApiDateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatTimeOfDay(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String formatWeekday(DateTime d) => _weekdays[d.weekday - 1];
String formatDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String formatFullDate(DateTime d) => '${formatWeekday(d)}, ${formatDayMonth(d)} ${d.year}';

/// Shared rendering for Night/DateRange/Package bookings (see
/// docs/tourism-business-template.md) - used by the confirm/success/my
/// bookings screens so the branch isn't duplicated in three places.
String formatDateRangeSummary(DateTime start, DateTime end, {required bool nights}) {
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  final count = endDay.difference(startDay).inDays;
  final unitLabel = nights ? (count == 1 ? 'night' : 'nights') : (count == 1 ? 'day' : 'days');
  return '${formatDayMonth(start)} → ${formatDayMonth(end)} · $count $unitLabel';
}
