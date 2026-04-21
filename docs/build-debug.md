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

## 1-1. 실기기 iPhone — 아이콘 탭 시 앱이 튕김 / 안 열림

**증상**: `flutter run -d <iPhone>` 으로 설치된 앱이 Flutter 터미널을 종료하고 나면 아이콘 탭 시 바로 꺼짐 (splash 후 튕김).

**원인**: `flutter run` 의 기본 모드는 **Debug**. Debug 빌드는 Dart Development Service(DDS) 와의 상시 연결을 전제로 하므로, Flutter 툴체인이 분리되면 런타임이 초기화되지 못하고 즉시 종료된다. iOS 코드사인 / 프로비저닝과 무관한 **빌드 모드 문제**다.

**해결**: 단독 실행 가능한 **Release 빌드**로 설치. 프로젝트 루트에 `Makefile` 과 `.vscode/launch.json` 이 준비되어 있다.

```bash
# 터미널 경로 — 기본이 Release
make install-ios

# hot reload 가 필요한 개발 세션만 Debug
make run-ios-dev
```

VS Code 에서는 F5 → "iPhone (Release)" 가 기본 엔트리. Debug 가 필요할 때만 드롭다운에서 "iPhone (Debug — 디버거 연결 시에만)" 선택.

**규칙**:
- 아이폰에 **오래 남길 빌드**는 항상 `--release`. Debug 빌드를 단독 실행이 되는 산출물로 오해하지 말 것.
- `flutter run` 자체는 CLI 플래그 없이는 항상 Debug 로 떨어지므로 **직접 타이핑 지양**, 가능한 한 Makefile / launch.json 진입점을 사용한다.
- Personal Apple ID 팀 서명은 유효기간 7일 — 튕김이 다시 시작되면 모드 문제가 아니라 **서명 만료**일 수 있다. 같은 `make install-ios` 로 재설치.

**금지**:
- Xcode scheme 의 Run Build Configuration 을 Release 로 바꾸는 방식으로 이 문제를 해결하려 하지 말 것. `flutter run` 은 CLI 플래그로 컨피그를 결정하므로 scheme 기본값은 반영되지 않는다 (Xcode 에서 직접 Run 할 때만 의미가 있음).

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

**코치 챗 회귀 (2026-04)**: `coachChat` 이 `gemini-2.5-flash` 로 `responseMimeType: 'application/json'` + `maxOutputTokens: 1024` 조합을 쓰면 thinking 토큰이 ~979 tok 소비(`thoughtsTokenCount`) → JSON 이 중간에 잘려 `finishReason: MAX_TOKENS`. `_parseCoachReply` 파싱 실패로 raw 텍스트 또는 빈 응답이 나가고, SDK 가 빈 content 에서 예외를 던지면 `_ErrorBanner` 까지 도달한다. **해결**: `_chatModel` 을 `gemini-2.5-flash-lite` 로 고정. flash-lite 는 thinking 거의 없음 + JSON 모드 정상 지원(실측 `finishReason: STOP`, `thoughtsTokenCount: 2`). 2.5-flash 로 되돌릴 경우 `thinkingConfig` 로 thinking 예산을 0 으로 명시하거나 `maxOutputTokens` 를 4096+ 로 상향해야 한다.

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

## 13-1. 휴식 타이머 — 상단 빨간 잔상 버그 (Impeller + BackdropFilter)

**증상**: 휴식 타이머가 활성화되는 순간 앱 **상단 전체 너비**에 어두운 적갈색 띠가 그려짐. AppBar 영역 위/SafeArea 안쪽에 노출.

**원인**: Flutter Impeller 렌더러와 `BackdropFilter`(`ImageFilter.blur`)를 상단 overlay 위치에서 합성할 때 iOS 시뮬레이터/일부 환경에서 발생하는 렌더 artifact. `RestTimerBar` 는 `_RootTimerOverlay`에 의해 status bar 바로 아래 `Positioned` 로 올라가므로 artifact 가 가장 눈에 띈다.

**해결**: `BackdropFilter` 폴백 경로를 **완전히 제거**했다 (`lib/features/exercise/presentation/widgets/rest_timer_bar.dart`).
- iOS 26+ : `LiquidGlassContainer` (네이티브 UIGlassEffect) 유지.
- 그 외(iOS ≤ 25 / Android / Web) : blur 없는 **solid pill** (`cs.surface` 배경 + 테두리 + boxShadow) 사용. glass 효과는 포기, 대신 Impeller 호환성 이슈 차단.
- 추가 방어: `_RootTimerOverlay` 의 `RestTimerBar` 를 `RepaintBoundary` 로 감싸 레이어 합성이 상위 위젯으로 번지지 않게 격리 (`lib/app.dart`).

**재발 감지 체크리스트**:
- [ ] 상단에 빨간/적갈색 띠가 보이면 `rest_timer_bar.dart` 빌드 함수에 `debugPrint('[RestTimer] supportsLiquidGlass=$useNativeGlass')` 찍어 현재 경로 확인.
- [ ] 누군가 `BackdropFilter` + `ImageFilter.blur` 를 다시 추가했는지 `rg "BackdropFilter" lib/features/exercise` 로 확인.
- [ ] `BottomNavShell` (`lib/shared/widgets/bottom_nav_shell.dart:202-208`)에도 동일 폴백이 남아있음 — 하단이라 artifact 가 덜 보여 지금은 유지. 여기서도 같은 증상이 보이면 동일 패턴으로 정리.

**금지**:
- `RestTimerBar` 의 fallback 에 `BackdropFilter` 나 `ImageFilter.blur` 를 재도입하지 말 것. 글래스 효과는 `LiquidGlassContainer` 경로 **전용** 으로 둔다.

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
- **Simulator / macOS에서는 제한적으로만 동작** — Dynamic Island는 실기기 iOS 16.1+ 전용. 반드시 실기기로 검증.
- 생성자에서 `_liveActivities.init(...)` 를 await 없이 fire-and-forget 하면 첫 `createActivity` 가 MethodChannel 핸드쉐이크보다 먼저 도달해 silently fail 할 수 있음. `RestNotificationServiceIOS._initFuture` 패턴으로 모든 퍼블릭 메서드가 `await _initFuture;` 하도록 유지.

**Live Activity 진단 로그 (Xcode Console)**:

`RestNotificationServiceIOS` 는 모든 단계에 `[LiveActivity]` 접두사로 로그를 남긴다. Live Activity가 뜨지 않을 때 Xcode 콘솔에서 필터하여 원인 분기:

```bash
# Xcode > Window > Devices and Simulators > View Device Logs, 또는 터미널에서:
log stream --predicate 'eventMessage contains "[LiveActivity]"'
```

| 로그 메시지 | 원인 | 조치 |
|-------------|------|------|
| `init OK, cleaned N stale` | 정상. N개 잔존 activity 정리 완료 | — |
| `init FAILED: ...` | MethodChannel 미연결 / App Group 엔타이틀먼트 누락 / iOS < 16.1 | Xcode > Signing & Capabilities 에서 Runner + Widget Extension 양쪽 App Group 확인, Podfile `platform :ios, '16.1'` 확인 |
| `disabled by user (Settings > ... > Live Activities)` | 사용자가 iOS 설정에서 꺼둠 또는 집중 모드 차단 | iOS 설정 > 앱 이름 > Live Activities 토글 ON, 집중 모드 해제 |
| `areActivitiesEnabled FAILED: ...` | ActivityKit 런타임 비지원 환경 | 실기기 iOS 16.1+ 여부 확인 |
| `createActivity FAILED: ... ActivityInput error 0` | Widget extension 의 `ActivityAttributes` 타입 이름이 플러그인이 요청하는 `LiveActivitiesAppAttributes` 와 불일치 (ActivityKit 이 매칭되는 `ActivityConfiguration` 을 못 찾음) | `ios/RestActivityWidget/RestActivityAttributes.swift` 가 `LiveActivitiesAppAttributes` 를 정확한 이름·레이아웃으로 선언했는지, `RestActivityWidget.swift` 가 `ActivityConfiguration(for: LiveActivitiesAppAttributes.self)` 로 등록했는지 확인. 두 파일 모두 Widget Extension Target 에 멤버십 포함 여부도 재확인. |
| `createActivity FAILED: ...` (기타) | 권한 거부 / 동일 시각 다수 activity 제한 / payload 직렬화 실패 | Error 내 PlatformException code 확인. `code=unsupportedTarget` 이면 시뮬레이터/macOS 문제 |
| `updateActivity/endActivity ... FAILED` | Activity 이미 종료됨 / ID 불일치 | 대부분 무해. 새 Activity 시작 시 자동 복구 |

**플러그인 데이터 플로우 (v2.4.3 기준)**:
`live_activities` 플러그인의 ContentState 는 `appGroupId: String` 하나뿐이며, Dart 가 `createActivity(id, data)` 로 넘긴 나머지 데이터는 App Group `UserDefaults(suiteName:)` 에 `"\(activity.id.uuidString)_\(key)"` 형태로 저장된다. Widget SwiftUI 는 이 UserDefaults 를 직접 읽어 표시한다 (`ios/RestActivityWidget/RestActivityWidget.swift` 의 `readRestPrefs(_:)` 참고). 커스텀 ContentState 필드는 **동작하지 않으므로** 추가하지 말 것.

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

---

## N+1. Personal Apple ID 팀 + Live Activity — aps-environment 엔타이틀먼트 없이 사용하기

**증상** (Xcode 빌드 에러 3종, 무료 Personal 팀 사용 시):

1. `Personal development teams ... do not support the Push Notifications capability.`
2. `Provisioning profile ... doesn't include the Push Notifications capability.`
3. `Provisioning profile ... doesn't include the aps-environment entitlement.`

**원인**: 과거(`live_activities` **≤ v2.4.3**) 버전은 `Activity.request(... pushType: .token)` 을 강제 호출했기에 Runner 타겟에 `aps-environment` 엔타이틀먼트가 필수였다. Personal (무료) Apple ID 팀은 Apple 정책상 Push Notifications capability 서명을 할 수 없어, 이 엔타이틀먼트를 유지하면 Personal 팀 빌드가 통과하지 못한다.

**해결 — 플러그인 v2.4.4+ 의 `iOSEnableRemoteUpdates: false` 사용 (유료 가입 불필요)**

1. `pubspec.yaml` 에서 `live_activities: ^2.4.7` (또는 v2.4.4 이상). 플러그인 제약상 `permission_handler: ^12.0.1` 이 함께 요구됨.
2. `lib/features/exercise/data/rest_notification_service_ios.dart` 의 `createActivity` 호출에 `iOSEnableRemoteUpdates: false` 전달:
   ```dart
   await _liveActivities.createActivity(id, data, iOSEnableRemoteUpdates: false);
   ```
3. v2.4.7 에서 `init()` 시그니처 변경: `requireNotificationPermission` → `requestAndroidNotificationPermission`.
4. `ios/Runner/Runner.entitlements` 에서 `aps-environment` 키 제거 (App Groups 는 위젯 공유에 필요하니 유지).
5. `ios/Runner/Info.plist` 의 `NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates` 는 **유지** (Push 엔타이틀먼트와 무관).
6. Xcode 의 Runner 타겟 → Signing & Capabilities 에 "Push Notifications" 항목이 남아 있으면 삭제.

**플러그인 문서 인용** (`live_activities.dart:53-55`):
> `iOSEnableRemoteUpdates` indicates if the live activity should allow remote updates via push notifications. **If set to false**, the live activity will not receive remote updates. If set to true, Push Notifications capability must be enabled in your Xcode project.

**검증**: Xcode 실기기 빌드 → 세 오류 모두 사라짐. 휴식 타이머 시작 시 Lock Screen/Dynamic Island 정상 표시 + 콘솔에 `createActivity FAILED ... ActivityInput error 0` 로그 없음.

**App Store 제출 트레이드오프**: 원격 푸시로 Activity 를 갱신하는 기능은 포기하게 된다. 로컬 타이머 갱신(`updateActivity`)은 정상 작동. 배포 전환 시점에 Apple Developer Program 유료 가입 후 엔타이틀먼트를 되돌리고 `iOSEnableRemoteUpdates: true` 로 바꾸면 된다.

**하네스 프롬프트 — 향후 발생 시**:
- Push Notifications/aps-environment 서명 오류를 보면 먼저 서명 팀이 Personal 인지 확인한다.
- Personal 팀을 유지하면서 Live Activity 를 쓰려면 반드시 v2.4.4+ + `iOSEnableRemoteUpdates: false` 조합을 사용한다.
- v2.4.3 이하로 다운그레이드하면 이 해결책은 복원 불가 — 반드시 플러그인 버전을 먼저 확인한다.
