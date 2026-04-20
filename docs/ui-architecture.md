# UI Architecture

> **문서 버전**: 2026-04  
> **범위**: 네비게이션, 레이아웃, 상태 관리  
> **플랫폼**: Flutter (iOS, Android, macOS, Windows, Linux, Web)

---

## 1. 전체 구조

```
┌──────────────────────────────────────────────┐
│              NacfsonHealthApp                 │
│         (MaterialApp.router)                  │
│  builder: (_, child) => _RootTimerOverlay(    │
│                           child: child)       │
└────────────────┬─────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────┐
│   _RootTimerOverlay  (Stack)                  │
│   ├─ child (GoRouter + Navigator + modals)   │
│   └─ Positioned(RestTimerBar)                │
└────────────────┬─────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────┐
│              GoRouter                         │
│  ┌─────────────────────────────────────────┐ │
│  │         ShellRoute                      │ │
│  │  ┌───────────────────────────────────┐  │ │
│  │  │      BottomNavShell               │  │ │
│  │  │  body: child (Screen)             │  │ │
│  │  │  bottomNav: NavigationBar         │  │ │
│  │  │  운동 │ 식단 │ 체중 │ 요약 │ 설정 │  │ │
│  │  └───────────────────────────────────┘  │ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

### 휴식 타이머 오버레이 (v7.2)

`RestTimerBar`는 `MaterialApp.router.builder`의 `_RootTimerOverlay`에서 root Navigator 외부에 배치된다.
- **z-order**: `showModalBottomSheet`가 shell Navigator에 삽입되어도 그 **위**에 그려진다 (시트로 가려지지 않음).
- **위치 계산**:
  - `activeSheetProvider != null` (시트 열림): `bottom = viewInsets.bottom + padding.bottom + 12` — 키보드/홈인디케이터 위.
  - 시트 없음: `bottom = 72 + padding.bottom + 12` — BottomNav 위.
- **가시성**: `restTimerProvider.isActive == true` 일 때만 렌더. 비활성 시 오버레이 자체가 생략되어 레이아웃 영향 없음.
- **모든 탭·모달에서 유지**: root-level 오버레이이므로 탭 전환·시트 오픈 무관.
- **스타일**: `BackdropFilter + 반투명 surface` Glassmorphism (BottomNav와 시각적 일관성).

---

## 2. 네비게이션 구조

### 2.1 경로 테이블

| 경로 | 화면 | 설명 |
|------|------|------|
| `/onboarding` | `OnboardingScreen` | 첫 실행 키/체중/성별/나이대/목표 입력 + 영양 목표 프리뷰 (Shell 외부, redirect 진입점) |
| `/login-callback` | `AuthCallbackScreen` | OAuth 콜백 → `/settings`로 복귀, `performSync()`는 `unawaited` 배경 실행 (Shell 외부) |
| `/exercise` | `ExerciseScreen` | 운동 기록 탭 |
| `/diet` | `DietScreen` | 식단 기록 탭 |
| `/weight` | `WeightScreen` | 체중 기록/차트 탭 |
| `/summary` | `SummaryScreen` | 요약/통계 탭 (AI 인사이트 카드 포함) |
| `/settings` | `SettingsScreen` | Google 연동 설정 + 테마 전환 탭 |

**라우팅 게이트**: `_RouterNotifier`가 `onboardingDoneProvider`를 listen → `refreshListenable`로 GoRouter redirect 재평가. 자세한 흐름은 `docs/architecture.md` "라우팅 흐름" 섹션 참조.

### 2.2 라우팅 흐름

```
NavigationBar.onDestinationSelected(index)
         │
         ▼
[popAll] (root/shellNavigatorKey.currentState?.popUntil((route) => route.isFirst))
         │
         ▼
context.go('/{path}')
         │
         ▼
appRouter (GoRouter)
```

### 2.3 탭 선택 인덱스 계산

```dart
int _calculateSelectedIndex(BuildContext context) {
  final location = GoRouterState.of(context).uri.path;
  if (location.startsWith('/exercise')) return 0;
  if (location.startsWith('/diet')) return 1;
  if (location.startsWith('/weight')) return 2;
  if (location.startsWith('/summary')) return 3;
  if (location.startsWith('/settings')) return 4;
  return 0;
}
```

---

## 3. Bottom Sheet (기록 추가 UI)

### 3.1 구조 및 제약

- **반응형 너비**: 데스크톱/웹 대응을 위해 `ConstrainedBox`를 사용하여 최대 너비를 **600px**로 제한한다.
- **배치**: `Align(alignment: Alignment.bottomCenter)`를 적용하여 넓은 화면에서도 하단 중앙에 위치하게 한다.
- **키보드 대응**: `SingleChildScrollView`와 `MediaQuery.of(context).viewInsets.bottom`을 조합하여 키보드가 올라와도 입력 필드가 가려지지 않도록 패딩을 조절한다.

```
┌──────────────────────────────────────┐
│  showModalBottomSheet()              │
│  isScrollControlled: true            │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  DraggableScrollableSheet            │
│  (initial 0.85, min 0.45, max 0.95)  │
│  └─ Container (surface + radius)     │
│     └─ SingleChildScrollView         │
│        (scrollController 연결)        │
│        └─ Column [핸들바·헤더·폼 child]│
└──────────────────────────────────────┘
```

**FAB & 시트 상태 관리** (`lib/core/providers/sheet_state_provider.dart`):

- `activeSheetProvider` (`StateProvider<SheetType?>`): 현재 열린 바텀시트 타입 추적
- `openSheet()` 헬퍼: 중복 시트 방지(같은 타입 재탭 → 닫기), Navigator.pop 연동, `showModalBottomSheet` 래핑
- `bottom_nav_shell.dart`의 `_showFab`는 `activeSheetProvider`를 watch → 시트 열림 시 FAB 자동 숨김
- 모든 화면(`exercise_screen`, `diet_screen`)은 `openSheet()` 경유하여 시트 오픈

---

## 4. 폼 구조

모든 입력 폼은 `RecordFormSheet`(DraggableScrollableSheet) 컨테이너로 감싸져 드래그로 높이 조절 가능 (45%~95%).

- **InlineSetInput** _(v8, 운동)_: 카드 하단 1행 입력기 (kg / 회 / RPE + ✓ / ✕). 직전 세트 값 프리필 → 연속 입력. 모달 폼 대체.
- **DietForm**: 식단 기록 (mealType, foodName, totalCalories, carbs, protein, fat, satisfaction, memo, timestamp)
- **WeightForm**: 체중 기록 (weight, timestamp) — `showDatePicker`로 날짜 선택, `DateTime(y, m, d)` 자정 저장

> 운동 도메인은 v8부터 모달 `ExerciseForm`을 폐기하고, 카드 내 인라인 입력 + AppBar의 루틴 프리셋 시트(`RoutinePresetSheet`)로 대체됨.

> **날짜 선택 패턴**: 날짜만 선택할 경우 `DateTime(year, month, day)` 자정 저장. `todayWeightProvider`는 year/month/day 비교이므로 자정 타임스탬프와 호환됨.

자세한 필드 정의는 `CLAUDE.md` Entity 스키마 참고.

---

## 4.5 공통 위젯 (v6/v7 신규)

| 위젯 | 위치 | 역할 |
|------|------|------|
| `DateNavigationBar` | `lib/shared/widgets/date_navigation_bar.dart` | 운동/식단/요약 공통 날짜 탐색 (좌우 chevron + DatePicker + Today 버튼). 미래 날짜는 forward 비활성화 (`isSelectedDateTodayProvider`) |
| `VolumeTrendChart` | `lib/features/exercise/presentation/widgets/volume_trend_chart.dart` | 운동 볼륨 주간/월간 LineChart (mint, k-notation) |
| `CalorieTrendChart` | `lib/features/diet/presentation/widgets/calorie_trend_chart.dart` | 식단 칼로리 주간/월간 BarChart + 빨간 점선 목표선, 105% 초과 시 코랄 |
| `OnboardingScreen` | `lib/features/onboarding/presentation/screens/onboarding_screen.dart` | 첫 실행 키(cm)/체중(kg)/성별/나이대/목표(다이어트/린매스업/벌크업) 입력 → `setHeight`/`complete()` + `WeightRecord` 자동 생성 + `calculateTargets(...)` 결과를 `nutritionTargetsProvider`에 seed. 실시간 프리뷰(`_NutritionPreview`) 포함 |
| `ThemeModeCard` | `lib/features/settings/presentation/widgets/theme_mode_card.dart` | SegmentedButton 3-way 테마 전환 |
| `_AiInsightCard` | `lib/features/summary/presentation/screens/summary_screen.dart` 내 private | Gemini 인사이트 카드 (loading/error/data + 새로고침) |
| `ExerciseGroupCard` _(v8)_ | `lib/features/exercise/presentation/widgets/exercise_group_card.dart` | 운동 카드. `editable=true`(오늘)면 `+ 세트 추가` 버튼·인라인 입력·"루틴에서 제거" 메뉴 노출. `editable=false`(과거)면 읽기 전용 |
| `InlineSetInput` _(v8)_ | `lib/features/exercise/presentation/widgets/inline_set_input.dart` | 카드 하단 1행 입력기. add/edit 모드 지원, 직전 세트 프리필, ✓ 저장 후 필드 유지 |
| `RoutinePresetSheet` _(v8)_ | `lib/features/exercise/presentation/widgets/routine_preset_sheet.dart` | 저장된 루틴 프리셋 시트. 탭=불러오기(교체/추가 confirm), 메뉴=이름변경/삭제 |

**전역 날짜 상태**: `lib/shared/providers/selected_date_provider.dart`
- `selectedDateProvider` (StateProvider<DateTime>, 자정 정규화)
- `isSelectedDateTodayProvider` (computed Provider<bool>) — DateNavigationBar의 forward 버튼 enable 토글

---

## 5. 위젯 계층도

```
lib/
├── app.dart                          # MaterialApp.router
├── main.dart                         # runApp + ProviderScope
│
├── core/
│   ├── database/
│   │   └── database_helper.dart      # sqflite 싱글톤
│   ├── providers/
│   │   └── sheet_state_provider.dart  # Bottom Sheet 상태 관리
│   ├── router/
│   │   └── app_router.dart           # GoRouter, ShellRoute (5탭)
│   ├── sync/
│   │   ├── google_auth_service.dart   # Google 로그인/세션 복원
│   │   ├── google_sheets_service.dart  # Sheets API CRUD
│   │   ├── sync_preferences.dart      # SharedPreferences 래퍼
│   │   └── sync_state.dart            # SyncStateNotifier (_syncAll)
│   ├── theme/
│   │   ├── app_theme.dart            # LightTheme + DarkTheme (Material 3)
│   │   └── theme_mode_provider.dart  # ThemeModeNotifier (system/light/dark, shared_preferences)
│   └── widget/
│       └── home_widget_service.dart   # iOS 홈 위젯 영양 데이터 연동
│
├── shared/
│   ├── providers/
│   │   ├── selected_date_provider.dart   # 전역 선택 날짜 (자정 정규화)
│   │   └── user_profile_provider.dart    # HeightNotifier, OnboardingNotifier
│   └── widgets/
│       ├── bottom_nav_shell.dart     # 하단 네비게이션 셸 (5탭, FAB 포함)
│       ├── date_navigation_bar.dart  # 날짜 탐색 바 (좌우 chevron + DatePicker)
│       ├── empty_state.dart          # 빈 상태 공통 위젯 (아이콘+텍스트, FAB 통일)
│       ├── error_overlay.dart        # 에러 오버레이 (자동 닫힘)
│       ├── record_form_sheet.dart    # DraggableScrollableSheet 컨테이너
│       └── template_picker_sheet.dart # 운동·식단 공통 템플릿 선택 BottomSheet
│
└── features/
    ├── onboarding/
    │   └── presentation/screens/
    │       └── onboarding_screen.dart      # 첫 실행 키/체중 입력
    │
    ├── exercise/
    │   ├── domain/entities/
    │   │   └── exercise_record.dart  # Entity + SyncStatus enum
    │   ├── data/repositories/
    │   │   ├── exercise_repository.dart      # Interface
    │   │   └── sqlite_exercise_repository.dart # sqflite 구현체
    │   └── presentation/
    │       ├── providers/
    │       │   └── exercise_provider.dart   # ExerciseNotifier + 2레벨 그룹핑 + volumeTrendDataProvider
    │       ├── screens/
    │       │   └── exercise_screen.dart    # 운동 기록 화면
    │       └── widgets/
    │           ├── exercise_form.dart      # 운동 기록 입력 Form (이름 필드 suffixIcon → TemplatePickerSheet + 점진적 과부하 표시)
    │           ├── exercise_group_card.dart # 종목별 세트 그룹 카드
    │           ├── exercise_record_card.dart # 개별 기록 카드 + 유형 색상/아이콘
    │           └── volume_trend_chart.dart # 운동 볼륨 주간/월간 LineChart
    │
    ├── diet/
    │   ├── domain/entities/
    │   │   └── diet_record.dart      # Entity
    │   ├── data/repositories/
    │   │   ├── diet_repository.dart        # Interface
    │   │   └── sqlite_diet_repository.dart  # sqflite 구현체
    │   └── presentation/
    │       ├── providers/
    │       │   └── diet_provider.dart      # DietNotifier + calorieTrendDataProvider
    │       ├── screens/
    │       │   └── diet_screen.dart        # 식단 기록 화면
    │       └── widgets/
    │           ├── calorie_trend_chart.dart # 칼로리 주간/월간 BarChart + 목표선
    │           ├── diet_form.dart          # 식단 기록 입력 Form (이름 필드 suffixIcon → TemplatePickerSheet)
    │           └── diet_record_card.dart   # 식단 기록 카드
    │
    ├── summary/
    │   ├── domain/entities/
    │   │   └── daily_summary.dart     # Entity (메모리 계산, DB 테이블 아님)
    │   └── presentation/
    │       ├── providers/
    │       │   └── summary_provider.dart  # DailySummaryNotifier
    │       └── screens/
    │           └── summary_screen.dart    # 요약 화면 (fl_chart)
    │
    ├── weight/
    │   ├── domain/entities/
    │   │   └── weight_record.dart     # Entity + SyncStatus enum
    │   ├── data/repositories/
    │   │   ├── weight_repository.dart      # Interface
    │   │   └── sqlite_weight_repository.dart # sqflite 구현체
    │   └── presentation/
    │       ├── providers/
    │       │   └── weight_provider.dart   # WeightNotifier + 차트 필터 Provider
    │       ├── screens/
    │       │   └── weight_screen.dart     # 체중 기록/차트 화면
    │       └── widgets/
    │           ├── weight_chart_card.dart  # 체중 추세 차트 (주/월/년)
    │           ├── weight_form.dart        # 체중 입력 Form
    │           └── weight_input_card.dart  # 체중 입력 카드
    │
    └── settings/
        ├── domain/entities/
        │   ├── exercise_template.dart     # ExerciseTemplate + TemplateSyncStatus
        │   ├── food_template.dart         # FoodTemplate + FoodTemplateSyncStatus
        │   └── user_profile.dart          # UserProfile (v7, 1인 1프로필)
        ├── data/repositories/
        │   ├── exercise_template_repository.dart      # Interface
        │   ├── sqlite_exercise_template_repository.dart # sqflite 구현체
        │   ├── food_template_repository.dart           # Interface
        │   └── sqlite_food_template_repository.dart    # sqflite 구현체
        ├── utils/
        │   └── date_time_utils.dart       # 상대 시간 포맷, 스프레드시트 ID 축약
        └── presentation/
            ├── providers/
            │   ├── exercise_template_provider.dart    # ExerciseTemplateNotifier
            │   └── food_template_provider.dart        # FoodTemplateNotifier
            ├── screens/
            │   └── settings_screen.dart   # 설정 탭 메인 화면 (카드 ListView)
            └── widgets/
                ├── diet_target_card.dart          # 영양 목표값 설정 (칼로리/탄단지)
                ├── exercise_template_card.dart    # 운동 종목 프리셋 관리 (유형별 그룹)
                ├── food_template_card.dart        # 음식 프리셋 관리
                ├── google_sign_in_card.dart       # Google 로그인/로그아웃
                ├── spreadsheet_status_card.dart   # 스프레드시트 상태 + 동기화 버튼
                └── theme_mode_card.dart           # SegmentedButton 시스템/라이트/다크 전환
```

---

## 6. 데이터 흐름

```
┌──────────────────────────────────────────────────────┐
│                      UI Layer                         │
│  ExerciseScreen / DietScreen / SummaryScreen          │
└─────────────────────┬────────────────────────────────┘
                      │ onPressed / Provider read
                      ▼
┌──────────────────────────────────────────────────────┐
│                  Provider Layer                       │
│  ExerciseNotifier / DietNotifier / SummaryNotifier   │
│  (StateNotifier<List<T>>)                            │
└─────────────────────┬────────────────────────────────┘
                      │ Repository Interface
                      ▼
┌──────────────────────────────────────────────────────┐
│                Repository Layer                       │
│  ExerciseRepository / DietRepository                  │
│  (MockRepository ↔ SqliteRepository)                  │
└─────────────────────┬────────────────────────────────┘
                      │ SQLite
                      ▼
┌──────────────────────────────────────────────────────┐
│                  Data Layer                          │
│  DatabaseHelper (sqflite singleton)                  │
│  - exercise_records 테이블                            │
│  - diet_records 테이블                                │
│  - weight_records 테이블                              │
└──────────────────────────────────────────────────────┘
```

---

## 7. 상태 관리 규칙

### 7.1 Provider 유형

| Provider | 용도 | 범위 |
|----------|------|------|
| `exerciseRecordsProvider` | 운동 기록 목록 | 앱 전역 |
| `dietRecordsProvider` | 식단 기록 목록 | 앱 전역 |
| `weightRecordsProvider` | 체중 기록 목록 | 앱 전역 |
| `dailySummaryProvider` | 일일 요약 데이터 | 앱 전역 |
| `latestWeightProvider` | 가장 최근 체중 | 앱 전역 |
| `todayWeightProvider` | 오늘 기록된 체중 | 앱 전역 |
| `weightChartDataProvider` | 차트용 체중 데이터 (주/월/년 필터) | 앱 전역 |
| `chartViewTypeProvider` | 차트 뷰 타입 (weekly/monthly/yearly) | 앱 전역 |

---

## 8. 애니메이션

### 8.1 Bottom Sheet 열기

```dart
// record_form_sheet.dart
_duration: const Duration(milliseconds: 300)
_curve: Curves.easeOut
_slideAnimation: Offset(0, 1) → Offset(0, 0)
_fadeAnimation: 0.0 → 1.0
```

### 8.2 만족도 별점 (DietForm)

```dart
Icon(i < _satisfaction ? Icons.star : Icons.star_border)
  color: Colors.amber
```

---

## 8.3 BottomNav Liquid Glass 렌더 분기 (iOS 26+)

`_GlassmorphicNavBar` (`lib/shared/widgets/bottom_nav_shell.dart`) 는 blur 백드롭을 런타임 플랫폼에 따라 분기한다.

```dart
final useNativeGlass = NativeLiquidGlassUtils.supportsLiquidGlass;
// true  ⇢ iOS 26+  → LiquidGlassContainer (실제 UIGlassEffect)
// false ⇢ 그 외   → ClipRect + BackdropFilter (Gaussian blur + tint)
```

### 원칙
- **Flutter 기본 `BackdropFilter` 는 단순 Gaussian blur 만 가능** → iOS 26 Liquid Glass 의 굴절·동적 틴트 재현 불가.
- iOS 26+ 에서만 `native_liquid_glass` 패키지의 `LiquidGlassContainer` 를 사용해 진짜 UIGlassEffect 를 백드롭으로 깔고, 그 위에 Flutter 측 pill / specular / 아이콘 / 라벨 을 Stack 으로 얹는다.
- **tint 레이어 (`cs.surface.withOpacity(bgOpacity)`) 는 fallback 경로에서만 활성**. native glass 경로는 무색 유리 (`LiquidGlassEffect.clear`) 유지.
- **Flutter 장식 레이어 (innerGlow / top hairline / `_SpecularHighlight`) 도 fallback 경로 전용**. iOS `UIGlassEffect` 가 edge lensing·specular 를 자체 렌더링하므로 native glass 경로에서는 중복·간섭 → 생략.
- **기본 배경색은 `cs.surfaceContainerHighest @ 0.4 alpha`**. tint 없는 clear glass 는 scaffoldBg 에 묻혀 안 보이고, `UIGlassEffect` 의 adaptive-contrast 가 채도를 과도하게 억제함. 중간 톤 backgroundColor 를 주면 ① 너무 하얗/검정 회피 ② 시스템 보정이 이 색을 기준으로 안정화.

### FAB 공존
- `_MintFab` 은 `FloatingActionButtonLocation.centerFloat` 로 NavBar 위쪽 경계에 걸쳐 있음.
- `LiquidGlassContainer` 내부는 `UiKitView` 를 `IgnorePointer` 로 감싸기 때문에 Flutter 제스처 아레나가 정상 동작 → FAB 탭은 native view 에 가로채이지 않는다.

### 수정 시 주의 (하네스)
1. `LiquidGlassContainer` 를 쓸 때 height 는 반드시 부모 `SizedBox` 로 고정할 것. 내부 Stack 만으로는 unbounded constraint 에러 발생.
2. `LiquidGlassEffect.clear` 는 "색상 없는 순수 유리". 선택 시 사용자 의도가 "투명 유리" 였는지 확인.
3. 패키지 fallback: iOS ≤ 25 에서 `LiquidGlassContainer.build` 는 `SizedBox()` 를 반환함 (텅 빈 박스). 따라서 반드시 `NativeLiquidGlassUtils.supportsLiquidGlass` 플래그로 감싸 분기해야 한다. 바로 쓰면 NavBar 가 사라진다.
4. `iOS Podfile` deployment target 은 16.1 유지. 패키지는 런타임에 iOS 버전을 체크해 자동 fallback 하므로 빌드 target 을 26 으로 올릴 필요 없음.

### 롤백 방법
`useNativeGlass` 를 `false` 로 상수화하면 전체가 Flutter BackdropFilter 경로로 복귀한다 (패키지 의존성은 남지만 런타임 호출 없음).

---

## 9. 관련 문서

| 문서 | 설명 |
|------|------|
| `docs/architecture.md` | 비즈니스 로직, 데이터 흐름, DB 스키마 |
| `CLAUDE.md` (프로젝트 루트) | 핵심 패키지, 아키텍처 개요, Entity 스키마, 주요 규칙 |
