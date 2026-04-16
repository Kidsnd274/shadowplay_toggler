import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_service.dart';

class AppStateRepository {
  final DatabaseService _dbService;

  AppStateRepository(this._dbService);

  Future<String?> getValue(String key) async {
    final maps = await _dbService.db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> setValue(String key, String value) async {
    await _dbService.db.insert(
      'app_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getBool(String key) async {
    final value = await getValue(key);
    return value == 'true';
  }

  Future<void> setBool(String key, bool value) async {
    await setValue(key, value.toString());
  }

  Future<void> remove(String key) async {
    await _dbService.db.delete(
      'app_state',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
