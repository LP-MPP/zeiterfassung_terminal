import 'package:flutter_test/flutter_test.dart';
import 'package:zeiterfassung_terminal/core/absence_helpers.dart';
import 'package:zeiterfassung_terminal/data/absence.dart';

void main() {
  group('calculateAbsenceDays', () {
    test('counts a full working day', () {
      expect(
        calculateAbsenceDays(
          startDate: '2026-07-13',
          endDate: '2026-07-13',
          holidays: const {},
        ),
        1,
      );
    });

    test('counts morning and afternoon as half a day', () {
      for (final part in [AbsenceDayPart.morning, AbsenceDayPart.afternoon]) {
        expect(
          calculateAbsenceDays(
            startDate: '2026-07-13',
            endDate: '2026-07-13',
            holidays: const {},
            startDayPart: part,
            endDayPart: part,
          ),
          0.5,
        );
      }
    });

    test('counts afternoon through next morning correctly', () {
      expect(
        calculateAbsenceDays(
          startDate: '2026-07-13',
          endDate: '2026-07-15',
          holidays: const {},
          startDayPart: AbsenceDayPart.afternoon,
          endDayPart: AbsenceDayPart.morning,
        ),
        2,
      );
    });

    test('excludes weekends and public holidays', () {
      expect(
        calculateAbsenceDays(
          startDate: '2026-07-17',
          endDate: '2026-07-20',
          holidays: const {'2026-07-20'},
        ),
        1,
      );
    });

    test('counts half-day sickness', () {
      expect(
        calculateAbsenceDays(
          startDate: '2026-07-13',
          endDate: '2026-07-13',
          holidays: const {},
          startDayPart: AbsenceDayPart.morning,
          endDayPart: AbsenceDayPart.morning,
          type: AbsenceType.krankheit,
        ),
        0.5,
      );
    });
  });
}
