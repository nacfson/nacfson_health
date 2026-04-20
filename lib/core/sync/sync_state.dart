import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/diet/presentation/providers/diet_provider.dart';
import '../../features/exercise/data/repositories/workout_routine_repository.dart';
import '../../features/exercise/domain/entities/exercise_record.dart'
    show SyncStatus;
import '../../features/exercise/presentation/providers/exercise_provider.dart';
import '../../features/exercise/presentation/providers/workout_routine_provider.dart';
import '../../features/settings/data/repositories/exercise_template_repository.dart';
import '../../features/settings/data/repositories/food_template_repository.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/settings/presentation/providers/exercise_template_provider.dart';
import '../../features/settings/presentation/providers/food_template_provider.dart';
import '../../features/weight/data/repositories/weight_repository.dart';
import '../../features/weight/presentation/providers/weight_provider.dart';
import '../nutrition/nutrition_targets.dart';
import 'google_auth_service.dart';
import 'supabase_service.dart';
import 'sync_preferences.dart';

export '../nutrition/nutrition_targets.dart' show NutritionTargets;

// ============================================================================
// Sync State Enum
// ============================================================================

enum SyncState { idle, syncing, error }

// ============================================================================
// Provider: SyncPreferences
// ============================================================================

final syncPreferencesProvider = Provider<SyncPreferences>((ref) {
  throw UnimplementedError('SyncPreferences는 main.dart에서 오버라이드해야 합니다');
});

// ============================================================================
// Provider: Last Sync Time
// ============================================================================

final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  return ref.watch(syncPreferencesProvider).lastSyncTime;
});

// ============================================================================
// Provider: GoogleAuthService (Supabase 구현체 래퍼)
// ============================================================================

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

// ============================================================================
// Provider: SupabaseService
// ============================================================================

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// ============================================================================
// Provider: Supabase Auth Stream (반응형 로그인 상태)
// ============================================================================

final supabaseAuthStreamProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// ============================================================================
// Provider: SyncStateNotifier
// ============================================================================

final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>((
  ref,
) {
  final supabaseService = ref.read(supabaseServiceProvider);
  final prefs = ref.read(syncPreferencesProvider);
  final exerciseRepo = ref.read(exerciseRepositoryProvider);
  final dietRepo = ref.read(dietRepositoryProvider);
  final weightRepo = ref.read(weightRepositoryProvider);
  final exerciseNotifier = ref.read(exerciseRecordsProvider.notifier);
  final dietNotifier = ref.read(dietRecordsProvider.notifier);
  final weightNotifier = ref.read(weightRecordsProvider.notifier);
  final templateRepo = ref.read(exerciseTemplateRepositoryProvider);
  final templateNotifier = ref.read(exerciseTemplatesProvider.notifier);
  final foodTemplateRepo = ref.read(foodTemplateRepositoryProvider);
  final foodTemplateNotifier = ref.read(foodTemplatesProvider.notifier);
  final workoutRoutineRepo = ref.read(workoutRoutineRepositoryProvider);
  final workoutRoutineNotifier = ref.read(workoutRoutinesProvider.notifier);

  return SyncStateNotifier(
    supabaseService: supabaseService,
    prefs: prefs,
    exerciseRepo: exerciseRepo,
    dietRepo: dietRepo,
    exerciseNotifier: exerciseNotifier,
    dietNotifier: dietNotifier,
    templateRepo: templateRepo,
    templateNotifier: templateNotifier,
    foodTemplateRepo: foodTemplateRepo,
    foodTemplateNotifier: foodTemplateNotifier,
    weightRepo: weightRepo,
    weightNotifier: weightNotifier,
    workoutRoutineRepo: workoutRoutineRepo,
    workoutRoutineNotifier: workoutRoutineNotifier,
  );
});

class SyncStateNotifier extends StateNotifier<SyncState> {
  final SupabaseService _supabaseService;
  final SyncPreferences _prefs;
  final dynamic _exerciseRepo;
  final dynamic _dietRepo;
  final ExerciseNotifier _exerciseNotifier;
  final DietNotifier _dietNotifier;
  final ExerciseTemplateRepository _templateRepo;
  final ExerciseTemplateNotifier _templateNotifier;
  final FoodTemplateRepository _foodTemplateRepo;
  final FoodTemplateNotifier _foodTemplateNotifier;
  final WeightRepository _weightRepo;
  final WeightNotifier _weightNotifier;
  final WorkoutRoutineRepository _workoutRoutineRepo;
  final WorkoutRoutineNotifier _workoutRoutineNotifier;

  SyncStateNotifier({
    required SupabaseService supabaseService,
    required SyncPreferences prefs,
    required dynamic exerciseRepo,
    required dynamic dietRepo,
    required ExerciseNotifier exerciseNotifier,
    required DietNotifier dietNotifier,
    required ExerciseTemplateRepository templateRepo,
    required ExerciseTemplateNotifier templateNotifier,
    required FoodTemplateRepository foodTemplateRepo,
    required FoodTemplateNotifier foodTemplateNotifier,
    required WeightRepository weightRepo,
    required WeightNotifier weightNotifier,
    required WorkoutRoutineRepository workoutRoutineRepo,
    required WorkoutRoutineNotifier workoutRoutineNotifier,
  })  : _supabaseService = supabaseService,
        _prefs = prefs,
        _exerciseRepo = exerciseRepo,
        _dietRepo = dietRepo,
        _exerciseNotifier = exerciseNotifier,
        _dietNotifier = dietNotifier,
        _templateRepo = templateRepo,
        _templateNotifier = templateNotifier,
        _foodTemplateRepo = foodTemplateRepo,
        _foodTemplateNotifier = foodTemplateNotifier,
        _weightRepo = weightRepo,
        _weightNotifier = weightNotifier,
        _workoutRoutineRepo = workoutRoutineRepo,
        _workoutRoutineNotifier = workoutRoutineNotifier,
        super(SyncState.idle);

  Future<SyncResult> performSync() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      throw Exception('로그인이 필요합니다');
    }

    state = SyncState.syncing;

    try {
      final result = await _syncAll(
        _supabaseService,
        _exerciseRepo,
        _dietRepo,
        _templateRepo,
        _foodTemplateRepo,
        _weightRepo,
        _workoutRoutineRepo,
        _prefs,
      );
      await Future.wait<void>([
        _exerciseNotifier.refresh(),
        _dietNotifier.refresh(),
        _weightNotifier.refresh(),
        _templateNotifier.refresh(),
        _foodTemplateNotifier.refresh(),
        _workoutRoutineNotifier.refresh(),
      ]);
      state = SyncState.idle;
      return result;
    } catch (e) {
      state = SyncState.error;
      rethrow;
    }
  }
}

// ============================================================================
// Provider: Is Syncing
// ============================================================================

final isSyncingProvider = Provider<bool>((ref) {
  return ref.watch(syncStateProvider) == SyncState.syncing;
});

// ============================================================================
// Provider: Is Signed In (Supabase auth stream 기반)
// ============================================================================

final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(supabaseAuthStreamProvider);
  return Supabase.instance.client.auth.currentUser != null;
});

// ============================================================================
// Provider: Current Account (Supabase User)
// ============================================================================

final currentAccountProvider = Provider<User?>((ref) {
  ref.watch(supabaseAuthStreamProvider);
  return Supabase.instance.client.auth.currentUser;
});

// ============================================================================
// Provider: Sync Result
// ============================================================================

class SyncResult {
  final int pushed;
  final int pulled;
  final List<String> errors;

  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  String get errorMessage => errors.join(', ');
}

// ============================================================================
// NutritionTargets — 영양 목표값 상태 관리
// ============================================================================
// `NutritionTargets` DTO는 `core/nutrition/nutrition_targets.dart`에 정의되어
// 있으며 이 파일에서 re-export 합니다 (sync 레이어에 결합되지 않도록).

class NutritionTargetsNotifier extends StateNotifier<NutritionTargets> {
  final SyncPreferences _prefs;

  NutritionTargetsNotifier(this._prefs)
      : super(
          NutritionTargets(
            calories: _prefs.targetCalories,
            carbs: _prefs.targetCarbs,
            protein: _prefs.targetProtein,
            fat: _prefs.targetFat,
          ),
        );

  Future<void> update({
    int? calories,
    double? carbs,
    double? protein,
    double? fat,
  }) async {
    if (calories != null) await _prefs.setTargetCalories(calories);
    if (carbs != null) await _prefs.setTargetCarbs(carbs);
    if (protein != null) await _prefs.setTargetProtein(protein);
    if (fat != null) await _prefs.setTargetFat(fat);
    state = NutritionTargets(
      calories: _prefs.targetCalories,
      carbs: _prefs.targetCarbs,
      protein: _prefs.targetProtein,
      fat: _prefs.targetFat,
    );
  }
}

final nutritionTargetsProvider =
    StateNotifierProvider<NutritionTargetsProvider, NutritionTargets>((ref) {
  return NutritionTargetsProvider(ref.read(syncPreferencesProvider));
});

// NutritionTargetsProvider alias to avoid name collision
typedef NutritionTargetsProvider = NutritionTargetsNotifier;

// ============================================================================
// Sync All Helper (Internal)
// ============================================================================

Future<SyncResult> _syncAll(
  SupabaseService supabaseService,
  dynamic exerciseRepo,
  dynamic dietRepo,
  ExerciseTemplateRepository templateRepo,
  FoodTemplateRepository foodTemplateRepo,
  WeightRepository weightRepo,
  WorkoutRoutineRepository workoutRoutineRepo,
  SyncPreferences prefs,
) async {
  final errors = <String>[];
  int pushed = 0;
  int pulled = 0;

  // 1. Push: 로컬 → Supabase
  try {
    final pendingExercise = await exerciseRepo.getPendingSync();
    if (pendingExercise.isNotEmpty) {
      await supabaseService.batchPushExerciseRecords(pendingExercise);
      final uuidsToMark = pendingExercise
          .where((r) => r.syncStatus.value != 3)
          .map<String>((r) => r.uuid as String)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await exerciseRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += (pendingExercise as List).length;
  } catch (e) {
    errors.add('운동 기록 Push 오류: $e');
  }

  try {
    final pendingDiet = await dietRepo.getPendingSync();
    if (pendingDiet.isNotEmpty) {
      await supabaseService.batchPushDietRecords(pendingDiet);
      final uuidsToMark = pendingDiet
          .where((r) => r.syncStatus.value != 3)
          .map<String>((r) => r.uuid as String)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await dietRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += (pendingDiet as List).length;
  } catch (e) {
    errors.add('식단 기록 Push 오류: $e');
  }

  try {
    final pendingWeight = await weightRepo.getPendingSync();
    if (pendingWeight.isNotEmpty) {
      await supabaseService.batchPushWeightRecords(pendingWeight);
      final uuidsToMark = pendingWeight
          .where((r) => r.syncStatus.value != 3)
          .map<String>((r) => r.uuid)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await weightRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += pendingWeight.length;
  } catch (e) {
    errors.add('체중 기록 Push 오류: $e');
  }

  try {
    final pendingTemplates = await templateRepo.getPendingSync();
    if (pendingTemplates.isNotEmpty) {
      await supabaseService.batchPushTemplates(pendingTemplates);
      final uuidsToMark = pendingTemplates
          .where((t) => t.syncStatus != TemplateSyncStatus.deleted)
          .map((t) => t.uuid)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await templateRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += pendingTemplates.length;
  } catch (e) {
    errors.add('운동 템플릿 Push 오류: $e');
  }

  try {
    final pendingFoodTemplates = await foodTemplateRepo.getPendingSync();
    if (pendingFoodTemplates.isNotEmpty) {
      await supabaseService.batchPushFoodTemplates(pendingFoodTemplates);
      final uuidsToMark = pendingFoodTemplates
          .where((t) => t.syncStatus != FoodTemplateSyncStatus.deleted)
          .map((t) => t.uuid)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await foodTemplateRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += pendingFoodTemplates.length;
  } catch (e) {
    errors.add('음식 템플릿 Push 오류: $e');
  }

  try {
    final pendingRoutines = await workoutRoutineRepo.getPendingSync();
    if (pendingRoutines.isNotEmpty) {
      await supabaseService.batchPushWorkoutRoutines(pendingRoutines);
      final uuidsToMark = pendingRoutines
          .where((r) => r.syncStatus != SyncStatus.deleted)
          .map((r) => r.uuid)
          .toList();
      if (uuidsToMark.isNotEmpty) {
        await workoutRoutineRepo.markAsSynced(uuidsToMark);
      }
    }
    pushed += pendingRoutines.length;
  } catch (e) {
    errors.add('운동 루틴 Push 오류: $e');
  }

  // 2. Pull: Supabase → 로컬
  final lastSync = prefs.lastSyncTime;

  try {
    final remoteExercise =
        await supabaseService.readExerciseRecordsDelta(since: lastSync);
    await exerciseRepo.mergeRemoteRecords(remoteExercise);
    pulled += remoteExercise.length;
  } catch (e) {
    errors.add('운동 기록 Pull 오류: $e');
  }

  try {
    final remoteDiet =
        await supabaseService.readDietRecordsDelta(since: lastSync);
    await dietRepo.mergeRemoteRecords(remoteDiet);
    pulled += remoteDiet.length;
  } catch (e) {
    errors.add('식단 기록 Pull 오류: $e');
  }

  try {
    final remoteWeight =
        await supabaseService.readWeightRecordsDelta(since: lastSync);
    await weightRepo.mergeRemoteRecords(remoteWeight);
    pulled += remoteWeight.length;
  } catch (e) {
    errors.add('체중 기록 Pull 오류: $e');
  }

  try {
    final remoteTemplates =
        await supabaseService.readTemplatesDelta(since: lastSync);
    await templateRepo.mergeRemoteTemplates(remoteTemplates);
    pulled += remoteTemplates.length;
  } catch (e) {
    errors.add('운동 템플릿 Pull 오류: $e');
  }

  try {
    final remoteFoodTemplates =
        await supabaseService.readFoodTemplatesDelta(since: lastSync);
    await foodTemplateRepo.mergeRemoteTemplates(remoteFoodTemplates);
    pulled += remoteFoodTemplates.length;
  } catch (e) {
    errors.add('음식 템플릿 Pull 오류: $e');
  }

  try {
    final remoteRoutines =
        await supabaseService.readWorkoutRoutinesDelta(since: lastSync);
    await workoutRoutineRepo.mergeRemoteRoutines(remoteRoutines);
    pulled += remoteRoutines.length;
  } catch (e) {
    errors.add('운동 루틴 Pull 오류: $e');
  }

  // 3. Hard Delete: sync_status == deleted
  try {
    await exerciseRepo.hardDeleteSyncedDeleted();
    await dietRepo.hardDeleteSyncedDeleted();
    await weightRepo.hardDeleteSyncedDeleted();
    await templateRepo.hardDeleteSyncedDeleted();
    await foodTemplateRepo.hardDeleteSyncedDeleted();
    await workoutRoutineRepo.hardDeleteSyncedDeleted();
  } catch (e) {
    errors.add('Hard Delete 오류: $e');
  }

  // 4. last_sync_timestamp 업데이트 (오류 없을 때만)
  if (errors.isEmpty) {
    try {
      await prefs.updateLastSyncTimestamp();
    } catch (e) {
      errors.add('Timestamp 업데이트 오류: $e');
    }
  }

  return SyncResult(pushed: pushed, pulled: pulled, errors: errors);
}
