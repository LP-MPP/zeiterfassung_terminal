import '../data/absence.dart';

/// Counts working days between startDate and endDate (inclusive),
/// excluding weekends (Sat/Sun) and public holidays.
int countWorkingDays(String startDate, String endDate, Set<String> holidays) {
  final start = _parseDate(startDate);
  final end = _parseDate(endDate);
  if (start == null || end == null) return 0;

  int count = 0;
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    if (d.weekday >= 6) continue; // Saturday=6, Sunday=7
    if (holidays.contains(_dayKey(d))) continue;
    count++;
  }
  return count;
}

double calculateAbsenceDays({
  required String startDate,
  required String endDate,
  required Set<String> holidays,
  String startDayPart = AbsenceDayPart.full,
  String endDayPart = AbsenceDayPart.full,
  String type = AbsenceType.urlaub,
}) {
  final start = _parseDate(startDate);
  final end = _parseDate(endDate);
  if (start == null || end == null || end.isBefore(start)) return 0;

  final normalizedStart = AbsenceDayPart.normalize(startDayPart);
  final normalizedEnd = AbsenceDayPart.normalize(endDayPart);
  final singleDay = startDate == endDate;
  double count = 0;

  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final key = _dayKey(d);
    if (d.weekday >= 6 || holidays.contains(key)) continue;

    var fraction = 1.0;
    if (singleDay && normalizedStart != AbsenceDayPart.full) {
      fraction = 0.5;
    } else if (!singleDay &&
        key == startDate &&
        normalizedStart == AbsenceDayPart.afternoon) {
      fraction = 0.5;
    } else if (!singleDay &&
        key == endDate &&
        normalizedEnd == AbsenceDayPart.morning) {
      fraction = 0.5;
    }
    count += fraction;
  }
  return count;
}

String formatAbsenceDays(double days) {
  return days == days.roundToDouble()
      ? days.toStringAsFixed(0)
      : days.toStringAsFixed(1).replaceAll('.', ',');
}

/// Expands an absence's date range into a map of dayKey → absenceType.
/// Only includes working days (excludes weekends).
Map<String, String> expandAbsenceToDayKeys(Absence absence) {
  final start = _parseDate(absence.startDate);
  final end = _parseDate(absence.endDate);
  if (start == null || end == null) return {};

  final map = <String, String>{};
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    if (d.weekday >= 6) continue;
    map[_dayKey(d)] = absence.type;
  }
  return map;
}

DateTime? _parseDate(String dayKey) {
  final parts = dayKey.split('-');
  if (parts.length != 3) return null;
  return DateTime.tryParse(dayKey);
}

String _dayKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
