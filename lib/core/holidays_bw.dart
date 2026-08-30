/// Computes all public holidays for Baden-Wuerttemberg in a given year.
/// Returns a list of dayKey strings (YYYY-MM-DD).
List<String> getPublicHolidaysBW(int year) {
  final easter = _easterSunday(year);
  final holidays = <DateTime>[
    DateTime(year, 1, 1), // Neujahr
    DateTime(year, 1, 6), // Heilige Drei Koenige
    easter.add(const Duration(days: -2)), // Karfreitag
    easter.add(const Duration(days: 1)), // Ostermontag
    DateTime(year, 5, 1), // Tag der Arbeit
    easter.add(const Duration(days: 39)), // Christi Himmelfahrt
    easter.add(const Duration(days: 50)), // Pfingstmontag
    easter.add(const Duration(days: 60)), // Fronleichnam
    DateTime(year, 10, 3), // Tag der Deutschen Einheit
    DateTime(year, 11, 1), // Allerheiligen
    DateTime(year, 12, 25), // 1. Weihnachtstag
    DateTime(year, 12, 26), // 2. Weihnachtstag
  ];

  return holidays.map(_dayKey).toList()..sort();
}

/// Returns a map of dayKey → holiday name for display purposes.
Map<String, String> getPublicHolidayNamesBW(int year) {
  final easter = _easterSunday(year);
  return {
    _dayKey(DateTime(year, 1, 1)): 'Neujahr',
    _dayKey(DateTime(year, 1, 6)): 'Heilige Drei Koenige',
    _dayKey(easter.add(const Duration(days: -2))): 'Karfreitag',
    _dayKey(easter.add(const Duration(days: 1))): 'Ostermontag',
    _dayKey(DateTime(year, 5, 1)): 'Tag der Arbeit',
    _dayKey(easter.add(const Duration(days: 39))): 'Christi Himmelfahrt',
    _dayKey(easter.add(const Duration(days: 50))): 'Pfingstmontag',
    _dayKey(easter.add(const Duration(days: 60))): 'Fronleichnam',
    _dayKey(DateTime(year, 10, 3)): 'Tag der Deutschen Einheit',
    _dayKey(DateTime(year, 11, 1)): 'Allerheiligen',
    _dayKey(DateTime(year, 12, 25)): '1. Weihnachtstag',
    _dayKey(DateTime(year, 12, 26)): '2. Weihnachtstag',
  };
}

/// Gauss Easter algorithm — returns Easter Sunday for a given year.
DateTime _easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

String _dayKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
