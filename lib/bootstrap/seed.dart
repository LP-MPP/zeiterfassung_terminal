import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';

enum WorkState { off, working, onBreak }

class TimeEventsRepo {
  static const _uuid = Uuid();

  Future<String?> getLastEventType(String employeeId) async {
    final db = await AppDb.instance.db;
    final rows = await db.query(
      'time_events',
      columns: ['event_type'],
      where: 'employee_id = ?',
      whereArgs: [employeeId],
      orderBy: 'timestamp_utc DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['event_type'] as String;
  }

  WorkState stateFromLastEvent(String? lastEventType) {
    if (lastEventType == null) return WorkState.off;
    switch (lastEventType) {
      case 'IN':
      case 'BREAK_END':
        return WorkState.working;
      case 'BREAK_START':
        return WorkState.onBreak;
      case 'OUT':
      default:
        return WorkState.off;
    }
  }

  bool isAllowed(WorkState state, String nextEventType) {
    switch (state) {
      case WorkState.off:
        return nextEventType == 'IN';
      case WorkState.working:
        return nextEventType == 'BREAK_START' || nextEventType == 'OUT';
      case WorkState.onBreak:
        return nextEventType == 'BREAK_END';
    }
  }

  Future<void> insertEvent({
    required String employeeId,
    required String eventType,
    required String terminalId,
    required String source, // "PIN" (später "NFC")
  }) async {
    final db = await AppDb.instance.db;

    final last = await getLastEventType(employeeId);
    final state = stateFromLastEvent(last);

    if (!isAllowed(state, eventType)) {
      throw StateError('Aktion nicht zulässig (letzter Status: $last).');
    }

    final nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    final eventId = _uuid.v4();

    await db.insert(
      'time_events',
      {
        'event_id': eventId,
        'employee_id': employeeId,
        'event_type': eventType,
        'timestamp_utc': nowUtc,
        'terminal_id': terminalId,
        'source': source,
        'synced': 0,
      },
    );
  }

  Future<List<Map<String, Object?>>> eventsInRangeUtc(
    int fromUtcMs,
    int toUtcMs,
  ) async {
    final db = await AppDb.instance.db;
    return db.query(
      'time_events',
      where: 'timestamp_utc >= ? AND timestamp_utc < ?',
      whereArgs: [fromUtcMs, toUtcMs],
      orderBy: 'timestamp_utc ASC',
    );
  }
}