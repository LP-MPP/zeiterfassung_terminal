import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final path = join(basePath, 'zeiterfassung.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE employees (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            pin_hash TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL
          );
        ''');
        await db.execute('''
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
        ''');
        await db.execute('''
          CREATE INDEX idx_time_events_employee_time
          ON time_events(employee_id, timestamp_utc);
        ''');
        await db.execute('''
          CREATE TABLE audit_log (
            id TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            timestamp_utc INTEGER NOT NULL,
            meta_json TEXT
          );
        ''');
      },
    );
  }
}