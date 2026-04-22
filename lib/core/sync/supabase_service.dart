import 'dart:convert';

import '../../features/diet/domain/entities/diet_record.dart';
import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/exercise/domain/entities/routine_item.dart';
import '../../features/exercise/domain/entities/workout_routine.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/weight/domain/entities/weight_record.dart';
import 'base_supabase_sync_service.dart';
import 'sync_status.dart';

// ============================================================================
// 도메인별 sync 서브클래스
// 각 클래스는 테이블 이름 + rowFromEntity + rowToEntity 세 훅만 제공한다.
// Push/Pull 의 upsert 방식 · is_deleted=false 필터 · delta 조회는 base 가 담당.
// ============================================================================

class _ExerciseRecordSync extends BaseSupabaseSyncService<ExerciseRecord> {
  @override
  String get tableName => 'exercise_records';

  @override
  Map<String, dynamic> rowFromEntity(ExerciseRecord r, String userId) => {
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
        'set_type': r.setType.value,
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  @override
  ExerciseRecord rowToEntity(Map<String, dynamic> row) => ExerciseRecord(
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
        setType: SetType.fromString(row['set_type'] as String?),
      );
}

class _DietRecordSync extends BaseSupabaseSyncService<DietRecord> {
  @override
  String get tableName => 'diet_records';

  @override
  Map<String, dynamic> rowFromEntity(DietRecord r, String userId) => {
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
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  @override
  DietRecord rowToEntity(Map<String, dynamic> row) => DietRecord(
        uuid: row['uuid'] as String,
        timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: SyncStatus.synced,
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

class _WeightRecordSync extends BaseSupabaseSyncService<WeightRecord> {
  @override
  String get tableName => 'weight_records';

  @override
  Map<String, dynamic> rowFromEntity(WeightRecord r, String userId) => {
        'uuid': r.uuid,
        'user_id': userId,
        'timestamp': r.timestamp.toUtc().toIso8601String(),
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'weight': r.weight,
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  @override
  WeightRecord rowToEntity(Map<String, dynamic> row) => WeightRecord(
        uuid: row['uuid'] as String,
        timestamp: DateTime.parse(row['timestamp'] as String).toLocal(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: SyncStatus.synced,
        weight: (row['weight'] as num).toDouble(),
      );
}

class _ExerciseTemplateSync extends BaseSupabaseSyncService<ExerciseTemplate> {
  @override
  String get tableName => 'exercise_templates';

  @override
  Map<String, dynamic> rowFromEntity(ExerciseTemplate t, String userId) => {
        'uuid': t.uuid,
        'user_id': userId,
        'name': t.name,
        'exercise_type': t.exerciseType,
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'is_deleted': t.syncStatus == TemplateSyncStatus.deleted,
      };

  @override
  ExerciseTemplate rowToEntity(Map<String, dynamic> row) => ExerciseTemplate(
        uuid: row['uuid'] as String,
        name: row['name'] as String,
        exerciseType: (row['exercise_type'] as String?) ?? '',
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: TemplateSyncStatus.synced,
      );
}

class _FoodTemplateSync extends BaseSupabaseSyncService<FoodTemplate> {
  @override
  String get tableName => 'food_templates';

  @override
  Map<String, dynamic> rowFromEntity(FoodTemplate t, String userId) => {
        'uuid': t.uuid,
        'user_id': userId,
        'name': t.name,
        'calories': t.calories,
        'carbs': t.carbs,
        'protein': t.protein,
        'fat': t.fat,
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'is_deleted': t.syncStatus == TemplateSyncStatus.deleted,
      };

  @override
  FoodTemplate rowToEntity(Map<String, dynamic> row) => FoodTemplate(
        uuid: row['uuid'] as String,
        name: row['name'] as String,
        calories: row['calories'] as int,
        carbs: (row['carbs'] as num).toDouble(),
        protein: (row['protein'] as num).toDouble(),
        fat: (row['fat'] as num).toDouble(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: TemplateSyncStatus.synced,
      );
}

class _WorkoutRoutineSync extends BaseSupabaseSyncService<WorkoutRoutine> {
  @override
  String get tableName => 'workout_routines';

  @override
  Map<String, dynamic> rowFromEntity(WorkoutRoutine r, String userId) => {
        'uuid': r.uuid,
        'user_id': userId,
        'name': r.name,
        // JSONB 컬럼이므로 구조화된 리스트로 전송 (JSON 문자열로 감싸지 않음)
        'items_json': r.items.map((i) => i.toJson()).toList(),
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  @override
  WorkoutRoutine rowToEntity(Map<String, dynamic> row) {
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
}

// ============================================================================
// Public Facade — 기존 호출부(sync_state.dart)와의 시그니처를 보존한다.
// 6개 subclass 인스턴스로 forwarding 만 수행.
// ============================================================================

class SupabaseService {
  final _exerciseSync = _ExerciseRecordSync();
  final _dietSync = _DietRecordSync();
  final _weightSync = _WeightRecordSync();
  final _exerciseTemplateSync = _ExerciseTemplateSync();
  final _foodTemplateSync = _FoodTemplateSync();
  final _workoutRoutineSync = _WorkoutRoutineSync();

  // Supabase 테이블은 SQL 마이그레이션으로 미리 생성되므로 no-op
  Future<void> ensureAllRequiredSheets() async {}

  // ── Push ─────────────────────────────────────────────────────────────────

  Future<void> batchPushExerciseRecords(List<ExerciseRecord> records) =>
      _exerciseSync.batchPush(records);

  Future<void> batchPushDietRecords(List<DietRecord> records) =>
      _dietSync.batchPush(records);

  Future<void> batchPushWeightRecords(List<WeightRecord> records) =>
      _weightSync.batchPush(records);

  Future<void> batchPushTemplates(List<ExerciseTemplate> templates) =>
      _exerciseTemplateSync.batchPush(templates);

  Future<void> batchPushFoodTemplates(List<FoodTemplate> templates) =>
      _foodTemplateSync.batchPush(templates);

  Future<void> batchPushWorkoutRoutines(List<WorkoutRoutine> routines) =>
      _workoutRoutineSync.batchPush(routines);

  // ── Pull ─────────────────────────────────────────────────────────────────

  Future<List<ExerciseRecord>> readExerciseRecordsDelta({DateTime? since}) =>
      _exerciseSync.readDelta(since: since);

  Future<List<DietRecord>> readDietRecordsDelta({DateTime? since}) =>
      _dietSync.readDelta(since: since);

  Future<List<WeightRecord>> readWeightRecordsDelta({DateTime? since}) =>
      _weightSync.readDelta(since: since);

  Future<List<ExerciseTemplate>> readTemplatesDelta({DateTime? since}) =>
      _exerciseTemplateSync.readDelta(since: since);

  Future<List<FoodTemplate>> readFoodTemplatesDelta({DateTime? since}) =>
      _foodTemplateSync.readDelta(since: since);

  Future<List<WorkoutRoutine>> readWorkoutRoutinesDelta({DateTime? since}) =>
      _workoutRoutineSync.readDelta(since: since);
}
