import 'package:sqflite/sqflite.dart';
import 'db.dart';

class EmployeesRepo {
  Future<void> upsertEmployee({
    required String id,
    required String name,
    required String pinHash,
    required bool active,
  }) async {
    final Database db = await AppDb.instance.db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await db.insert(
      'employees',
      {
        'id': id,
        'name': name,
        'pin_hash': pinHash,
        'active': active ? 1 : 0,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getActiveEmployee(String id) async {
    final db = await AppDb.instance.db;
    final rows = await db.query(
      'employees',
      where: 'id = ? AND active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listEmployees() async {
    final db = await AppDb.instance.db;
    return db.query('employees', orderBy: 'id ASC');
  }

  Future<void> setActive(String id, bool active) async {
    final db = await AppDb.instance.db;
    await db.update(
      'employees',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}