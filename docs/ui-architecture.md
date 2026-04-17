# UI Architecture

> **문서 버전**: 2026-04  
> **범위**: 네비게이션, 레이아웃, 상태 관리  
> **플랫폼**: Flutter (iOS, Android, macOS, Windows, Linux, Web)

---

## 1. 전체 구조

```
┌─────────────────────────────────────────┐
│              NacfsonHealthApp            │
│         (MaterialApp.router)             │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│              GoRouter                    │
│  ┌─────────────────────────────────────┐ │
│  │         ShellRoute                  │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │      BottomNavShell             │ │ │
│  │  │  ┌───────────────────────────┐ │ │ │
│  │  │  │       Scaffold.body       │ │ │ │
│  │  │  │   (ExerciseScreen 등)      │ │ │ │
│  │  │  └───────────────────────────┘ │ │ │
│  │  │  ┌───────────────────────────┐ │ │ │
│  │  │  │     NavigationBar              │ │ │ │
│  │  │  │  운동 │ 식단 │ 요약 │ 체중 │ 설정  │ │ │ │
│  │  │  └────────────────────────────────┘ │ │ │
│  │  └─────────────────────────────────┘ │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

---

## 2. 네비게이션 구조

### 2.1 경로 테이블

| 경로 | 화면 | 설명 |
|------|------|------|
| `/exercise` | `ExerciseScreen` | 운동 기록 탭 |
| `/diet` | `DietScreen` | 식단 기록 탭 |
| `/summary` | `SummaryScreen` | 요약/통계 탭 |
| `/weight` | `WeightScreen` | 체중 기록/차트 탭 |
| `/settings` | `SettingsScreen` | Google 연동 설정 탭 |

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
  if (location.startsWith('/summary')) return 2;
  if (location.startsWith('/weight')) return 3;
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
│  Align (bottomCenter)                │
│  └─ ConstrainedBox (maxWidth: 600)   │
│     └─ RecordFormSheet (공통 컨테이너) │
│        └─ SingleChildScrollView      │
│           └─ Padding (viewInsets)    │
└──────────────────────────────────────┘
```

---

## 4. 폼 구조

모든 입력 폼은 `RecordFormSheet` 컨테이너로 감싸져 슬라이드업 애니메이션이 적용됨.

- **ExerciseForm**: 운동 기록 (exerciseType, exerciseName, currentSet, weight, reps, rpe)
- **DietForm**: 식단 기록 (mealType, foodName, totalCalories, carbs, protein, fat, satisfaction, memo, timestamp)

자세한 필드 정의는 `CLAUDE.md` Entity 스키마 참고.

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
│   │   └── app_theme.dart            # LightTheme (Material 3)
│   └── widget/
│       └── home_widget_service.dart   # iOS 홈 위젯 영양 데이터 연동
│
├── shared/
│   └── widgets/
│       ├── bottom_nav_shell.dart     # 하단 네비게이션 셸 (5탭)
│       ├── empty_state.dart          # 빈 상태 공통 위젯 (아이콘+텍스트+버튼)
│       ├── error_overlay.dart        # 에러 오버레이 (자동 닫힘)
│       └── record_form_sheet.dart    # Bottom Sheet 공통 컨테이너 (Animation)
│
└── features/
    ├── exercise/
    │   ├── domain/entities/
    │   │   └── exercise_record.dart  # Entity + SyncStatus enum
    │   ├── data/repositories/
    │   │   ├── exercise_repository.dart      # Interface
    │   │   └── sqlite_exercise_repository.dart # sqflite 구현체
    │   └── presentation/
    │       ├── providers/
    │       │   └── exercise_provider.dart   # ExerciseNotifier + 2레벨 그룹핑
    │       ├── screens/
    │       │   └── exercise_screen.dart    # 운동 기록 화면
    │       └── widgets/
    │           ├── exercise_form.dart      # 운동 기록 입력 Form (직접입력/템플릿)
    │           ├── exercise_group_card.dart # 종목별 세트 그룹 카드
    │           └── exercise_record_card.dart # 개별 기록 카드 + 유형 색상/아이콘
    │
    ├── diet/
    │   ├── domain/entities/
    │   │   └── diet_record.dart      # Entity
    │   ├── data/repositories/
    │   │   ├── diet_repository.dart        # Interface
    │   │   └── sqlite_diet_repository.dart  # sqflite 구현체
    │   └── presentation/
    │       ├── providers/
    │       │   └── diet_provider.dart      # DietNotifier
    │       ├── screens/
    │       │   └── diet_screen.dart        # 식단 기록 화면
    │       └── widgets/
    │           ├── diet_form.dart          # 식단 기록 입력 Form (템플릿 드롭다운)
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
        │   └── food_template.dart         # FoodTemplate + FoodTemplateSyncStatus
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
                └── spreadsheet_status_card.dart   # 스프레드시트 상태 + 동기화 버튼
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

## 9. 관련 문서

| 문서 | 설명 |
|------|------|
| `docs/architecture.md` | 비즈니스 로직, 데이터 흐름, DB 스키마 |
| `CLAUDE.md` (프로젝트 루트) | 핵심 패키지, 아키텍처 개요, Entity 스키마, 주요 규칙 |
