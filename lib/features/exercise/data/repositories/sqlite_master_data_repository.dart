import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/exercise_category.dart';
import '../../domain/entities/exercise_definition.dart';
import '../../domain/entities/exercise_translation.dart';
import '../../domain/entities/one_rm_formula.dart';
import '../../domain/repositories/master_data_repository.dart';

/// `MasterDataRepository` 구현. SQLite + Supabase + SharedPreferences TTL.
class SqliteMasterDataRepository implements MasterDataRepository {
  static const _ttlMs = 24 * 60 * 60 * 1000; // 24h
  static const _attemptThrottleMs = 5 * 60 * 1000; // 5분
  static const _lastFetchedKey = 'master_data_last_fetched_at';
  static const _lastAttemptKey = 'master_data_last_fetch_attempt_at';

  final DatabaseHelper _dbHelper;
  SqliteMasterDataRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<void> ensureFresh({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastFetchedKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && lastMs != null && (now - lastMs) < _ttlMs) {
      return; // TTL within 24h
    }

    // 오프라인 등으로 fetch 가 실패했을 때 5분 내 재시도 차단.
    // 첫 설치 + 오프라인 상태에서 화면 진입마다 무한 네트워크 호출하는 비용을 막는다.
    if (!forceRefresh) {
      final lastAttemptMs = prefs.getInt(_lastAttemptKey);
      if (lastAttemptMs != null && (now - lastAttemptMs) < _attemptThrottleMs) {
        return;
      }
    }
    await prefs.setInt(_lastAttemptKey, now);

    try {
      final results = await Future.wait<List<dynamic>>([
        _supabase.from('exercise_categories').select().eq('is_deleted', false),
        _supabase.from('exercise_category_translations').select(),
        _supabase.from('exercise_definitions').select().eq('is_deleted', false),
        _supabase.from('exercise_translations').select(),
        _supabase.from('one_rm_formulas').select().eq('is_deleted', false),
      ]);

      final categories = results[0]
          .map((r) => ExerciseCategory.fromSupabaseRow(r as Map<String, dynamic>))
          .toList();
      final categoryTranslations = results[1]
          .map((r) => ExerciseCategoryTranslation.fromSupabaseRow(
              r as Map<String, dynamic>))
          .toList();
      final definitions = results[2]
          .map((r) => ExerciseDefinition.fromSupabaseRow(r as Map<String, dynamic>))
          .toList();
      final translations = results[3]
          .map((r) => ExerciseTranslation.fromSupabaseRow(r as Map<String, dynamic>))
          .toList();
      final formulas = results[4]
          .map((r) => OneRMFormula.fromSupabaseRow(r as Map<String, dynamic>))
          .toList();

      // SQLite 전체 replace (트랜잭션)
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        await txn.delete('exercise_translations');
        await txn.delete('exercise_definitions');
        await txn.delete('exercise_category_translations');
        await txn.delete('exercise_categories');
        await txn.delete('one_rm_formulas');

        for (final c in categories) {
          await txn.insert('exercise_categories', c.toSqliteRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final ct in categoryTranslations) {
          await txn.insert(
              'exercise_category_translations', ct.toSqliteRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final d in definitions) {
          await txn.insert('exercise_definitions', d.toSqliteRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final t in translations) {
          await txn.insert('exercise_translations', t.toSqliteRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final f in formulas) {
          await txn.insert('one_rm_formulas', f.toSqliteRow(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      await prefs.setInt(_lastFetchedKey, now);
    } catch (_) {
      // 오프라인 또는 Supabase 오류 — 기존 SQLite 캐시 그대로 사용.
      // last_fetched_at 갱신 안 함 → 다음 진입 시 재시도.
      rethrow;
    }
  }

  @override
  Future<List<ExerciseCategory>> getCategories() async {
    final db = await _dbHelper.database;
    final rows = await db.query('exercise_categories', orderBy: 'display_order ASC');
    return rows.map(ExerciseCategory.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseCategoryTranslation>> getCategoryTranslations(
      String locale) async {
    final db = await _dbHelper.database;
    final rows = await db.query('exercise_category_translations',
        where: 'locale = ?', whereArgs: [locale]);
    return rows.map(ExerciseCategoryTranslation.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseDefinition>> getDefinitions() async {
    final db = await _dbHelper.database;
    final rows = await db.query('exercise_definitions', orderBy: 'exercise_key ASC');
    return rows.map(ExerciseDefinition.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseTranslation>> getTranslations(String locale) async {
    final db = await _dbHelper.database;
    final rows = await db.query('exercise_translations',
        where: 'locale = ?', whereArgs: [locale]);
    return rows.map(ExerciseTranslation.fromSqliteRow).toList();
  }

  @override
  Future<List<OneRMFormula>> getFormulas() async {
    final db = await _dbHelper.database;
    final rows = await db.query('one_rm_formulas');
    return rows.map(OneRMFormula.fromSqliteRow).toList();
  }

  @override
  Future<DateTime?> lastFetchedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastFetchedKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
