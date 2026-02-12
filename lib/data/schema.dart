const String createEmployeesTable = '''
CREATE TABLE employees (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
''';

const String createTimeEventsTable = '''
CREATE TABLE time_events (
  event_id TEXT PRIMARY KEY,
  employee_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  timestamp_utc INTEGER NOT NULL,
  terminal_id TEXT NOT NULL,
  source TEXT NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (employee_id) REFERENCES employees(id)
);
''';

const String createTimeEventsIndex = '''
CREATE INDEX idx_time_events_employee_time
ON time_events(employee_id, timestamp_utc);
''';

const String createAuditLogTable = '''
CREATE TABLE audit_log (
  id TEXT PRIMARY KEY,
  action TEXT NOT NULL,
  timestamp_utc INTEGER NOT NULL,
  meta_json TEXT
);
''';
