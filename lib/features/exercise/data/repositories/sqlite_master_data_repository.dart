import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/sync/health_sync_service.dart';
import '../../../../core/sync/health_auth_service.dart';
import '../../domain/entities/exercise_category.dart';
import '../../domain/entities/exercise_definition.dart';
import '../../domain/entities/exercise_translation.dart';
import '../../domain/entities/one_rm_formula.dart';
import '../../domain/repositories/master_data_repository.dart';

/// `MasterDataRepository` 구현. SQLite + health-api master bundle + SharedPreferences TTL.
class SqliteMasterDataRepository implements MasterDataRepository {
  static const _ttlMs = 24 * 60 * 60 * 1000; // 24h
  static const _attemptThrottleMs = 5 * 60 * 1000; // 5분
  static const _lastFetchedKey = 'master_data_last_fetched_at';
  static const _lastAttemptKey = 'master_data_last_fetch_attempt_at';

  final DatabaseHelper _dbHelper;
  final HealthSyncService _sync;

  SqliteMasterDataRepository({
    DatabaseHelper? dbHelper,
    HealthSyncService? sync,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _sync = sync ?? HealthSyncService();

  @override
  Future<void> ensureFresh({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastFetchedKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && lastMs != null && (now - lastMs) < _ttlMs) {
      return;
    }

    if (!forceRefresh) {
      final lastAttemptMs = prefs.getInt(_lastAttemptKey);
      if (lastAttemptMs != null && (now - lastAttemptMs) < _attemptThrottleMs) {
        return;
      }
    }
    await prefs.setInt(_lastAttemptKey, now);

    if (!sharedHealthAuth().isSignedIn) {
      // Offline / signed-out: keep SQLite cache.
      return;
    }

    try {
      _sync.attachToken(sharedHealthAuth().accessToken);
      final bundle = await _sync.fetchMasterBundle();

      final categories = (bundle['categories'] as List<dynamic>)
          .map((r) => ExerciseCategory.fromSupabaseRow(
              (r as Map).cast<String, dynamic>()))
          .toList();
      final categoryTranslations =
          (bundle['category_translations'] as List<dynamic>)
              .map((r) => ExerciseCategoryTranslation.fromSupabaseRow(
                  (r as Map).cast<String, dynamic>()))
              .toList();
      final definitions = (bundle['definitions'] as List<dynamic>)
          .map((r) => ExerciseDefinition.fromSupabaseRow(
              (r as Map).cast<String, dynamic>()))
          .toList();
      final translations = (bundle['translations'] as List<dynamic>)
          .map((r) => ExerciseTranslation.fromSupabaseRow(
              (r as Map).cast<String, dynamic>()))
          .toList();
      final formulas = (bundle['formulas'] as List<dynamic>)
          .map((r) =>
              OneRMFormula.fromSupabaseRow((r as Map).cast<String, dynamic>()))
          .toList();

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
          await txn.insert('exercise_category_translations', ct.toSqliteRow(),
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
      rethrow;
    }
  }

  @override
  Future<List<ExerciseCategory>> getCategories() async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('exercise_categories', orderBy: 'display_order ASC');
    return rows.map(ExerciseCategory.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseCategoryTranslation>> getCategoryTranslations(
      String locale) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'exercise_category_translations',
      where: 'locale = ?',
      whereArgs: [locale],
    );
    return rows.map(ExerciseCategoryTranslation.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseDefinition>> getDefinitions() async {
    final db = await _dbHelper.database;
    final rows = await db.query('exercise_definitions');
    return rows.map(ExerciseDefinition.fromSqliteRow).toList();
  }

  @override
  Future<List<ExerciseTranslation>> getTranslations(String locale) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'exercise_translations',
      where: 'locale = ?',
      whereArgs: [locale],
    );
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
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
