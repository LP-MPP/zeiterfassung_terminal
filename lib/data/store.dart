import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String id;
  final String name;
  final String pinHash;
  final bool active;

  Employee({
    required this.id,
    required this.name,
    required this.pinHash,
    required this.active,
  });

  static Employee fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Employee(
      id: (d['id'] ?? doc.id).toString(),
      name: (d['name'] ?? '').toString(),
      pinHash: (d['pinHash'] ?? '').toString(),
      active: (d['active'] ?? true) == true,
    );
  }
}

class TimeEvent {
  final String id; // Firestore doc id
  final String employeeId;
  final String eventType; // IN, OUT, BREAK_START, BREAK_END
  final int timestampUtcMs; // ms since epoch UTC
  final String terminalId;
  final String source; // PIN / ADMIN
  final String? note;
  final String? adminUid; // set for ADMIN writes

  TimeEvent({
    required this.id,
    required this.employeeId,
    required this.eventType,
    required this.timestampUtcMs,
    required this.terminalId,
    required this.source,
    this.note,
    this.adminUid,
  });

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'eventType': eventType,
        'timestampUtcMs': timestampUtcMs,
        'terminalId': terminalId,
        'source': source,
        'note': note,
        if (adminUid != null) 'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'dayKey': dayKeyFromUtcMs(timestampUtcMs),
      };

  static TimeEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return TimeEvent(
      id: doc.id,
      employeeId: (d['employeeId'] ?? '').toString(),
      eventType: (d['eventType'] ?? '').toString(),
      timestampUtcMs: (d['timestampUtcMs'] ?? 0) is int
          ? (d['timestampUtcMs'] as int)
          : int.tryParse((d['timestampUtcMs'] ?? '0').toString()) ?? 0,
      terminalId: (d['terminalId'] ?? '').toString(),
      source: (d['source'] ?? '').toString(),
      note: d['note']?.toString(),
      adminUid: d['adminUid']?.toString(),
    );
  }

  static String dayKeyFromUtcMs(int utcMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

///
/// Firestore-backed + realtime cached store.
/// Name remains `InMemoryStore` to keep your existing code changes minimal.
///
class InMemoryStore {
  InMemoryStore._();
  static final InMemoryStore instance = InMemoryStore._();

  final _db = FirebaseFirestore.instance;

  /// Public caches used by UI/Admin/Audit
  final Map<String, Employee> employees = {};
  final List<TimeEvent> events = [];

  StreamSubscription? _empSub;
  StreamSubscription? _eventsSub;

  bool _empInit = false;
  bool _eventsInit = false;

  CollectionReference<Map<String, dynamic>> get _empCol => _db.collection('employees');
  CollectionReference<Map<String, dynamic>> get _evCol => _db.collection('events');

  /// Start realtime listeners.
  /// You can subscribe only to events (recommended for terminal),
  /// because PunchScreen now loads employees directly from Firestore.
  Future<void> init({bool listenEmployees = true, bool listenEvents = true}) async {
    if (listenEmployees && !_empInit) {
      _empSub = _empCol.snapshots(includeMetadataChanges: true).listen((snap) {
        // On web, Firestore can emit an initial empty snapshot from cache.
        // Avoid clearing already-loaded data which would cause UI flicker.
        if (snap.metadata.isFromCache && snap.docs.isEmpty && employees.isNotEmpty) {
          return;
        }

        final next = <String, Employee>{};
        for (final doc in snap.docs) {
          final e = Employee.fromDoc(doc);
          next[e.id] = e;
        }
        employees
          ..clear()
          ..addAll(next);
      });
      _empInit = true;
    }

    if (listenEvents && !_eventsInit) {
      _eventsSub = _evCol
          .orderBy('timestampUtcMs', descending: false)
          .snapshots(includeMetadataChanges: true)
          .listen((snap) {
        // On web, Firestore can emit an initial empty snapshot from cache.
        // Avoid clearing already-loaded data which would cause UI flicker.
        if (snap.metadata.isFromCache && snap.docs.isEmpty && events.isNotEmpty) {
          return;
        }

        final next = <TimeEvent>[];
        for (final doc in snap.docs) {
          next.add(TimeEvent.fromDoc(doc));
        }
        events
          ..clear()
          ..addAll(next);
      });
      _eventsInit = true;
    }
  }

  Future<void> dispose() async {
    await _empSub?.cancel();
    await _eventsSub?.cancel();
    _empSub = null;
    _eventsSub = null;
    _empInit = false;
    _eventsInit = false;
  }

  // ---------------- Employees ----------------

  List<Employee> listEmployees() {
    final list = employees.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  Employee? getActiveEmployee(String id) {
    final e = employees[id];
    if (e == null) return null;
    if (!e.active) return null;
    return e;
  }

  void setActive(String id, bool active) {
    _empCol.doc(id).set(
      {'active': active, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  void upsertEmployee({
    required String id,
    required String name,
    required String pinHash,
    required bool active,
  }) {
    final data = {
      'id': id,
      'name': name,
      'pinHash': pinHash,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      // Hinweis: createdAt wird mit merge auch bei Updates gesetzt.
      // Wenn du das sauber trennen willst: später per Transaction nur beim ersten Anlegen.
      'createdAt': FieldValue.serverTimestamp(),
    };
    _empCol.doc(id).set(data, SetOptions(merge: true));
  }

  // ---------------- Events ----------------

  /// Creates an event at "now" (UTC). Append-only.
  Future<TimeEvent> addEvent({
    required String employeeId,
    required String eventType,
    required String terminalId,
    required String source, // "PIN" or "ADMIN"
    String? note,
    String? adminUid, // set when source == "ADMIN"
  }) async {
    final utcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final doc = _evCol.doc();
    final ev = TimeEvent(
      id: doc.id,
      employeeId: employeeId,
      eventType: eventType,
      timestampUtcMs: utcMs,
      terminalId: terminalId,
      source: source,
      note: note,
      adminUid: adminUid,
    );
    await doc.set(ev.toMap());
    return ev;
  }

  /// Creates an event at explicit UTC timestamp. Append-only. Used for admin corrections.
  Future<TimeEvent> addEventAt({
    required String employeeId,
    required String eventType,
    required int timestampUtcMs,
    required String terminalId,
    required String source, // "PIN" or "ADMIN"
    String? note,
    String? adminUid, // set when source == "ADMIN"
  }) async {
    final doc = _evCol.doc();
    final ev = TimeEvent(
      id: doc.id,
      employeeId: employeeId,
      eventType: eventType,
      timestampUtcMs: timestampUtcMs,
      terminalId: terminalId,
      source: source,
      note: note,
      adminUid: adminUid,
    );
    await doc.set(ev.toMap());
    return ev;
  }

  String? lastEventType(String employeeId) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e.employeeId == employeeId) return e.eventType;
    }
    return null;
  }

  // Signature matches your existing report.dart call style (positional args)
  List<TimeEvent> eventsInRangeUtc(int startUtcMsInclusive, int endUtcMsExclusive) {
    return events.where((e) {
      final t = e.timestampUtcMs;
      return t >= startUtcMsInclusive && t < endUtcMsExclusive;
    }).toList();
  }

  List<TimeEvent> eventsForEmployeeInRangeUtc(
    String employeeId,
    int startUtcMsInclusive,
    int endUtcMsExclusive,
  ) {
    return events.where((e) {
      if (e.employeeId != employeeId) return false;
      final t = e.timestampUtcMs;
      return t >= startUtcMsInclusive && t < endUtcMsExclusive;
    }).toList();
  }

  List<TimeEvent> eventsForEmployeeInMonthUtc(String employeeId, int year, int month) {
    final start = DateTime.utc(year, month, 1).millisecondsSinceEpoch;
    final end = DateTime.utc(year, month + 1, 1).millisecondsSinceEpoch;
    return eventsForEmployeeInRangeUtc(employeeId, start, end);
  }

  /// Returns map dayKey -> sorted events (ascending by time) for the given month.
  Map<String, List<TimeEvent>> groupEmployeeEventsByDayKey(String employeeId, int year, int month) {
    final list = eventsForEmployeeInMonthUtc(employeeId, year, month);
    final map = <String, List<TimeEvent>>{};
    for (final e in list) {
      final dk = TimeEvent.dayKeyFromUtcMs(e.timestampUtcMs);
      (map[dk] ??= []).add(e);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) => a.timestampUtcMs.compareTo(b.timestampUtcMs));
    }
    return map;
  }

  Future<void> seedIfEmpty({required List<Employee> seedEmployees}) async {
    final snap = await _empCol.limit(1).get();
    if (snap.docs.isNotEmpty) return;

    for (final e in seedEmployees) {
      await _empCol.doc(e.id).set({
        'id': e.id,
        'name': e.name,
        'pinHash': e.pinHash,
        'active': e.active,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
