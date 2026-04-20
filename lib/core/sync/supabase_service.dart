import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/diet/domain/entities/diet_record.dart' as diet;
import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/exercise/domain/entities/routine_item.dart';
import '../../features/exercise/domain/entities/workout_routine.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/weight/domain/entities/weight_record.dart' as weight;

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // Supabase 테이블은 SQL 마이그레이션으로 미리 생성되므로 no-op
  Future<void> ensureAllRequiredSheets() async {}

  // ==========================================================================
  // Push (Local → Supabase)
  // SyncStatus.created / modified → upsert (is_deleted=false)
  // SyncStatus.deleted           → upsert (is_deleted=true)
  // ==========================================================================

  Future<void> batchPushExerciseRecords(List<ExerciseRecord> records) async {
    if (records.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = records
        .map((r) => {
              'uuid': r.uuid,
              'user_id': userId,
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'updated_at': r.updatedAt.toUtc().toIso8601String(),
              'exercise_type': r.exerciseType,
              'exercise_name': r.exerciseName,
              'current_set': r.currentSet,
              'weight': r.weight,
              'reps': r.reps,
              'rpe': r.rpe,
              'is_deleted': r.syncStatus == SyncStatus.deleted,
            })
        .toList();
    await _client.from('exercise_records').upsert(rows, onConflict: 'uuid');
  }

  Future<void> batchPushDietRecords(List<diet.DietRecord> records) async {
    if (records.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = records
        .map((r) => {
              'uuid': r.uuid,
              'user_id': userId,
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'updated_at': r.updatedAt.toUtc().toIso8601String(),
              'meal_type': r.mealType,
              'food_name': r.foodName,
              'total_calories': r.totalCalories,
              'carbs': r.carbs,
              'protein': r.protein,
              'fat': r.fat,
              'satisfaction': r.satisfaction,
              'memo': r.memo,
              'is_deleted': r.syncStatus == diet.SyncStatus.deleted,
            })
        .toList();
    await _client.from('diet_records').upsert(rows, onConflict: 'uuid');
  }

  Future<void> batchPushWeightRecords(
      List<weight.WeightRecord> records) async {
    if (records.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = records
        .map((r) => {
              'uuid': r.uuid,
              'user_id': userId,
              'timestamp': r.timestamp.toUtc().toIso8601String(),
              'updated_at': r.updatedAt.toUtc().toIso8601String(),
              'weight': r.weight,
              'is_deleted': r.syncStatus == weight.SyncStatus.deleted,
            })
        .toList();
    await _client.from('weight_records').upsert(rows, onConflict: 'uuid');
  }

  Future<void> batchPushTemplates(List<ExerciseTemplate> templates) async {
    if (templates.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = templates
        .map((t) => {
              'uuid': t.uuid,
              'user_id': userId,
              'name': t.name,
              'exercise_type': t.exerciseType,
              'updated_at': t.updatedAt.toUtc().toIso8601String(),
              'is_deleted': t.syncStatus == TemplateSyncStatus.deleted,
            })
        .toList();
    await _client
        .from('exercise_templates')
        .upsert(rows, onConflict: 'uuid');
  }

  Future<void> batchPushWorkoutRoutines(List<WorkoutRoutine> routines) async {
    if (routines.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = routines
        .map((r) => {
              'uuid': r.uuid,
              'user_id': userId,
              'name': r.name,
              // JSONB 컬럼이므로 구조화된 리스트로 전송 (JSON 문자열로 감싸지 않음)
              'items_json': r.items.map((i) => i.toJson()).toList(),
              'created_at': r.createdAt.toUtc().toIso8601String(),
              'updated_at': r.updatedAt.toUtc().toIso8601String(),
              'is_deleted': r.syncStatus == SyncStatus.deleted,
            })
        .toList();
    await _client.from('workout_routines').upsert(rows, onConflict: 'uuid');
  }

  Future<void> batchPushFoodTemplates(List<FoodTemplate> templates) async {
    if (templates.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = templates
        .map((t) => {
              'uuid': t.uuid,
              'user_id': userId,
              'name': t.name,
              'calories': t.calories,
              'carbs': t.carbs,
              'protein': t.protein,
              'fat': t.fat,
              'updated_at': t.updatedAt.toUtc().toIso8601String(),
              'is_deleted': t.syncStatus == FoodTemplateSyncStatus.deleted,
            })
        .toList();
    await _client.from('food_templates').upsert(rows, onConflict: 'uuid');
  }

  // ==========================================================================
  // Pull (Supabase → Local) — is_deleted=false 레코드만 반환
  // RLS가 현재 사용자 데이터만 반환하므로 user_id 필터 불필요
  // ==========================================================================

  Future<List<ExerciseRecord>> readExerciseRecordsDelta(
      {DateTime? since}) async {
    var query = _client
        .from('exercise_records')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List).map((r) => _rowToExerciseRecord(r as Map<String, dynamic>)).toList();
  }

  Future<List<diet.DietRecord>> readDietRecordsDelta(
      {DateTime? since}) async {
    var query = _client
        .from('diet_records')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List).map((r) => _rowToDietRecord(r as Map<String, dynamic>)).toList();
  }

  Future<List<weight.WeightRecord>> readWeightRecordsDelta(
      {DateTime? since}) async {
    var query = _client
        .from('weight_records')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List).map((r) => _rowToWeightRecord(r as Map<String, dynamic>)).toList();
  }

  Future<List<ExerciseTemplate>> readTemplatesDelta(
      {DateTime? since}) async {
    var query = _client
        .from('exercise_templates')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List).map((r) => _rowToExerciseTemplate(r as Map<String, dynamic>)).toList();
  }

  Future<List<FoodTemplate>> readFoodTemplatesDelta(
      {DateTime? since}) async {
    var query = _client
        .from('food_templates')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List).map((r) => _rowToFoodTemplate(r as Map<String, dynamic>)).toList();
  }

  Future<List<WorkoutRoutine>> readWorkoutRoutinesDelta(
      {DateTime? since}) async {
    var query = _client
        .from('workout_routines')
        .select()
        .eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List)
        .map((r) => _rowToWorkoutRoutine(r as Map<String, dynamic>))
        .toList();
  }

  // ==========================================================================
  // Row → Entity 변환
  // ==========================================================================

  ExerciseRecord _rowToExerciseRecord(Map<String, dynamic> row) {
    return ExerciseRecord(
      uuid: row['uuid'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: SyncStatus.synced,
      exerciseType: row['exercise_type'] as String,
      exerciseName: row['exercise_name'] as String,
      currentSet: row['current_set'] as int,
      weight: (row['weight'] as num).toDouble(),
      reps: row['reps'] as int,
      rpe: (row['rpe'] as num).toDouble(),
    );
  }

  diet.DietRecord _rowToDietRecord(Map<String, dynamic> row) {
    return diet.DietRecord(
      uuid: row['uuid'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: diet.SyncStatus.synced,
      mealType: row['meal_type'] as String,
      foodName: row['food_name'] as String,
      totalCalories: row['total_calories'] as int,
      carbs: (row['carbs'] as num).toDouble(),
      protein: (row['protein'] as num).toDouble(),
      fat: (row['fat'] as num).toDouble(),
      satisfaction: row['satisfaction'] as int,
      memo: row['memo'] as String?,
    );
  }

  weight.WeightRecord _rowToWeightRecord(Map<String, dynamic> row) {
    return weight.WeightRecord(
      uuid: row['uuid'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: weight.SyncStatus.synced,
      weight: (row['weight'] as num).toDouble(),
    );
  }

  ExerciseTemplate _rowToExerciseTemplate(Map<String, dynamic> row) {
    return ExerciseTemplate(
      uuid: row['uuid'] as String,
      name: row['name'] as String,
      exerciseType: (row['exercise_type'] as String?) ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: TemplateSyncStatus.synced,
    );
  }

  WorkoutRoutine _rowToWorkoutRoutine(Map<String, dynamic> row) {
    final raw = row['items_json'];
    final List itemsList = raw is String
        ? (jsonDecode(raw) as List)
        : (raw is List ? raw : const []);
    final items = itemsList
        .map((e) => RoutineItem.fromJson(
              (e as Map).cast<String, dynamic>(),
            ))
        .toList();
    return WorkoutRoutine(
      uuid: row['uuid'] as String,
      name: row['name'] as String,
      items: items,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: SyncStatus.synced,
    );
  }

  FoodTemplate _rowToFoodTemplate(Map<String, dynamic> row) {
    return FoodTemplate(
      uuid: row['uuid'] as String,
      name: row['name'] as String,
      calories: row['calories'] as int,
      carbs: (row['carbs'] as num).toDouble(),
      protein: (row['protein'] as num).toDouble(),
      fat: (row['fat'] as num).toDouble(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      syncStatus: FoodTemplateSyncStatus.synced,
    );
  }
}
