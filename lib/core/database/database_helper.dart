import 'package:flutter/foundation.dart';
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
    if (kIsWeb) {
      throw UnsupportedError('Database operations are not supported on web platform');
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
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
        exercise_type TEXT NOT NULL DEFAULT '',
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

    await db.execute('''
      CREATE TABLE user_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        gender TEXT NOT NULL,
        age_group TEXT NOT NULL,
        height REAL NOT NULL,
        goal TEXT NOT NULL,
        target_calories INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
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
      // v5: exercise_templates에 exercise_type 컬럼 추가 및 weight_records 테이블 생성
      try {
        await db.execute('''
          ALTER TABLE exercise_templates
          ADD COLUMN exercise_type TEXT NOT NULL DEFAULT ''
        ''');
      } catch (e) {
        // 컬럼이 이미 존재하는 경우 무시
      }
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
    if (oldVersion < 6) {
      // v6: exercise_type이 빈 문자열인 템플릿 삭제 (v5 마이그레이션 당시 기본값)
      await db.execute('''
        DELETE FROM exercise_templates WHERE exercise_type = ''
      ''');
    }
    if (oldVersion < 7) {
      // v7: user_profiles 테이블 생성
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          gender TEXT NOT NULL,
          age_group TEXT NOT NULL,
          height REAL NOT NULL,
          goal TEXT NOT NULL,
          target_calories INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status INTEGER DEFAULT 1
        )
      ''');
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
