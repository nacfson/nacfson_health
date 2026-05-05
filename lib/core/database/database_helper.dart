import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../../features/exercise/data/legacy_korean_mapping.dart';

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
      version: 12,
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
        rpe REAL NOT NULL,
        set_type TEXT NOT NULL DEFAULT 'work'
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
        rest_seconds_override INTEGER,
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
        age_group TEXT,
        age INTEGER NOT NULL DEFAULT 30,
        height REAL NOT NULL,
        goal TEXT NOT NULL,
        activity_level TEXT NOT NULL DEFAULT 'moderate',
        training_intensity TEXT NOT NULL DEFAULT 'moderate',
        target_calories INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_routines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        items_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_routine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT UNIQUE NOT NULL,
        items_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // v12: 다국어 master 운동 데이터 + 1RM 공식
    await _createV12Tables(db);
    // exercise_records / exercise_templates 의 exercise_key 컬럼은
    // _createDB 첫 진입 시점부터 함께 생성 (신규 사용자는 마이그레이션 불필요).
    await db.execute('ALTER TABLE exercise_records ADD COLUMN exercise_key TEXT');
    await db.execute('ALTER TABLE exercise_records ADD COLUMN category_key TEXT');
    await db.execute('ALTER TABLE exercise_templates ADD COLUMN exercise_key TEXT');
    await db.execute('ALTER TABLE exercise_templates ADD COLUMN category_key TEXT');
  }

  /// v12 master 운동 데이터 테이블 5개 생성. _createDB / _upgradeDB 양쪽에서 사용.
  Future<void> _createV12Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_categories (
        category_key TEXT PRIMARY KEY,
        display_order INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_category_translations (
        category_key TEXT NOT NULL,
        locale TEXT NOT NULL,
        display_name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (category_key, locale)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_definitions (
        exercise_key TEXT PRIMARY KEY,
        category_key TEXT NOT NULL,
        is_compound INTEGER NOT NULL DEFAULT 0,
        default_name TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_translations (
        exercise_key TEXT NOT NULL,
        locale TEXT NOT NULL,
        display_name TEXT NOT NULL,
        aliases TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (exercise_key, locale)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS one_rm_formulas (
        exercise_key TEXT PRIMARY KEY,
        formula_type TEXT NOT NULL,
        coefficients TEXT NOT NULL,
        source TEXT,
        optimal_rep_max INTEGER,
        notice_translations TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_exercise_definitions_category ON exercise_definitions(category_key)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_exercise_translations_locale ON exercise_translations(locale)');
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
    if (oldVersion < 8) {
      // v8: 루틴 프리셋(workout_routines) + 오늘 루틴(daily_routine) 테이블 생성
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workout_routines (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          items_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status INTEGER DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_routine (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT UNIQUE NOT NULL,
          items_json TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      // v9: exercise_records에 set_type 컬럼 추가 (웜업/본세트/드롭/실패)
      try {
        await db.execute('''
          ALTER TABLE exercise_records
          ADD COLUMN set_type TEXT NOT NULL DEFAULT 'work'
        ''');
      } catch (e) {
        // 컬럼이 이미 존재하는 경우 무시
      }
    }
    if (oldVersion < 10) {
      // v10: user_profiles 에 age / activity_level / training_intensity 컬럼 추가.
      // 기존 age_group 은 NULL 허용으로 남겨두고 신규 컬럼으로 이관 (SQLite DROP COLUMN 회피).
      try {
        await db.execute('''
          ALTER TABLE user_profiles
          ADD COLUMN age INTEGER NOT NULL DEFAULT 30
        ''');
      } catch (_) {
        // 이미 존재
      }
      try {
        await db.execute('''
          ALTER TABLE user_profiles
          ADD COLUMN activity_level TEXT NOT NULL DEFAULT 'moderate'
        ''');
      } catch (_) {
        // 이미 존재
      }
      try {
        await db.execute('''
          ALTER TABLE user_profiles
          ADD COLUMN training_intensity TEXT NOT NULL DEFAULT 'moderate'
        ''');
      } catch (_) {
        // 이미 존재
      }
      // age_group → age 값 백필 (중앙값). age 가 여전히 기본값 30 인 레코드에만 덮어쓴다.
      const midpoints = {'20s': 25, '30s': 35, '40s': 45, '50s+': 55};
      for (final entry in midpoints.entries) {
        await db.rawUpdate(
          'UPDATE user_profiles SET age = ? WHERE age_group = ? AND age = 30',
          [entry.value, entry.key],
        );
      }
      // 레거시 goal 문자열 정리: 'lean_mass' → 'lean_gain'
      await db.rawUpdate(
        "UPDATE user_profiles SET goal = 'lean_gain' WHERE goal = 'lean_mass'",
      );
    }
    if (oldVersion < 11) {
      // v11: exercise_templates 에 rest_seconds_override 컬럼 추가.
      // 종목별 휴식 시간 오버라이드(초). NULL 이면 부위 기본값 사용.
      // 기존 레코드는 NULL 상태로 두어 부위 기본값이 자동 적용되도록 한다.
      try {
        await db.execute('''
          ALTER TABLE exercise_templates
          ADD COLUMN rest_seconds_override INTEGER
        ''');
      } catch (_) {
        // 이미 존재
      }
    }
    if (oldVersion < 12) {
      // v12: 다국어 master 운동 데이터 (exercise_definitions/translations/categories)
      // + one_rm_formulas + 기존 사용자 데이터의 exercise_key 자동 매핑.
      await _createV12Tables(db);

      // 기존 user-owned 테이블에 exercise_key/category_key 컬럼 추가
      for (final stmt in const [
        'ALTER TABLE exercise_records ADD COLUMN exercise_key TEXT',
        'ALTER TABLE exercise_records ADD COLUMN category_key TEXT',
        'ALTER TABLE exercise_templates ADD COLUMN exercise_key TEXT',
        'ALTER TABLE exercise_templates ADD COLUMN category_key TEXT',
      ]) {
        try {
          await db.execute(stmt);
        } catch (_) {
          // 이미 존재
        }
      }

      // 한글명 → exercise_key 자동 매핑 (M1 — Eager).
      // exercise_name / exercise_type 컬럼은 보존 (historical snapshot).
      await _backfillExerciseKeysV12(db, 'exercise_records');
      await _backfillExerciseKeysV12(db, 'exercise_templates');

      // 루틴 items_json 도 한글명 → exercise_key 보강 (Dart 처리).
      await _migrateRoutineItemsJsonV12(db);
    }
  }

  /// v12 마이그레이션: 한글명 → exercise_key 자동 매핑.
  Future<void> _backfillExerciseKeysV12(Database db, String table) async {
    // exercise_templates 의 컬럼명은 'name', exercise_records 는 'exercise_name'.
    final nameCol = table == 'exercise_templates' ? 'name' : 'exercise_name';
    final typeCol = 'exercise_type';

    for (final entry in kLegacyKoreanExerciseNameToKey.entries) {
      await db.rawUpdate(
        'UPDATE $table SET exercise_key = ? WHERE $nameCol = ? AND exercise_key IS NULL',
        [entry.value, entry.key],
      );
    }
    for (final entry in kLegacyKoreanCategoryToKey.entries) {
      await db.rawUpdate(
        'UPDATE $table SET category_key = ? WHERE $typeCol = ? AND category_key IS NULL',
        [entry.value, entry.key],
      );
    }
  }

  /// v12 마이그레이션: workout_routines / daily_routine 의 items_json 안
  /// 한글 종목명에 exerciseKey 필드를 추가한다.
  Future<void> _migrateRoutineItemsJsonV12(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final tableName in const ['workout_routines', 'daily_routine']) {
      final rows = await db.query(tableName);
      for (final row in rows) {
        final raw = row['items_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List) continue;
          var changed = false;
          for (final item in decoded) {
            if (item is! Map<String, dynamic>) continue;
            if (item['exerciseKey'] != null) continue;
            final name = item['exerciseName'] as String?;
            final key = legacyKoreanToExerciseKey(name);
            if (key != null) {
              item['exerciseKey'] = key;
              changed = true;
            }
          }
          if (changed) {
            final values = <String, Object?>{
              'items_json': jsonEncode(decoded),
              'updated_at': now,
            };
            // workout_routines 는 sync_status 가 있으므로 modified 로 마킹하여 재push.
            if (tableName == 'workout_routines') {
              values['sync_status'] = 2; // SyncStatus.modified
            }
            await db.update(
              tableName,
              values,
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        } catch (_) {
          // 한 행 파싱 실패해도 나머지는 계속 처리
        }
      }
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
