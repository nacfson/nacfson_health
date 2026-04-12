import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/exercise/presentation/providers/exercise_provider.dart';
import '../../features/diet/presentation/providers/diet_provider.dart';
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

  return SyncStateNotifier(
    sheetsService: sheetsService,
    prefs: prefs,
    exerciseRepo: exerciseRepo,
    dietRepo: dietRepo,
  );
});

class SyncStateNotifier extends StateNotifier<SyncState> {
  // 외부 서비스를 생성자로 주입받습니다 (Facade 패턴)
  final GoogleSheetsService? _sheetsService;
  final SyncPreferences _prefs;
  final dynamic _exerciseRepo;
  final dynamic _dietRepo;

  SyncStateNotifier({
    required GoogleSheetsService? sheetsService,
    required SyncPreferences prefs,
    required dynamic exerciseRepo,
    required dynamic dietRepo,
  })  : _sheetsService = sheetsService,
        _prefs = prefs,
        _exerciseRepo = exerciseRepo,
        _dietRepo = dietRepo,
        super(SyncState.idle);

  /// 동기화를 수행합니다.
  /// Notifier가 자기 자신의 state를 변경하는 것은 Riverpod이 허용합니다.
  /// (다른 Provider의 상태를 변경하지 않으므로 초기화 충돌이 없습니다)
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
        _prefs,
      );
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
// Sync All Helper (Internal)
// ============================================================================

Future<SyncResult> _syncAll(
  GoogleSheetsService sheetsService,
  dynamic exerciseRepo,
  dynamic dietRepo,
  SyncPreferences prefs,
) async {
  final errors = <String>[];
  int pushed = 0;
  int pulled = 0;

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
          .where((r) => r.syncStatus.name != 'deleted')
          .map((r) => r.uuid)
          .toList();
      if (uuidsToMarkSynced.isNotEmpty) {
        await exerciseRepo.markAsSynced(uuidsToMarkSynced);
      }
    }

    if (dietToPush.isNotEmpty) {
      await sheetsService.batchPushDietRecords(dietToPush);
      
      final uuidsToMarkSynced = dietToPush
          .where((r) => r.syncStatus.name != 'deleted')
          .map((r) => r.uuid)
          .toList();
      if (uuidsToMarkSynced.isNotEmpty) {
        await dietRepo.markAsSynced(uuidsToMarkSynced);
      }
    }

    pushed = exerciseToPush.length + dietToPush.length;
  } catch (e) {
    errors.add('Push 오류: $e');
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

  // 3. Hard Delete: sync_status == deleted
  try {
    await exerciseRepo.hardDeleteSyncedDeleted();
    await dietRepo.hardDeleteSyncedDeleted();
  } catch (e) {
    errors.add('Hard Delete 오류: $e');
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
