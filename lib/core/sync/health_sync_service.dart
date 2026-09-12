import 'dart:convert';

import '../../features/diet/domain/entities/diet_record.dart';
import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/exercise/domain/entities/routine_item.dart';
import '../../features/exercise/domain/entities/workout_routine.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/weight/domain/entities/weight_record.dart';
import 'health_api_client.dart';
import 'health_auth_service.dart';
import 'sync_status.dart';

/// health-web sync facade — same method surface as the former SupabaseService.
class HealthSyncService {
  HealthSyncService({HealthApiClient? api}) : _api = api ?? HealthApiClient();

  final HealthApiClient _api;

  void attachToken(String? token) => _api.setBearerToken(token);

  Future<void> ensureAllRequiredSheets() async {}

  Future<void> batchPushExerciseRecords(List<ExerciseRecord> records) =>
      _push('exercise_records', records.map(_exerciseRow).toList());

  Future<void> batchPushDietRecords(List<DietRecord> records) =>
      _push('diet_records', records.map(_dietRow).toList());

  Future<void> batchPushWeightRecords(List<WeightRecord> records) =>
      _push('weight_records', records.map(_weightRow).toList());

  Future<void> batchPushTemplates(List<ExerciseTemplate> templates) =>
      _push('exercise_templates', templates.map(_exerciseTemplateRow).toList());

  Future<void> batchPushFoodTemplates(List<FoodTemplate> templates) =>
      _push('food_templates', templates.map(_foodTemplateRow).toList());

  Future<void> batchPushWorkoutRoutines(List<WorkoutRoutine> routines) =>
      _push('workout_routines', routines.map(_routineRow).toList());

  Future<List<ExerciseRecord>> readExerciseRecordsDelta({DateTime? since}) async {
    final rows = await _api.pullSync('exercise_records', since: since);
    return rows.map(_exerciseFromRow).toList();
  }

  Future<List<DietRecord>> readDietRecordsDelta({DateTime? since}) async {
    final rows = await _api.pullSync('diet_records', since: since);
    return rows.map(_dietFromRow).toList();
  }

  Future<List<WeightRecord>> readWeightRecordsDelta({DateTime? since}) async {
    final rows = await _api.pullSync('weight_records', since: since);
    return rows.map(_weightFromRow).toList();
  }

  Future<List<ExerciseTemplate>> readTemplatesDelta({DateTime? since}) async {
    final rows = await _api.pullSync('exercise_templates', since: since);
    return rows.map(_exerciseTemplateFromRow).toList();
  }

  Future<List<FoodTemplate>> readFoodTemplatesDelta({DateTime? since}) async {
    final rows = await _api.pullSync('food_templates', since: since);
    return rows.map(_foodTemplateFromRow).toList();
  }

  Future<List<WorkoutRoutine>> readWorkoutRoutinesDelta({DateTime? since}) async {
    final rows = await _api.pullSync('workout_routines', since: since);
    return rows.map(_routineFromRow).toList();
  }

  Future<Map<String, dynamic>> fetchMasterBundle() => _api.fetchMasterBundle();

  Future<void> _push(String resource, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final token = sharedHealthAuth().accessToken;
    _api.setBearerToken(token);
    await _api.pushSync(resource, items);
  }

  Map<String, dynamic> _exerciseRow(ExerciseRecord r) => {
        'uuid': r.uuid,
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

  ExerciseRecord _exerciseFromRow(Map<String, dynamic> row) => ExerciseRecord(
        uuid: row['uuid'] as String,
        timestamp: DateTime.parse((row['timestamp'] ?? row['recorded_at']) as String)
            .toLocal(),
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

  Map<String, dynamic> _dietRow(DietRecord r) => {
        'uuid': r.uuid,
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

  DietRecord _dietFromRow(Map<String, dynamic> row) => DietRecord(
        uuid: row['uuid'] as String,
        timestamp: DateTime.parse((row['timestamp'] ?? row['recorded_at']) as String)
            .toLocal(),
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

  Map<String, dynamic> _weightRow(WeightRecord r) => {
        'uuid': r.uuid,
        'timestamp': r.timestamp.toUtc().toIso8601String(),
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'weight': r.weight,
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  WeightRecord _weightFromRow(Map<String, dynamic> row) => WeightRecord(
        uuid: row['uuid'] as String,
        timestamp: DateTime.parse((row['timestamp'] ?? row['recorded_at']) as String)
            .toLocal(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: SyncStatus.synced,
        weight: (row['weight'] as num).toDouble(),
      );

  Map<String, dynamic> _exerciseTemplateRow(ExerciseTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'exercise_type': t.exerciseType,
        'rest_seconds_override': t.restSecondsOverride,
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'is_deleted': t.syncStatus == TemplateSyncStatus.deleted,
      };

  ExerciseTemplate _exerciseTemplateFromRow(Map<String, dynamic> row) =>
      ExerciseTemplate(
        uuid: row['uuid'] as String,
        name: row['name'] as String,
        exerciseType: (row['exercise_type'] as String?) ?? '',
        restSecondsOverride: row['rest_seconds_override'] as int?,
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: TemplateSyncStatus.synced,
      );

  Map<String, dynamic> _foodTemplateRow(FoodTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'calories': t.calories,
        'carbs': t.carbs,
        'protein': t.protein,
        'fat': t.fat,
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'is_deleted': t.syncStatus == TemplateSyncStatus.deleted,
      };

  FoodTemplate _foodTemplateFromRow(Map<String, dynamic> row) => FoodTemplate(
        uuid: row['uuid'] as String,
        name: row['name'] as String,
        calories: row['calories'] as int,
        carbs: (row['carbs'] as num).toDouble(),
        protein: (row['protein'] as num).toDouble(),
        fat: (row['fat'] as num).toDouble(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        syncStatus: TemplateSyncStatus.synced,
      );

  Map<String, dynamic> _routineRow(WorkoutRoutine r) => {
        'uuid': r.uuid,
        'name': r.name,
        'items_json': r.items.map((i) => i.toJson()).toList(),
        'created_at': r.createdAt.toUtc().toIso8601String(),
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'is_deleted': r.syncStatus == SyncStatus.deleted,
      };

  WorkoutRoutine _routineFromRow(Map<String, dynamic> row) {
    final raw = row['items_json'];
    final List itemsList = raw is String
        ? (jsonDecode(raw) as List)
        : (raw is List ? raw : const []);
    final items = itemsList
        .map((e) => RoutineItem.fromJson((e as Map).cast<String, dynamic>()))
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

/// Backward-compatible typedef so call sites named SupabaseService still compile
/// during the rename window. Prefer [HealthSyncService].
typedef SupabaseService = HealthSyncService;
