/// Absence type constants.
class AbsenceType {
  static const urlaub = 'URLAUB';
  static const krankheit = 'KRANKHEIT';
  static const sonderurlaub = 'SONDERURLAUB';

  static String label(String type) {
    switch (type) {
      case urlaub:
        return 'Urlaub';
      case krankheit:
        return 'Krankheit';
      case sonderurlaub:
        return 'Sonderurlaub (bezahlt)';
      default:
        return type;
    }
  }
}

/// Absence status constants.
class AbsenceStatus {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';

  static String label(String status) {
    switch (status) {
      case pending:
        return 'Offen';
      case approved:
        return 'Genehmigt';
      case rejected:
        return 'Abgelehnt';
      case cancelled:
        return 'Storniert';
      default:
        return status;
    }
  }
}

class AbsenceDayPart {
  static const full = 'FULL';
  static const morning = 'MORNING';
  static const afternoon = 'AFTERNOON';

  static String normalize(Object? value) {
    final part = (value ?? full).toString().toUpperCase();
    return part == morning || part == afternoon ? part : full;
  }

  static String label(String part) {
    switch (normalize(part)) {
      case morning:
        return 'Vormittag';
      case afternoon:
        return 'Nachmittag';
      default:
        return 'Ganzer Tag';
    }
  }
}

class SpecialLeaveCategory {
  static String label(String? category) {
    switch (category) {
      case 'HOCHZEIT':
        return 'Hochzeit';
      case 'TRAUERFALL':
        return 'Trauerfall';
      case 'GEBURT':
        return 'Geburt';
      case 'UMZUG':
        return 'Umzug';
      case 'SONSTIGES':
        return 'Sonstiges';
      default:
        return '';
    }
  }
}

/// Represents an absence record (vacation, paid special leave or sick leave).
class Absence {
  final String id;
  final String employeeId;
  final String type; // URLAUB | KRANKHEIT | SONDERURLAUB
  final String startDate; // dayKey YYYY-MM-DD, inclusive
  final String endDate; // dayKey YYYY-MM-DD, inclusive
  final String startDayPart; // FULL | MORNING | AFTERNOON
  final String endDayPart; // FULL | MORNING | AFTERNOON
  final String status; // PENDING | APPROVED | REJECTED | CANCELLED
  final double vacationDaysConsumed; // working days excl. weekends/holidays
  final String? specialLeaveCategory;
  final String? reason;
  final bool createdByEmployee; // true = terminal, false = admin
  final String? adminUid;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime? createdAt;

  Absence({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.startDayPart = AbsenceDayPart.full,
    this.endDayPart = AbsenceDayPart.full,
    required this.status,
    required this.vacationDaysConsumed,
    this.specialLeaveCategory,
    this.reason,
    this.createdByEmployee = false,
    this.adminUid,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    this.createdAt,
  });

  factory Absence.fromMap(String id, Map<String, dynamic> d) {
    return Absence(
      id: id,
      employeeId: (d['employeeId'] ?? '').toString(),
      type: (d['type'] ?? AbsenceType.urlaub).toString(),
      startDate: (d['startDate'] ?? '').toString(),
      endDate: (d['endDate'] ?? '').toString(),
      startDayPart: AbsenceDayPart.normalize(d['startDayPart']),
      endDayPart: AbsenceDayPart.normalize(d['endDayPart']),
      status: (d['status'] ?? AbsenceStatus.pending).toString(),
      vacationDaysConsumed: (d['vacationDaysConsumed'] ?? 0).toDouble(),
      specialLeaveCategory: d['specialLeaveCategory']?.toString(),
      reason: d['reason']?.toString(),
      createdByEmployee: d['createdByEmployee'] == true,
      adminUid: d['adminUid']?.toString(),
      approvedBy: d['approvedBy']?.toString(),
      approvedAt: _asDateTime(d['approvedAt']),
      rejectionReason: d['rejectionReason']?.toString(),
      createdAt: _asDateTime(d['createdAt']),
    );
  }

  /// Whether this absence is active (approved or pending).
  bool get isActive =>
      status == AbsenceStatus.approved || status == AbsenceStatus.pending;
}

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is Map && value['_seconds'] is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value['_seconds'] as num).toInt() * 1000,
      isUtc: true,
    ).toLocal();
  }
  return null;
}
