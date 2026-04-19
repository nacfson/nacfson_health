# 빌드 & 디버그 가이드

실제 빌드/프리뷰 과정에서 마주친 버그와 해결책을 정리합니다.
새 코드 작성 전 이 패턴을 먼저 확인하세요.

---

## 1. 빌드 타겟: iOS 시뮬레이터 미지원

**증상**: `flutter run -d <simulator>` 실행 시 빌드 타겟 미발견 오류

**원인**: Xcode 프로젝트 `SUPPORTED_PLATFORMS = iphoneos` (시뮬레이터 제외)

**해결**: macOS 로컬 프리뷰 사용

```bash
# 사용 가능한 디바이스 확인
flutter devices

# macOS 앱으로 실행 (권장)
flutter run -d macos

# 분석만 할 때
flutter analyze
```

---

## 2. Riverpod StateNotifier 비동기 초기화 → 라우터 깜빡임 / 온보딩 루프

**증상**: 앱 재시작 시 온보딩 완료 상태임에도 `/onboarding` 리다이렉트 발생

**원인**: `StateNotifier` 안에서 `_load()` 비동기 호출 → 초기값 `false`로 GoRouter가 먼저 평가됨

```dart
// ❌ 금지 패턴 — 비동기 _load()
class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier() : super(false) { _load(); } // false로 시작 → 라우터가 /onboarding으로 튕김
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('onboarding_done') ?? false; // 너무 늦음
  }
}
```

**해결**: `main.dart`에서 `runApp()` 전에 미리 로드 → `ProviderScope.overrides`로 주입

```dart
// ✅ 올바른 패턴
// 1. StateNotifier는 초기값 파라미터만 받음
class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier([bool initial = false]) : super(initial);
  Future<void> complete() async { /* 저장만 */ }
}

// 2. main.dart에서 runApp() 전 동기적으로 로드
void main() async {
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final heightM = prefs.getDouble('user_height_m') ?? 1.70;

  runApp(
    ProviderScope(
      overrides: [
        onboardingDoneProvider.overrideWith((ref) => OnboardingNotifier(onboardingDone)),
        heightMProvider.overrideWith((ref) => HeightNotifier(heightM)),
      ],
      child: const MyApp(),
    ),
  );
}
```

**규칙**: SharedPreferences 기반 Provider는 **절대 StateNotifier 내부에서 비동기 로드하지 않는다.**
앱 시작 시 필요한 값은 모두 `main()`에서 미리 로드하고 `overrideWith`로 주입한다.

---

## 3. GoRouter + Riverpod: ref.watch vs ref.read

**증상**: `notifyListeners()` 호출마다 GoRouter 인스턴스가 재생성 → 네비게이션 상태 손실

**원인**: `appRouterProvider`에서 `ref.watch` 사용

```dart
// ❌ 금지 — ref.watch는 GoRouter를 매번 재생성
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider); // notifyListeners() 때마다 재실행
  return GoRouter(...); // 새 인스턴스 생성 → 스택 초기화
});
```

**해결**: `ref.read`로 한 번만 생성, 재평가는 `refreshListenable`에 위임

```dart
// ✅ 올바른 패턴
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(_routerNotifierProvider); // 한 번만
  return GoRouter(
    refreshListenable: notifier,   // redirect 재평가 트리거
    redirect: notifier.redirect,   // 실제 리다이렉트 로직
    // ...
  );
});
```

**규칙**: `Provider<GoRouter>` 안에서는 항상 `ref.read`를 사용한다.

### 3-1. OAuth 딥링크 콜백 라우팅 (Supabase)

**증상**: 로그인 후 앱 복귀 시 `GoException: no routes for location: io.supabase.nacfson://login-callback/?code=...` 및 `GoException: no routes for location: /` 발생, "Page Not Found" 화면 표시.

**원인**:
- `supabase_flutter`는 `app_links`로 딥링크를 자동 수신해 세션을 저장하지만, Flutter 플랫폼 라우팅이 **별개로** 원시 URL을 `MaterialApp.router` → `go_router`에 전달해 매칭 실패.
- OS 복귀 시점에 `/` 루트 경로를 주입하는데 라우트가 없으면 에러.

**해결 원칙** (3개 레이어):
1. **플랫폼 매니페스트**: Android는 `AndroidManifest.xml`에 `io.supabase.nacfson://login-callback` intent-filter 별개 블록으로 추가 (MAIN/LAUNCHER와 섞지 말 것). iOS는 `Info.plist`의 `CFBundleURLTypes`에 스킴 등록.
2. **GoRouter `onException`**: 매칭 실패 시 `isSignedInProvider` 상태로 `/settings` or `/exercise` 복구. supabase가 이미 세션을 처리했으므로 화면만 정상화.
3. **`/` 라우트 명시 등록**: `GoRoute(path: '/', redirect: (_, _) => '/exercise')`로 silent 처리.

**`_RouterNotifier`에 auth listener 통합**:
```dart
_ref.listen<bool>(isSignedInProvider, (_, _) => notifyListeners());
_ref.listen<AsyncValue<AuthState>>(supabaseAuthStreamProvider, (_, next) {
  next.whenData((s) {
    if (s.event == AuthChangeEvent.signedIn) notifyListeners();
  });
});
```

**규칙**:
- 커스텀 스킴 딥링크는 route로 매칭 **시도하지 말고** `onException`으로 복구한다.
- Android intent-filter 변경은 `flutter clean && flutter run` 필수 (hot reload 미반영).
- `redirect` 내부 경로 비교는 기존 관례대로 `state.uri.path`를 유지 (`matchedLocation`은 매칭 실패 엣지 케이스에서 빈 값/`/`로 떨어질 수 있어 의도치 않은 분기 유발 가능).

---

## 4. ConsumerStatefulWidget의 dispose()에서 ref.read() 크래시

**증상**: 탭 전환 시 `Bad state: Cannot use 'ref' after the widget was disposed` 에러

**원인**: `dispose()`가 호출되는 시점에 위젯이 이미 unmount되어 `ref`가 무효화됨

```dart
// ❌ 크래시 발생
@override
void dispose() {
  ref.read(fabActionProvider.notifier).state = null; // StateError!
  super.dispose();
}
```

**해결**: try-catch로 감싸기

```dart
// ✅ 안전한 패턴
@override
void dispose() {
  try {
    ref.read(fabActionProvider.notifier).state = null;
  } catch (_) {}
  super.dispose();
}
```

**규칙**: `ConsumerStatefulWidget.dispose()` 안에서 `ref`를 사용하는 모든 코드는 try-catch로 감싼다.

---

## 5. macOS TextFormField 포커스 이슈

**증상**: 두 번째 `TextFormField`를 클릭해도 포커스가 이동하지 않음 (macOS 데스크탑)

**원인**: macOS에서 포커스 전환 시 `FocusNode` 없이는 프로그래매틱 포커스 이동이 불안정

**해결**: 명시적 `FocusNode` + `textInputAction` + `onFieldSubmitted` 연결

```dart
// ✅ 멀티 필드 폼 패턴
class _MyFormState extends ConsumerState<MyForm> {
  final _secondFocus = FocusNode();

  @override
  void dispose() {
    _secondFocus.dispose(); // 반드시 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextFormField(
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_secondFocus),
      ),
      TextFormField(
        focusNode: _secondFocus,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
      ),
    ]);
  }
}
```

**규칙**: macOS 대상 폼에서 `TextFormField`가 2개 이상이면 항상 `FocusNode`를 명시적으로 할당한다.

---

## 6. .env / Gemini API 키 디버깅

**증상**: 요약 화면에서 "AI 분석 중 오류가 발생했습니다." 표시

**체크리스트**:

```bash
# 1. .env 파일 존재 여부 확인
cat "/Users/hyungjuyu/Projects/Flutter/nacfson_health copy/.env"
# → GEMINI_API_KEY=... 형태여야 함

# 2. pubspec.yaml assets에 .env 등록 여부 확인
grep -A5 "assets:" pubspec.yaml

# 3. 앱 콘솔에서 에러 로그 확인
# flutter run -d macos 실행 후 터미널에서 "[GeminiService] Error:" 라인 확인
```

**API 키 갱신**: https://aistudio.google.com/app/apikey 에서 키 재발급 후 `.env` 교체

**규칙**:
- `.env`는 `.gitignore`에 등록 (커밋 금지)
- `GeminiService` catch 블록은 `debugPrint('[GeminiService] ${e.runtimeType}: $e')` 로 runtimeType 함께 기록하고 **반드시 `rethrow`** 하여 `AsyncValue.error` 로 전파할 것. 문자열 fallback 반환은 UI 에러 분기를 죽이고 원인 진단을 불가능하게 만든다.
- API 키 오류와 네트워크 오류를 구분하려면 `e.toString()`에서 `"API_KEY"` 또는 `"403"` 확인

### 쿼터 (`limit: 0`) 이슈 — "is not found for API version v1beta" 의 진짜 얼굴

에러 메시지가 `models/<이름> is not found for API version v1beta` 이면 모델명 오타가 아니라 **해당 API 키 프로젝트의 무료 티어 할당량이 0**인 경우가 대부분이다. 실제 원문은 `You exceeded your current quota … limit: 0, model: <이름>` 이며 `google_generative_ai 0.4.x` 가 이 응답을 "not found"로 요약해 버린다.

**진단 방법** (ListModels 로 키 자체와 지원 모델 리스트를 분리 확인):

```bash
KEY=$(grep '^GEMINI_API_KEY=' .env | cut -d= -f2)
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$KEY" | head -50
```

- HTTP 200 + 모델 리스트 정상 → **키는 유효**, 쿼터 정책 문제.
- HTTP 403 / "API key not valid" → 키 재발급.
- HTTP 200 + `models/<이름>` 이 리스트에 있는데도 `generateContent` 에서 실패 → 그 모델의 무료 티어가 0으로 막혔다는 신호.

**회피**: 리스트에서 `gemini-2.5-flash-lite` / `gemini-flash-lite-latest` / `gemma-3-1b-it` 는 보통 무료 티어가 열려 있다. [lib/core/ai/gemini_service.dart](../lib/core/ai/gemini_service.dart) 의 `model:` 인자만 교체. `gemini-2.0-flash`, `gemini-2.0-flash-lite` 는 일부 계정/지역에서 무료 티어가 0으로 내려가 있어 회피 모델로 부적합.

---

## 7. ConsumerStatefulWidget FAB 설정 — dispose() 일관성

**증상**: 식단 탭 → 운동 탭 빠른 전환 시 `Bad state: Cannot use 'ref' after disposed`

**원인**: `dispose()`에서 `fabActionProvider` 초기화 시 ref가 이미 무효화되어 있음

**규칙**: `fabActionProvider`를 설정하는 **모든** Screen의 `dispose()`에는 반드시 try-catch 적용

```dart
// ✅ exercise_screen.dart, diet_screen.dart 동일 패턴
@override
void dispose() {
  try {
    ref.read(fabActionProvider.notifier).state = null;
  } catch (_) {}
  super.dispose();
}
```

---

## 8. 폼 저장 버튼 — 중복 클릭 방지 + 피드백

**증상**: 저장 중 버튼을 두 번 탭하면 DB에 중복 레코드 저장됨. 저장 성공 여부 불명확.

**규칙**: 데이터를 저장하는 **모든** 폼(exercise_form, diet_form, weight_form)에 적용

```dart
// ✅ 올바른 패턴
bool _isLoading = false;

Future<void> _submit() async {
  if (_isLoading) return;                        // 중복 클릭 방지
  if (!_formKey.currentState!.validate()) return;
  setState(() => _isLoading = true);
  try {
    // 저장 로직
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장되었습니다'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

// 버튼:
FilledButton(
  onPressed: _isLoading ? null : _submit,   // null → 자동 비활성화
  child: _isLoading
      ? const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2))
      : const Text('저장'),
)
```

---

## 9. 미구현 지표를 종합율에 포함하지 않는다

**증상**: 운동+식단 모두 100% 달성해도 종합율이 66%로 표시됨

**원인**: `sleepProgress = 0.0` (미구현)을 overall 계산에 포함

```dart
// ❌ 금지 — 미구현 지표 포함
final overall = ((exerciseProgress + dietProgress + sleepProgress) / 3 * 100).toInt();

// ✅ 올바른 패턴 — 구현된 지표만 평균
final overall = ((exerciseProgress + dietProgress) / 2 * 100).toInt();
```

**규칙**: 새 지표(수면, 스트레스 등)를 추가할 때 **구현 완료 후** overall 계산에 편입한다.

---

## 10. Bottom Sheet 상태 — Future.microtask 금지

**증상**: 운동/식단 기록 폼을 닫은 뒤 FAB이 한 프레임 동안 안 돌아오거나 탭 전환 시 깜빡임.

**원인**: `sheet_state_provider.dart`의 `showModalBottomSheet(...).then()` 안에서 `Future.microtask(() => activeSheetProvider.state = null)`로 초기화하던 레거시 코드. 마이크로태스크 지연만큼 FAB 복귀가 한 프레임 밀리고, 시트 재오픈과 타이밍이 겹치면 state가 역순으로 덮어써져 race가 발생.

**해결**: `.then()` 내부에서 **동기적으로** `state = null` 호출. builder에서의 중복 state 세팅도 제거.

```dart
// ❌ 금지 — microtask 지연
).then((_) {
  Future.microtask(() {
    ref.read(activeSheetProvider.notifier).state = null;
  });
});

// ✅ 즉시 초기화
).then((_) {
  ref.read(activeSheetProvider.notifier).state = null;
});
```

**규칙**: 모달 라이프사이클과 연동된 `StateProvider` 초기화는 **반드시 동기**로. 프레임 지연 회피용 `Future.microtask`/`Future.delayed` 삽입 금지.

---

## 11. AuthCallbackScreen — initState 구독 + 배경 동기화

**증상**: 설정 화면에서 Google 로그인 후 의도치 않게 운동 탭으로 점프하거나, `performSync()` 실패 시 콘솔에 unhandled async error 기록.

**원인**:
1. `build()` 안에서 `ref.listen` 사용 → 매 rebuild마다 재구독.
2. `context.go('/exercise')` 하드코딩 → 사용자가 로그인한 `/settings`에서 멀어짐.
3. `performSync()`를 `await` 없이 호출 → 실패 시 예외가 라우팅 이후로 전파되어 UI가 깨짐.

**해결**: `ConsumerStatefulWidget` + `ref.listenManual` 으로 한 번만 구독, `/settings`로 복귀, 동기화는 `unawaited` + try/catch로 분리.

```dart
// ✅ auth_callback_screen.dart
class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  ProviderSubscription<AsyncValue<AuthState>>? _subscription;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual<AsyncValue<AuthState>>(
      supabaseAuthStreamProvider,
      (_, next) => next.whenData((s) {
        if (!_handled && s.event == AuthChangeEvent.signedIn) {
          _handled = true;
          if (!mounted) return;
          context.go('/settings');
          unawaited(_syncInBackground());
        }
      }),
    );
  }

  @override
  void dispose() { _subscription?.close(); super.dispose(); }

  Future<void> _syncInBackground() async {
    try {
      await ref.read(syncStateProvider.notifier).performSync();
    } catch (_) {
      ErrorOverlay.show(title: '동기화 실패', message: '...');
    }
  }
}
```

**규칙**:
- 라이프사이클 중 한 번만 발동해야 하는 Provider 이벤트는 `ref.listenManual`을 `initState`에서 등록하고 `dispose`에서 해제. `build` 내부 `ref.listen` 금지.
- OAuth 콜백 후 라우팅 목적지는 **사용자가 로그인을 시작한 화면**(현재는 `/settings`). 하드코딩된 다른 탭으로 강제 이동 금지.
- 로그인 직후 동기화 호출은 반드시 `unawaited` + try/catch로 감싸 라우팅 성공과 분리.

---

## 12. AI 인사이트 날짜별 캐싱

**증상**: 요약 탭 재방문마다 Gemini API 재호출 → 지연 + API 비용 낭비

**해결**: `insightCacheProvider (StateProvider<Map<String,String>>)`로 날짜별 캐시 관리

```dart
// lib/core/ai/health_insight_provider.dart

final insightCacheProvider = StateProvider<Map<String, String>>((ref) => {});

String insightCacheKey(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2,'0')}${date.day.toString().padLeft(2,'0')}';

final healthInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  final cacheKey = insightCacheKey(ref.watch(selectedDateProvider));
  final cache = ref.read(insightCacheProvider);
  if (cache.containsKey(cacheKey)) return cache[cacheKey]!;  // 캐시 히트

  final result = await GeminiService().getHealthInsight(...);
  ref.read(insightCacheProvider.notifier).update((s) => {...s, cacheKey: result});
  return result;
});
```

refresh 아이콘 탭 시 캐시 키 먼저 삭제 후 invalidate:
```dart
onTap: () {
  final key = insightCacheKey(ref.read(selectedDateProvider));
  ref.read(insightCacheProvider.notifier).update((s) => Map.from(s)..remove(key));
  ref.invalidate(healthInsightProvider);
},
```

**규칙**: `FutureProvider.autoDispose`로 외부 API를 호출하는 모든 Provider는 세션 내 캐싱을 적용한다.

---

## 빠른 검증 체크리스트

새 기능 구현 후 또는 버그 수정 후 아래 순서로 확인:

```bash
# 1. 정적 분석
flutter analyze

# 2. macOS 빌드 (코드사인 없이)
flutter build macos --debug

# 3. 실행
flutter run -d macos
```

| 항목 | 확인 방법 |
|------|-----------|
| 온보딩 최초 실행 | 앱 데이터 초기화 후 실행 → 온보딩 화면 표시 |
| 온보딩 재진입 방지 | 온보딩 완료 후 앱 재시작 → 바로 운동 화면 |
| 요약 탭 이동 | 운동/식단 탭 FAB 표시 중 요약 탭 버튼 탭 가능 여부 |
| BMI 동적 계산 | 체중 탭 → 키 값이 `heightMProvider` 기준으로 표시 |
| AI 인사이트 | 요약 탭 → 로딩 후 카드 표시 또는 에러 메시지 |
| dispose 크래시 | 식단↔운동 탭 빠른 전환 반복 → 크래시 없음 |
| 중복 저장 방지 | 운동 폼에서 저장 버튼 연속 탭 → DB에 1건만 저장 |
| SnackBar 피드백 | 운동/식단/체중 저장 후 "저장되었습니다" 표시 |
| 종합율 정확도 | 운동+식단 100% 달성 시 종합 100% 표시 |
| AI 캐싱 | 요약 탭 반복 방문 시 두 번째부터 즉시 표시 |
| 음수 입력 차단 | 중량 -5 입력 시 "0보다 커야 합니다" 표시 |

---

## 12-1. 다크모드 UI 이슈 디버깅

특정 위젯이 다크 테마에서 라이트 색으로 남아있다는 제보가 오면 다음 순서로 grep:

```bash
# 1) 위젯이 AppTheme의 라이트 전용 static을 직접 참조하는지
rg "AppTheme\.(colorBg|colorSurface|colorSurfaceAlt|colorText[A-Za-z]*|colorHairBorder)\b" lib/

# 2) 하드코딩된 흰/빨/검정 잔존 여부 (의도적 navy 브랜드 내부만 허용)
rg "Colors\.(white|black|grey|red|redAccent)\b" lib/ --glob '!**/app_theme.dart'

# 3) 매직넘버 Color(0xFFxxxxxx) — 브랜드 팔레트 이외는 AppTheme 토큰으로 치환
rg "Color\(0xFF[0-9A-Fa-f]{6}\)" lib/ --glob '!**/app_theme.dart'
```

해결 규칙은 `docs/conventions.md` §2 "위젯에서 색상 참조 원칙"에 정리. 요약:
- 위젯 빌드 함수는 `Theme.of(context).colorScheme` 토큰만 사용
- 카테고리 컬러는 `AppTheme.catDiet(context)` / `catSleep(context)` 같은 brightness-aware 헬퍼 사용
- `const TextStyle(color: AppTheme.*)` 패턴 금지 → `const` 제거 후 `cs.*` 주입
- 예외: `AppTheme.colorNavy` 브랜드 히어로 컨테이너 내부의 `Colors.white` 텍스트/도트는 의도적 유지

---

## 13. 휴식 타이머 — 루트 오버레이 배치

`RestTimerBar`는 `MaterialApp.router.builder`에서 `_RootTimerOverlay`로 감싸 **root Navigator 외부**에 배치한다 (`lib/app.dart`). `showModalBottomSheet`는 기본적으로 shell Navigator(ShellRoute 내부)에 삽입되므로 타이머를 shell 내부 Stack에 두면 시트 아래에 묻힌다.

**위치 계산 규칙**:
- `activeSheetProvider != null` (시트 열림): `bottom = viewInsets.bottom + padding.bottom + 12` → 키보드/홈인디케이터 위
- 시트 없음: `bottom = 72 + padding.bottom + 12` → 바텀 네비게이션 바 위

**금지**:
- `BottomNavShell` 또는 특정 Screen 내부 Stack에 `RestTimerBar`를 배치하지 말 것 (모달 시트에 가려짐).
- `useRootNavigator: true`로 시트를 띄우는 방식으로 우회하면 FAB/네비 바와 시트의 z-order가 깨지므로 오버레이 경로를 유지한다.

---

## 14. 휴식 타이머 — iOS Live Activity Widget Extension 추가 (수동)

`live_activities` 패키지는 Dart 측을 처리하지만, iOS Widget Extension 타겟은 Xcode UI에서 사용자가 직접 추가해야 합니다 (project.pbxproj 자동 생성은 안전하지 않음).

**준비된 자산** (이미 작성됨):
- `ios/RestActivityWidget/RestActivityAttributes.swift` — `ActivityAttributes` 정의
- `ios/RestActivityWidget/RestActivityWidget.swift` — Lock Screen + Dynamic Island 위젯
- `ios/Podfile` — `platform :ios, '16.1'`
- `ios/Runner/Info.plist` — `NSSupportsLiveActivities=true`, `NSSupportsLiveActivitiesFrequentUpdates=true`

**Xcode 수동 단계**:
1. `open ios/Runner.xcworkspace`
2. **File → New → Target**
3. **Widget Extension** 선택, "Include Live Activity" 체크박스 활성화
4. Product Name: `RestActivityWidget`, Team/Bundle ID 확인 후 Finish
5. 새 그룹의 자동 생성 Swift 파일 (예: `RestActivityWidgetLiveActivity.swift`)을 삭제하고, 사전 작성된 두 파일 (`RestActivityAttributes.swift`, `RestActivityWidget.swift`)을 그룹에 드래그하여 추가 (Target Membership: `RestActivityWidget`만 체크, Runner는 체크 해제)
6. Widget Extension 타겟의 **Signing & Capabilities** → **+ Capability** → **App Groups**:
   - `group.com.nacfson.nacfsonHealth` 그룹 생성/선택 (Runner 엔타이틀먼트와 동일)
7. **Runner 타겟**도 동일한 App Group 추가
8. `cd ios && pod install`
9. `flutter run -d <iOS device, iOS 16.1+>`

**검증 체크리스트**:
| 항목 | 확인 방법 |
|------|-----------|
| Live Activity 등장 | iPhone 14 Pro+ 실기에서 운동 기록 저장 → Dynamic Island에 ⏱ 카운트다운 |
| Lock Screen 위젯 | 잠금화면 진입 → 카드형 위젯에 운동명 + 카운트다운 |
| Expanded view | Dynamic Island 길게 눌러 펼침 → 큰 카운트다운 + ProgressView |
| 백그라운드 정확성 | 다른 앱으로 전환 후 60초 대기 → Live Activity 시간 정확 |
| 종료 동기화 | 인앱 ✕ 또는 0초 도달 → Live Activity 자동 dismiss |

**자주 발생하는 함정**:
- App Group이 두 타겟에 다르게 설정되면 widget이 데이터를 못 받습니다.
- iOS 16.0 이하 시뮬레이터/기기에서는 createActivity가 silently fail (try/catch 처리됨).
- Widget Extension이 추가되지 않은 상태로 빌드해도 Dart는 정상 (createActivity가 PlatformException으로 처리됨).

---

## 15. 휴식 타이머 — Android persistent notification

`flutter_local_notifications`가 자동 처리하지만 Android 13+에서는 권한 요청 필요.

**자동 처리됨**:
- `AndroidManifest.xml` — `POST_NOTIFICATIONS`, `VIBRATE` 권한 추가됨
- `RestNotificationServiceAndroid` — 첫 호출 시 `Permission.notification.request()` 자동 호출
- `flutter_local_notifications` 17.x — `usesChronometer + chronometerCountDown + when=endAt` 으로 시스템이 카운트다운 자동 표시
- 알림 채널 `rest_timer_channel` (importance/priority `low`로 헤드업/소리 방지)
- 액션 버튼: `[+15초]` `[정지]` — `onDidReceiveNotificationResponse` 콜백 → `RestTimerNotifier.addSeconds(15)` / `stop()`

**검증 체크리스트**:
| 항목 | 확인 방법 |
|------|-----------|
| 권한 다이얼로그 | Android 13+ 첫 운동 기록 저장 시 1회 표시 |
| 알림 표시 | 알림창 펼치기 → "휴식 종료까지 MM:SS" + 두 액션 버튼 |
| +15초 액션 | 알림의 `[+15초]` 탭 → 인앱 미니바와 알림 모두 +15초 |
| 정지 액션 | `[정지]` 탭 → 알림 dismiss + 인앱 미니바 사라짐 |
| 백그라운드 카운트 | 앱 백그라운드 + 알림창 펼침 → 카운트다운 정확 |

**자주 발생하는 함정**:
- 권한 거부 시: `RestNotificationServiceAndroid.show()`가 null 반환, 인앱 미니바는 정상 동작.
- Android 8.0 미만: 채널 미지원이라 importance 무시. minSdk 21 이상이면 안전.
- 앱 강제 종료 시: 알림도 함께 사라짐 (Foreground Service 미사용 — 백로그 참조).

---

## N. iOS 빌드 실패 — PrivacyInfo.xcprivacy "no rule to process file"

**증상**: Xcode 빌드 시 아래와 같은 에러로 `Command PhaseScriptExecution failed with a nonzero exit code`.

```
no rule to process file '.../flutter_app_group_directory/.../PrivacyInfo.xcprivacy' of type 'text.xml' for architecture 'arm64'
no rule to process file '.../live_activities/.../PrivacyInfo.xcprivacy' of type 'text.xml' for architecture 'arm64'
```

**원인**: `flutter_app_group_directory 1.1.0`, `live_activities 2.4.3` 두 플러그인의 podspec 에 버그가 있다.

```ruby
s.source_files = '...Sources/.../**/*'   # ← 와일드카드가 .xcprivacy 를 컴파일 소스로 포함
# s.resource_bundles = {...}              # ← resource 선언은 주석 처리
```

→ 와일드카드가 `PrivacyInfo.xcprivacy` 를 Compile Sources 로 등록 → Xcode 는 `.xcprivacy`(text.xml) 를 컴파일할 방법이 없어 실패.

**해결**: `ios/Podfile` 의 `post_install` 블록에 두 플러그인의 Compile Sources 에서 `.xcprivacy` 를 제거하는 루프 추가.

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    # ... 기존 deployment target 설정 ...

    if ['live_activities', 'flutter_app_group_directory'].include?(target.name)
      target.source_build_phase.files.dup.each do |bf|
        ref = bf.file_ref
        if ref && ref.path && ref.path.end_with?('PrivacyInfo.xcprivacy')
          target.source_build_phase.remove_build_file(bf)
        end
      end
    end
  end
end
```

수정 후: `cd ios && pod install` → `flutter build ios --debug --no-codesign` 으로 검증.

**참고 — 나머지 non-blocking 경고들** (빌드 성공 후에도 남음, 무시 가능):
- `flutter_local_notifications 17.2.4`: `setRegisterPlugins:` method definition not found / `UNNotificationPresentationOptionAlert` deprecated
- `home_widget 0.7.0`, `live_activities 2.4.3`: Sendable / `@Sendable` closure 경고 (Swift 6 concurrency)
- `permission_handler_apple 9.4.7`: `CTCarrier` deprecated (iOS 16+)

**App Store 제출 시 주의**: 위 해결책은 PrivacyInfo 매니페스트를 **번들에서 제외** 한다. App Store 제출 단계에서 매니페스트가 필요하면 `remove_build_file` 대신 `target.resources_build_phase.add_file_reference(ref)` 로 Resources phase 에 재등록하는 방식으로 전환해야 한다.
