import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/managed_rule.dart';
import 'database_service.dart';

class ManagedRulesRepository {
  final DatabaseService _dbService;

  ManagedRulesRepository(this._dbService);

  Future<List<ManagedRule>> getAllRules() async {
    // Stable alphabetical order by exe name, then full path as a tiebreaker.
    // Toggling `intended_value` / `updated_at` must NOT reorder the list
    // because reordering on every flip is disorienting in the UI.
    final maps = await _dbService.db.query(
      'managed_rules',
      orderBy: 'LOWER(exe_name) ASC, LOWER(exe_path) ASC',
    );
    return maps.map(ManagedRule.fromMap).toList();
  }

  Future<ManagedRule?> getRuleByExePath(String exePath) async {
    final maps = await _dbService.db.query(
      'managed_rules',
      where: 'exe_path = ?',
      whereArgs: [exePath],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ManagedRule.fromMap(maps.first);
  }

  Future<int> insertRule(ManagedRule rule) async {
    return _dbService.db.insert(
      'managed_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateRule(ManagedRule rule) async {
    if (rule.id == null) {
      throw ArgumentError('Cannot update a rule without an id');
    }
    await _dbService.db.update(
      'managed_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<void> deleteRule(int id) async {
    await _dbService.db.delete(
      'managed_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRuleByExePath(String exePath) async {
    await _dbService.db.delete(
      'managed_rules',
      where: 'exe_path = ?',
      whereArgs: [exePath],
    );
  }
}
