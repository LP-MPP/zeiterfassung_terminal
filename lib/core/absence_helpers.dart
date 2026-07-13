import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/absence.dart';
import 'holidays_bw.dart';

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

  final normalizedStart = type == AbsenceType.urlaub
      ? AbsenceDayPart.normalize(startDayPart)
      : AbsenceDayPart.full;
  final normalizedEnd = type == AbsenceType.urlaub
      ? AbsenceDayPart.normalize(endDayPart)
      : AbsenceDayPart.full;
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

/// Recalculates and writes the vacation_balances document for an employee/year.
Future<void> recalculateVacationBalance(String employeeId, int year) async {
  final db = FirebaseFirestore.instance;

  // Get employee data for entitlement
  final empDoc = await db.collection('employees').doc(employeeId).get();
  final empData = empDoc.data() ?? {};
  final entitlement = (empData['vacationDaysPerYear'] ?? 25).toDouble();

  // Get all absences for this employee in this year
  final yearStart = '$year-01-01';
  final yearEnd = '$year-12-31';
  final holidays = getPublicHolidaysBW(year).toSet();

  final absSnap = await db
      .collection('absences')
      .where('employeeId', isEqualTo: employeeId)
      .get();

  double usedVacation = 0;
  double plannedVacation = 0;
  double sickDays = 0;

  for (final doc in absSnap.docs) {
    final a = Absence.fromDoc(doc);
    // Check if absence overlaps with this year
    if (a.endDate.compareTo(yearStart) < 0) continue;
    if (a.startDate.compareTo(yearEnd) > 0) continue;

    // Clamp to year boundaries
    final clampedStart = a.startDate.compareTo(yearStart) < 0
        ? yearStart
        : a.startDate;
    final clampedEnd = a.endDate.compareTo(yearEnd) > 0 ? yearEnd : a.endDate;
    final days = calculateAbsenceDays(
      startDate: clampedStart,
      endDate: clampedEnd,
      holidays: holidays,
      startDayPart: clampedStart == a.startDate
          ? a.startDayPart
          : AbsenceDayPart.full,
      endDayPart: clampedEnd == a.endDate ? a.endDayPart : AbsenceDayPart.full,
      type: a.type,
    );

    if (a.type == AbsenceType.urlaub) {
      if (a.status == AbsenceStatus.approved) {
        usedVacation += days;
      } else if (a.status == AbsenceStatus.pending) {
        plannedVacation += days;
      }
    } else if (a.type == AbsenceType.krankheit &&
        a.status == AbsenceStatus.approved) {
      sickDays += days;
    }
  }

  // Get carry-over from previous year's balance (if exists)
  double carryOver = 0;
  final prevBalDoc = await db
      .collection('vacation_balances')
      .doc('${employeeId}_${year - 1}')
      .get();
  if (prevBalDoc.exists) {
    final prevData = prevBalDoc.data() ?? {};
    final prevRemaining = (prevData['remaining'] ?? 0).toDouble();
    if (prevRemaining > 0) carryOver = prevRemaining;
  }

  final remaining = entitlement + carryOver - usedVacation;

  await db.collection('vacation_balances').doc('${employeeId}_$year').set({
    'employeeId': employeeId,
    'year': year,
    'entitlement': entitlement,
    'carryOver': carryOver,
    'used': usedVacation,
    'planned': plannedVacation,
    'remaining': remaining,
    'sickDays': sickDays,
    'updatedAt': FieldValue.serverTimestamp(),
  });
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
