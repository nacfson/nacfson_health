import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/ai/food_vision_provider.dart';
import 'core/sync/sync_preferences.dart';
import 'core/sync/sync_state.dart';
import 'features/exercise/data/rest_notification_service.dart';
import 'features/exercise/data/rest_notification_service_android.dart';
import 'features/exercise/data/rest_notification_service_ios.dart';
import 'shared/providers/user_profile_provider.dart';
import 'features/settings/data/default_exercise_templates.dart';
import 'features/settings/data/repositories/sqlite_exercise_template_repository.dart';
import 'features/settings/domain/entities/exercise_template.dart';
import 'features/settings/presentation/providers/exercise_template_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final prefs = await SharedPreferences.getInstance();
  final syncPrefs = SyncPreferences(prefs);

  // 사용자 프로필 미리 로드 (router가 즉시 올바른 초기값을 사용하도록)
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final heightM = prefs.getDouble('user_height_m') ?? 1.70;

  // Gemini 호출 카운트 미리 로드 (사진 분석 하루 상한 체크용)
  final foodVisionCounts = await FoodVisionCallCountNotifier.load();

  // SharedPreferences 템플릿 → SQLite 1회 마이그레이션 (Web 환경 제외)
  if (!kIsWeb) {
    final legacyTemplates = syncPrefs.exerciseTemplates;
    if (legacyTemplates.isNotEmpty) {
      final templateRepo = SqliteExerciseTemplateRepository();
      for (final name in legacyTemplates) {
        await templateRepo.add(ExerciseTemplate(
          uuid: '',
          name: name,
          updatedAt: DateTime.now(),
        ));
      }
      await syncPrefs.clearExerciseTemplates();
    }

    // 기본 운동 템플릿 사전 시드 — Provider lazy bootstrap 과의 race condition 방지.
    // FAB 첫 탭 시 ref.read(exerciseTemplatesProvider) 가 동기적으로 호출되므로
    // 앱 시작 전에 SQLite 에 16개 기본 템플릿을 물려 둔다.
    final seedFlag =
        prefs.getBool(ExerciseTemplateNotifier.seedFlagKey) ?? false;
    if (!seedFlag) {
      final repo = SqliteExerciseTemplateRepository();
      await repo.seedDefaults(kDefaultExerciseTemplates);
      await prefs.setBool(ExerciseTemplateNotifier.seedFlagKey, true);
    }
  }

  final restService = _createRestNotificationService();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        syncPreferencesProvider.overrideWithValue(syncPrefs),
        // 미리 로드한 값으로 초기화 → 비동기 _load() 제거, 플리커 없음
        onboardingDoneProvider.overrideWith((ref) => OnboardingNotifier(onboardingDone)),
        heightMProvider.overrideWith((ref) => HeightNotifier(heightM)),
        foodVisionCallCountProvider.overrideWith(
          (ref) => FoodVisionCallCountNotifier(foodVisionCounts),
        ),
        restNotificationServiceProvider.overrideWithValue(restService),
      ],
      child: const NacfsonHealthAppWithSync(),
    ),
  );
}

/// 플랫폼별 RestNotificationService 인스턴스를 생성합니다.
/// Web/macOS/Linux/Windows 등 지원 범위 밖에서는 Noop 구현으로 안전 fallback.
RestNotificationService _createRestNotificationService() {
  if (kIsWeb) return NoopRestNotificationService();
  try {
    if (Platform.isIOS) return RestNotificationServiceIOS();
    if (Platform.isAndroid) return RestNotificationServiceAndroid();
  } catch (_) {
    // Platform 접근 실패 시 안전 fallback.
  }
  return NoopRestNotificationService();
}

class NacfsonHealthAppWithSync extends ConsumerStatefulWidget {
  const NacfsonHealthAppWithSync({super.key});

  @override
  ConsumerState<NacfsonHealthAppWithSync> createState() =>
      _NacfsonHealthAppWithSyncState();
}

class _NacfsonHealthAppWithSyncState
    extends ConsumerState<NacfsonHealthAppWithSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerSync();
    }
  }

  Future<void> _triggerSync() async {
    final isSignedIn = ref.read(isSignedInProvider);
    if (isSignedIn) {
      ref.read(syncStateProvider.notifier).performSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NacfsonHealthApp();
  }
}
