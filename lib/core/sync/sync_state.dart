import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/diet/presentation/providers/diet_provider.dart';
import '../../features/exercise/presentation/providers/exercise_provider.dart';
import '../../features/settings/data/repositories/exercise_template_repository.dart';
import '../../features/settings/data/repositories/food_template_repository.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/settings/presentation/providers/exercise_template_provider.dart';
import '../../features/settings/presentation/providers/food_template_provider.dart';
import 'google_auth_service.dart';
import 'google_sheets_service.dart';
import 'sync_preferences.dart';

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
// Provider: Spreadsheet ID
// ============================================================================

final spreadsheetIdProvider = StateProvider<String?>((ref) {
  return ref.watch(syncPreferencesProvider).spreadsheetId;
});

// ============================================================================
// Provider: Last Sync Time
// ============================================================================

final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  return ref.watch(syncPreferencesProvider).lastSyncTime;
});

// ============================================================================
// Provider: GoogleAuthService
// ============================================================================

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

// ============================================================================
// Provider: GoogleSheetsService
// ============================================================================

final googleSheetsServiceProvider = Provider<GoogleSheetsService?>((ref) {
  final authService = ref.watch(googleAuthServiceProvider);
  final spreadsheetId = ref.watch(spreadsheetIdProvider);

  if (spreadsheetId == null) {
    return null;
  }

  return GoogleSheetsService(authService, spreadsheetId);
});

// ============================================================================
// Provider: SyncStateNotifier
// ============================================================================

final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  // 생성자 주입(DI) — Provider 빌드 시 종속성을 미리 읽어서 Notifier에 전달합니다.
  // ref.read를 사용하는 이유: Provider 초기화 중에는 watch 구독이 아닌
  // 일회성 읽기만 허용되기 때문입니다.
  final sheetsService = ref.read(googleSheetsServiceProvider);
  final prefs = ref.read(syncPreferencesProvider);
  final exerciseRepo = ref.read(exerciseRepositoryProvider);
  final dietRepo = ref.read(dietRepositoryProvider);
  final exerciseNotifier = ref.read(exerciseRecordsProvider.notifier);
  final dietNotifier = ref.read(dietRecordsProvider.notifier);
  final templateRepo = ref.read(exerciseTemplateRepositoryProvider);
  final templateNotifier = ref.read(exerciseTemplatesProvider.notifier);
  final foodTemplateRepo = ref.read(foodTemplateRepositoryProvider);
  final foodTemplateNotifier = ref.read(foodTemplatesProvider.notifier);

  return SyncStateNotifier(
    sheetsService: sheetsService,
    prefs: prefs,
    exerciseRepo: exerciseRepo,
    dietRepo: dietRepo,
    exerciseNotifier: exerciseNotifier,
    dietNotifier: dietNotifier,
    templateRepo: templateRepo,
    templateNotifier: templateNotifier,
    foodTemplateRepo: foodTemplateRepo,
    foodTemplateNotifier: foodTemplateNotifier,
  );
});

class SyncStateNotifier extends StateNotifier<SyncState> {
  // 외부 서비스를 생성자로 주입받습니다 (Facade 패턴)
  final GoogleSheetsService? _sheetsService;
  final SyncPreferences _prefs;
  final dynamic _exerciseRepo;
  final dynamic _dietRepo;
  final ExerciseNotifier _exerciseNotifier;
  final DietNotifier _dietNotifier;
  final ExerciseTemplateRepository _templateRepo;
  final ExerciseTemplateNotifier _templateNotifier;
  final FoodTemplateRepository _foodTemplateRepo;
  final FoodTemplateNotifier _foodTemplateNotifier;

  SyncStateNotifier({
    required GoogleSheetsService? sheetsService,
    required SyncPreferences prefs,
    required dynamic exerciseRepo,
    required dynamic dietRepo,
    required ExerciseNotifier exerciseNotifier,
    required DietNotifier dietNotifier,
    required ExerciseTemplateRepository templateRepo,
    required ExerciseTemplateNotifier templateNotifier,
    required FoodTemplateRepository foodTemplateRepo,
    required FoodTemplateNotifier foodTemplateNotifier,
  })  : _sheetsService = sheetsService,
        _prefs = prefs,
        _exerciseRepo = exerciseRepo,
        _dietRepo = dietRepo,
        _exerciseNotifier = exerciseNotifier,
        _dietNotifier = dietNotifier,
        _templateRepo = templateRepo,
        _templateNotifier = templateNotifier,
        _foodTemplateRepo = foodTemplateRepo,
        _foodTemplateNotifier = foodTemplateNotifier,
        super(SyncState.idle);

  /// 동기화를 수행합니다.
  /// 완료 후 ExerciseNotifier와 DietNotifier를 갱신해 UI를 최신 상태로 반영합니다.
  Future<SyncResult> performSync() async {
    if (_sheetsService == null) {
      throw Exception('Google Sheets가 연동되지 않았습니다');
    }

    // 자기 자신의 state 변경 → Riverpod 규칙상 완전히 합법
    state = SyncState.syncing;

    try {
      final result = await _syncAll(
        _sheetsService,
        _exerciseRepo,
        _dietRepo,
        _templateRepo,
        _foodTemplateRepo,
        _prefs,
      );
      // 동기화 완료 후 UI 상태를 DB 최신 데이터로 갱신
      await Future.wait([
        _exerciseNotifier.refresh(),
        _dietNotifier.refresh(),
        _templateNotifier.refresh(),
        _foodTemplateNotifier.refresh(),
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
// Provider: Is Signed In
// ============================================================================

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(googleAuthServiceProvider).isSignedIn;
});

// ============================================================================
// Provider: Current Account
// ============================================================================

final currentAccountProvider = Provider<dynamic>((ref) {
  return ref.watch(googleAuthServiceProvider).currentAccount;
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

class NutritionTargets {
  final int calories;
  final double carbs;
  final double protein;
  final double fat;

  const NutritionTargets({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  NutritionTargets copyWith({
    int? calories,
    double? carbs,
    double? protein,
    double? fat,
  }) =>
      NutritionTargets(
        calories: calories ?? this.calories,
        carbs: carbs ?? this.carbs,
        protein: protein ?? this.protein,
        fat: fat ?? this.fat,
      );
}

class NutritionTargetsNotifier extends StateNotifier<NutritionTargets> {
  final SyncPreferences _prefs;

  NutritionTargetsNotifier(this._prefs)
      : super(NutritionTargets(
          calories: _prefs.targetCalories,
          carbs: _prefs.targetCarbs,
          protein: _prefs.targetProtein,
          fat: _prefs.targetFat,
        ));

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
    StateNotifierProvider<NutritionTargetsNotifier, NutritionTargets>((ref) {
  return NutritionTargetsNotifier(ref.read(syncPreferencesProvider));
});

// ============================================================================
// Sync All Helper (Internal)
// ============================================================================

Future<SyncResult> _syncAll(
  GoogleSheetsService sheetsService,
  dynamic exerciseRepo,
  dynamic dietRepo,
  ExerciseTemplateRepository templateRepo,
  FoodTemplateRepository foodTemplateRepo,
  SyncPreferences prefs,
) async {
  final errors = <String>[];
  int pushed = 0;
  int pulled = 0;

  // 0. 필수 시트 존재 보장 (멱등 — 없는 시트만 생성)
  try {
    await sheetsService.ensureAllRequiredSheets();
  } catch (e) {
    errors.add('시트 초기화 오류: $e');
  }

  // 1. Push: 로컬 → 시트
  try {
    final pendingExercise = await exerciseRepo.getPendingSync();
    final pendingDiet = await dietRepo.getPendingSync();

    final exerciseToPush = pendingExercise; // 삭제 대상도 시트 연동을 위해 포함
    final dietToPush = pendingDiet;

    if (exerciseToPush.isNotEmpty) {
      await sheetsService.batchPushExerciseRecords(exerciseToPush);
      
      // 시트에 업로드가 끝난 후, 삭제(deleted) 상태가 아닌 것만 synced 로 상태 변경
      // 삭제 상태인 항목은 그대로 두어 이후 step 3 (hardDelete) 에서 완전히 로컬 삭제되도록 유도
      final uuidsToMarkSynced = exerciseToPush
          .where((r) => r.syncStatus.value != 3) // 3 = SyncStatus.deleted
          .map<String>((r) => r.uuid as String)
          .toList();
      if (uuidsToMarkSynced.isNotEmpty) {
        await exerciseRepo.markAsSynced(uuidsToMarkSynced);
      }
    }

    if (dietToPush.isNotEmpty) {
      await sheetsService.batchPushDietRecords(dietToPush);
      
      final uuidsToMarkSynced = dietToPush
          .where((r) => r.syncStatus.value != 3) // 3 = SyncStatus.deleted
          .map<String>((r) => r.uuid as String)
          .toList();
      if (uuidsToMarkSynced.isNotEmpty) {
        await dietRepo.markAsSynced(uuidsToMarkSynced);
      }
    }

    pushed = exerciseToPush.length + dietToPush.length;
  } catch (e) {
    errors.add('Push 오류: $e');
  }

  // 1-3. 템플릿 Push: 로컬 → 시트
  try {
    final pendingTemplates = await templateRepo.getPendingSync();
    if (pendingTemplates.isNotEmpty) {
      await sheetsService.batchPushTemplates(pendingTemplates);
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
    errors.add('템플릿 Push 오류: $e');
  }

  // 1-4. 음식 템플릿 Push: 로컬 → 시트
  try {
    final pendingFoodTemplates = await foodTemplateRepo.getPendingSync();
    if (pendingFoodTemplates.isNotEmpty) {
      await sheetsService.batchPushFoodTemplates(pendingFoodTemplates);
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

  // 2. Pull: 시트 → 로컬
  try {
    final lastSync = prefs.lastSyncTime;

    final remoteExercise =
        await sheetsService.readExerciseRecordsDelta(since: lastSync);
    final remoteDiet = await sheetsService.readDietRecordsDelta(since: lastSync);

    await exerciseRepo.mergeRemoteRecords(remoteExercise);
    await dietRepo.mergeRemoteRecords(remoteDiet);

    pulled = remoteExercise.length + remoteDiet.length;
  } catch (e) {
    errors.add('Pull 오류: $e');
  }

  // 2-3. 템플릿 Pull: 시트 → 로컬
  try {
    final lastSync = prefs.lastSyncTime;
    final remoteTemplates =
        await sheetsService.readTemplatesDelta(since: lastSync);
    await templateRepo.mergeRemoteTemplates(remoteTemplates);
    pulled += remoteTemplates.length;
  } catch (e) {
    errors.add('템플릿 Pull 오류: $e');
  }

  // 2-4. 음식 템플릿 Pull: 시트 → 로컬
  try {
    final lastSync = prefs.lastSyncTime;
    final remoteFoodTemplates =
        await sheetsService.readFoodTemplatesDelta(since: lastSync);
    await foodTemplateRepo.mergeRemoteTemplates(remoteFoodTemplates);
    pulled += remoteFoodTemplates.length;
  } catch (e) {
    errors.add('음식 템플릿 Pull 오류: $e');
  }

  // 3. Hard Delete: sync_status == deleted
  try {
    await exerciseRepo.hardDeleteSyncedDeleted();
    await dietRepo.hardDeleteSyncedDeleted();
  } catch (e) {
    errors.add('Hard Delete 오류: $e');
  }

  // 3-3. 템플릿 Hard Delete
  try {
    await templateRepo.hardDeleteSyncedDeleted();
  } catch (e) {
    errors.add('템플릿 Hard Delete 오류: $e');
  }

  // 3-4. 음식 템플릿 Hard Delete
  try {
    await foodTemplateRepo.hardDeleteSyncedDeleted();
  } catch (e) {
    errors.add('음식 템플릿 Hard Delete 오류: $e');
  }

  // 4. last_sync_timestamp 업데이트 (완벽하게 성공했을 때만 갱신)
  if (errors.isEmpty) {
    try {
      await prefs.updateLastSyncTimestamp();
    } catch (e) {
      errors.add('Timestamp 업데이트 오류: $e');
    }
  }

  return SyncResult(pushed: pushed, pulled: pulled, errors: errors);
}
