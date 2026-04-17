import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbFileName = 'managed_rules.db';
const _dbVersion = 1;

class DatabaseService {
  Database? _db;
  String? _path;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return database;
  }

  bool get isInitialized => _db != null;

  /// Absolute path to the on-disk database file. Null until [initialize]
  /// has been called at least once. Useful for the Reset Database flow
  /// in Settings, which has to delete the file from outside this class.
  String? get path => _path;

  Future<void> initialize() async {
    if (_db != null) return;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, _dbFileName);
    _path = dbPath;

    _db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE managed_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exe_path TEXT NOT NULL UNIQUE,
        exe_name TEXT NOT NULL,
        profile_name TEXT NOT NULL,
        profile_was_predefined INTEGER NOT NULL DEFAULT 0,
        profile_was_created INTEGER NOT NULL DEFAULT 0,
        intended_value INTEGER NOT NULL DEFAULT 0x10000000,
        previous_value INTEGER,
        driver_version TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Reserved for future schema migrations.
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
