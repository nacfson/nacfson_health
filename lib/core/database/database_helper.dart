import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('nacfson_health.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE exercise_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1,
        exercise_type TEXT NOT NULL,
        exercise_name TEXT NOT NULL,
        current_set INTEGER NOT NULL,
        weight REAL NOT NULL,
        reps INTEGER NOT NULL,
        rpe REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE diet_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1,
        meal_type TEXT NOT NULL,
        food_name TEXT NOT NULL,
        total_calories INTEGER NOT NULL,
        carbs REAL NOT NULL,
        protein REAL NOT NULL,
        fat REAL NOT NULL,
        satisfaction INTEGER NOT NULL,
        memo TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE exercise_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        name TEXT UNIQUE NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE food_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        name TEXT UNIQUE NOT NULL,
        calories INTEGER NOT NULL DEFAULT 0,
        carbs REAL NOT NULL DEFAULT 0,
        protein REAL NOT NULL DEFAULT 0,
        fat REAL NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE weight_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        timestamp INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1,
        weight REAL NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exercise_templates (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          name TEXT UNIQUE NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status INTEGER DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS food_templates (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          name TEXT UNIQUE NOT NULL,
          calories INTEGER NOT NULL DEFAULT 0,
          carbs REAL NOT NULL DEFAULT 0,
          protein REAL NOT NULL DEFAULT 0,
          fat REAL NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          sync_status INTEGER DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS weight_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          timestamp INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status INTEGER DEFAULT 1,
          weight REAL NOT NULL
        )
      ''');
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
