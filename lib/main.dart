import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/ai/food_vision_provider.dart';
import 'core/router/app_router.dart';
import 'core/sync/health_auth_service.dart';
import 'core/sync/sync_preferences.dart';
import 'core/sync/sync_state.dart';
import 'core/widget/home_widget_service.dart';
import 'features/activity/presentation/providers/activity_provider.dart';
import 'features/diet/presentation/providers/diet_provider.dart';
import 'features/exercise/presentation/providers/exercise_provider.dart';
import 'features/exercise/data/rest_notification_service.dart';
import 'features/exercise/data/rest_notification_service_android.dart';
import 'features/exercise/data/rest_notification_service_ios.dart';
import 'shared/providers/user_profile_provider.dart';
import 'features/settings/data/default_exercise_templates.dart';
import 'features/settings/data/repositories/sqlite_exercise_template_repository.dart';
import 'features/settings/data/repositories/sqlite_food_template_repository.dart';
import 'features/settings/domain/entities/exercise_template.dart';
import 'features/settings/domain/entities/food_template.dart';
import 'features/settings/presentation/providers/exercise_template_provider.dart';
import 'features/settings/presentation/providers/food_template_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await sharedHealthAuth().restoreSession();

  final prefs = await SharedPreferences.getInstance();
  final syncPrefs = SyncPreferences(prefs);

  // v2.5 이전 사용자 프로필 키 (user_age_group, fitness_goal='lean_mass')를 신규 스키마로 1회 이관
  await syncPrefs.migrateLegacyProfile();

  // 사용자 프로필 미리 로드 (router가 즉시 올바른 초기값을 사용하도록)
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final heightM = prefs.getDouble('user_height_m') ?? 1.70;

  // Gemini 호출 카운트 미리 로드 (사진 분석 하루 상한 체크용)
  final foodVisionCounts = await FoodVisionCallCountNotifier.load();

  // SharedPreferences 템플릿 → SQLite 1회 마이그레이션 (Web 환경 제외)
  // 및 시트 오픈 플리커 방지를 위한 템플릿 사전 로드.
  List<ExerciseTemplate> initialExerciseTemplates = const [];
  List<FoodTemplate> initialFoodTemplates = const [];
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

    // 운동/식단 템플릿 사전 로드 — 시트 첫 오픈 시 빈 리스트 플리커 제거.
    // Provider 는 withInitial 생성자로 이 값을 직접 주입받아 _bootstrap/_load 를 생략한다.
    initialExerciseTemplates =
        await SqliteExerciseTemplateRepository().getAll();
    initialFoodTemplates = await SqliteFoodTemplateRepository().getAll();
  }

  final restService = _createRestNotificationService();

  // iOS 홈스크린 위젯용 App Group 등록 (영양/운동 잔디).
  // 실패해도 앱 흐름에 영향 없으므로 fire-and-forget.
  if (!kIsWeb) {
    try {
      if (Platform.isIOS) {
        await HomeWidgetService.initialize();
      }
    } catch (_) {
      // App Group 미등록 등 — 위젯만 비활성. 앱 동작은 유지.
    }
  }

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
        // 사전 로드된 템플릿 리스트를 Notifier 에 직접 주입 → 시트 첫 프레임부터 리스트 표시.
        exerciseTemplatesProvider.overrideWith((ref) =>
            ExerciseTemplateNotifier.withInitial(
              ref.watch(exerciseTemplateRepositoryProvider),
              ref.watch(sharedPreferencesProvider),
              initialExerciseTemplates,
            )),
        foodTemplatesProvider.overrideWith((ref) =>
            FoodTemplateNotifier.withInitial(
              ref.watch(foodTemplateRepositoryProvider),
              initialFoodTemplates,
            )),
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
    _registerHomeWidgetSync();
    _registerWidgetTapListener();
  }

  /// 홈스크린 위젯 탭으로 들어온 URI 를 GoRouter 로 라우팅한다.
  ///
  /// iOS 위젯의 `.widgetURL(URL(string: "nacfsonhealth://<host>"))` 가 트리거하면
  /// home_widget 플러그인이 두 채널로 알린다:
  ///   - cold launch  : `HomeWidget.initiallyLaunchedFromHomeWidget()` (1회)
  ///   - warm launch  : `HomeWidget.widgetClicked` Stream
  ///
  /// 매핑은 위젯 정의(NutritionWidget / WorkoutHeatmapWidget)와 일치해야 한다.
  void _registerWidgetTapListener() {
    if (kIsWeb) return;
    try {
      if (!Platform.isIOS) return;
    } catch (_) {
      return;
    }

    void handle(Uri? uri) {
      if (uri == null) return;
      // Auth callback (`nacfsonhealth://login-callback`) and other non-widget hosts.
      if (uri.scheme != 'nacfsonhealth') return;
      if (uri.host == 'login-callback') {
        unawaited(sharedHealthAuth().completeFromRedirect(uri));
        return;
      }
      final route = switch (uri.host) {
        'diet' => '/diet',
        'summary' => '/summary',
        'exercise' => '/exercise',
        'weight' => '/weight',
        'settings' => '/settings',
        _ => null,
      };
      if (route == null) return;
      ref.read(appRouterProvider).go(route);
    }

    // Cold launch — 라우터/첫 프레임이 준비된 뒤에 이동시켜야 redirect 와 충돌 없음.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        handle(await HomeWidget.initiallyLaunchedFromHomeWidget());
      } catch (_) {
        // 위젯 미설치 등 — 무시.
      }
    });

    // Warm launch — 앱이 백그라운드에 있다 위젯 탭으로 복귀한 경우.
    HomeWidget.widgetClicked.listen(handle);
  }

  /// 홈스크린 위젯(영양 / 운동 잔디) 데이터 동기화 리스너 등록.
  ///
  /// - 식단 합계, 영양 목표, 운동 본세트 볼륨이 변할 때마다 App Group UserDefaults
  ///   를 갱신하고 WidgetKit 에 reload 신호를 보낸다.
  /// - iOS 외 플랫폼은 home_widget 패키지가 no-op 처리하지만 호출 자체를 막아 비용 절감.
  /// - 호출 실패는 무시(fire-and-forget) — 위젯 미설치/엔타이틀먼트 누락 시도 앱 흐름 영향 없음.
  void _registerHomeWidgetSync() {
    if (kIsWeb) return;
    try {
      if (!Platform.isIOS) return;
    } catch (_) {
      // Platform 접근 실패 (테스트/desktop 등) — 홈 위젯 동기화 비활성
      return;
    }

    void pushNutrition() {
      final s = ref.read(todayDietSummaryProvider);
      final t = ref.read(nutritionTargetsProvider);
      unawaited(
        HomeWidgetService.update(
          calories: s.kcal,
          targetCalories: t.calories,
          carbs: s.carbs,
          targetCarbs: t.carbs,
          protein: s.protein,
          targetProtein: t.protein,
          fat: s.fat,
          targetFat: t.fat,
        ).catchError((_) {}),
      );
    }

    void pushHeatmap() {
      final data = ref.read(heatmapDataProvider);
      unawaited(
        HomeWidgetService.updateHeatmap(volumeByDay: data).catchError((_) {}),
      );
    }

    // 1. 영양: 합계 또는 목표 둘 중 하나라도 변하면 갱신
    ref.listenManual(
      todayDietSummaryProvider,
      (_, _) => pushNutrition(),
      fireImmediately: true,
    );
    ref.listenManual(
      nutritionTargetsProvider,
      (_, _) => pushNutrition(),
    );

    // 2. 운동 잔디: 본세트 볼륨 맵 변경 시 갱신
    ref.listenManual(
      heatmapDataProvider,
      (_, _) => pushHeatmap(),
      fireImmediately: true,
    );
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
      // 외부 source of truth (Apple Health / Health Connect) 가 백그라운드 동안
      // 갱신됐을 수 있으므로 활동 캐시를 invalidate. 권한 상태도 함께 재평가
      // (사용자가 OS 설정에서 권한을 토글한 케이스 대응).
      ref.invalidate(activityAuthStatusProvider);
      ref.invalidate(dailyActivityProvider);
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
