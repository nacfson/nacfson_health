# v6 변경 로그 (DB v7 · AI 인사이트 · 온보딩 · 다크 모드)

## 개요
한 번의 큰 호흡으로 네 가지 흐름을 묶어 출시한 버전. **DB는 v6→v7**로 한 단계 올라갔으며(테이블 5→6), Gemini 기반 일일 건강 조언, 첫 실행 온보딩, 시스템/라이트/다크 테마 전환, Pretendard 한글 폰트가 추가되었다. 차트(주간/월간 추세)와 전역 날짜 탐색이 추가되어 과거 날짜를 자유롭게 열람할 수 있다.

---

## 데이터베이스 (v6 → v7)

### 마이그레이션
- `version: 6` → `version: 7`
- `_upgradeDB`에 추가:
  ```dart
  if (oldVersion < 7) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        gender TEXT NOT NULL,
        age_group TEXT NOT NULL,
        height REAL NOT NULL,
        goal TEXT NOT NULL,
        target_calories INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER DEFAULT 1
      )
    ''');
  }
  ```

### 신규 테이블 `user_profiles`
- 1인 1프로필 — 키(m) / 성별 / 연령대 / 목표(lose/maintain/gain) / 일일 목표 칼로리
- v7 시점 **로컬 전용** (Google Sheets 동기화 미적용)
- 상세: `docs/db-schema.md` §6

### 파일
- `lib/core/database/database_helper.dart`: version 7, `_upgradeDB` v7 분기
- `lib/features/settings/domain/entities/user_profile.dart`: Entity + `SyncStatus` enum
- `docs/db-schema.md` 갱신, `CLAUDE.md` DB 버전 라인 갱신

---

## AI 건강 인사이트

### 신규 컴포넌트
| 파일 | 역할 |
|------|------|
| `lib/core/ai/gemini_service.dart` | `gemini-2.5-flash-lite` 모델로 한국어 150자 이내 건강 조언 생성 (`.env` `GEMINI_API_KEY`) |
| `lib/core/ai/health_insight_provider.dart` | 세션 캐시 + 일일 호출 상한(3회) + `FutureProvider.autoDispose` 합성 |
| `lib/features/summary/presentation/screens/summary_screen.dart` 내 `_AiInsightCard` | 요약 화면 카드 UI (loading/error/data + 새로고침) |

### 호출 정책 (비용 방어 우선)
- **세션 캐시** (`insightCacheProvider`): 키 `YYYYMMDD`, 같은 날 재방문 시 즉시 반환
- **일일 호출 상한** (`insightCallCountProvider`): SharedPreferences `insight_call_count_v1`, 상한 `kInsightDailyLimit = 3`
- **호출 직전 증가** (increment-before): 네트워크 실패 시에도 카운트 소모
- **상한 초과**: `throw StateError('DAILY_LIMIT_REACHED')` → UI는 `AsyncValue.error` 분기에서 안내
- **새로고침**: 카드 아이콘 → 캐시 키 삭제 + `ref.invalidate(healthInsightProvider)`

### 입력 데이터
`selectedDate` + `dailySummary`(운동·식단 합성) + `heightM` + `latestWeight` + 최근 7일 `weightChartDataProvider` → BMI 자동 계산 후 프롬프트 합성.

### 의존성
- `google_generative_ai: ^0.4.7` (`pubspec.yaml`)
- 기존 `flutter_dotenv`로 키 주입

---

## 온보딩 + 사용자 프로필

### 신규 컴포넌트
| 파일 | 역할 |
|------|------|
| `lib/features/onboarding/presentation/screens/onboarding_screen.dart` | 첫 실행 키(cm)/체중(kg) 입력 화면 |
| `lib/shared/providers/user_profile_provider.dart` | `HeightNotifier`(m), `OnboardingNotifier` (둘 다 SharedPreferences 영속) |
| `lib/shared/providers/selected_date_provider.dart` | `selectedDateProvider` + `isSelectedDateTodayProvider` (전역 날짜 상태) |
| `lib/shared/widgets/date_navigation_bar.dart` | 날짜 좌우 이동 + DatePicker + Today 버튼 |

### 라우팅 게이트
`lib/core/router/app_router.dart`에 `_RouterNotifier` 도입:
- `onboardingDoneProvider`를 `ref.listen` → `notifyListeners()`
- GoRouter `refreshListenable` + `redirect` 콜백으로 미완료 시 강제 `/onboarding`
- **함정**: `appRouterProvider` 내부에서는 반드시 `ref.read(_routerNotifierProvider)` (watch 금지 — 라우터 재생성 시 네비 스택 초기화). 자세한 사례는 `docs/build-debug.md` #3.

### 첫 실행 플로우
1. `main.dart`에서 SharedPreferences `onboarding_done`, `user_height_m` 미리 로드 → `overrideWith`로 Notifier 초기화 (플리커 방지)
2. `_RouterNotifier.redirect`가 `/onboarding`으로 강제
3. 사용자 입력 → `setHeight()` + `complete()` + `WeightRecord` 오늘 날짜로 자동 저장
4. `notifyListeners()` → GoRouter 재평가 → `/exercise`로 자동 이동

### BMI 동적 계산
`_BmiBar`(요약 화면)가 `ConsumerWidget`으로 전환되어 `heightMProvider`를 watch — 체중·키 변동 시 즉시 갱신.

---

## 다크 모드 + Pretendard 폰트

### 테마 전환
| 파일 | 역할 |
|------|------|
| `lib/core/theme/app_theme.dart` | `lightTheme` + `darkTheme` 양쪽 정의 (Material 3 ColorScheme 토큰화) |
| `lib/core/theme/theme_mode_provider.dart` | `ThemeModeNotifier` — `system`/`light`/`dark` 3-way, `SyncPreferences.themeModeRaw` 영속 |
| `lib/features/settings/presentation/widgets/theme_mode_card.dart` | 설정 화면 SegmentedButton |

### 다크 잔여 흰색 전수 정비
- glassmorphic NavBar
- TriRing 트랙(다크 22% / 라이트 12% 투명도)
- AI 인사이트 카드, BMI 바, 차트 목표선
- DateNavigationBar, OnboardingScreen, Autocomplete 드롭다운

### Pretendard 폰트
- `assets/fonts/Pretendard-{Regular,Medium,SemiBold,Bold}.ttf`
- `pubspec.yaml`의 `flutter.fonts`에 4 weight 등록
- `ThemeData.fontFamily: 'Pretendard'`로 라이트/다크 양쪽 적용

---

## UI/UX 개선

### 추세 차트
- `VolumeTrendChart` (`lib/features/exercise/.../volume_trend_chart.dart`): 운동 볼륨 주간/월간 LineChart, mint 그라디언트, k-notation
- `CalorieTrendChart` (`lib/features/diet/.../calorie_trend_chart.dart`): 칼로리 주간/월간 BarChart, 빨간 점선 목표선, 105% 초과 시 코랄 강조
- 새 Provider: `volumeTrendDataProvider`, `calorieTrendDataProvider`, `*ChartViewTypeProvider`

### 시트 & FAB 일원화
- `RecordFormSheet`: `DraggableScrollableSheet` 기반 (initial 0.85 / min 0.45 / max 0.95)
- `lib/core/providers/sheet_state_provider.dart`: `activeSheetProvider` + `openSheet()` 헬퍼 — 직접 `showModalBottomSheet` 호출 금지
- `BottomNavShell`의 FAB는 `activeSheetProvider`를 watch → 시트 열림 시 자동 숨김
- 중복 "운동 추가/식사 추가" 버튼을 `EmptyState`에서 제거, 하단 FAB로 통일 (탭 하단 여백 96→120)

### 점진적 과부하
`ExerciseForm`이 동일 종목의 직전 기록을 참조해 표시 (Strong 앱 방식).

### 자동 동기화
`AuthCallbackScreen` → `performSync()` 즉시 호출 (Google 로그인 직후).

---

## 신규 패키지

`pubspec.yaml`:
- `flutter_localizations` (sdk) — 다이얼로그 한글화
- `google_generative_ai: ^0.4.7` — Gemini SDK

---

## 검증 체크리스트

- [x] DB 마이그레이션 v6 → v7 (user_profiles 생성)
- [x] 첫 실행 시 `/onboarding` 강제 진입
- [x] 온보딩 완료 후 `/exercise` 자동 이동
- [x] 같은 날 요약 탭 재방문 → Gemini 미호출 (캐시 적중)
- [x] 일일 4회째 호출 시 `DAILY_LIMIT_REACHED` 처리
- [x] 시스템/라이트/다크 테마 전환 후 재시작 시 유지 (`SyncPreferences.themeModeRaw`)
- [x] 다크 모드에서 NavBar/카드/차트 흰색 잔존 없음
- [x] DateNavigationBar 미래 날짜 forward 비활성화
- [x] 운동/식단 추세 차트 weekly/monthly 토글 정상
- [x] FAB 자동 숨김 (`activeSheetProvider` 연동)

---

## 관련 문서 업데이트

| 문서 | 변경 |
|------|------|
| `CLAUDE.md` | DB 버전 라인 v6 → v7, 라우팅에 `build-debug.md` 추가, 참조 문서 표에 `changelog-v6.md` 추가 |
| `docs/db-schema.md` | v7 / 6 테이블, `user_profiles` 스키마 추가, `exercise_templates.exercise_type` 컬럼 명시 |
| `docs/architecture.md` | DB 버전, 도메인 표(ai/onboarding/사용자프로필), AI 인사이트 흐름, 라우팅 흐름 섹션 추가 |
| `docs/implementation-guide.md` | `FutureProvider.autoDispose` 패턴, 온보딩 1회성 플래그, `refreshListenable`, `SyncPreferences` 일원화 추가 |
| `docs/conventions.md` | Pretendard 폰트, 다크 테마 토큰, `DraggableScrollableSheet` + `openSheet()` 룰 추가 |
| `docs/domains.md` | `ai`, `onboarding` 행 추가 |
| `docs/ui-architecture.md` | `/onboarding`/`/login-callback` 경로, 공통 위젯 표(DateNavigationBar/TriRing/차트), 위젯 트리에 신규 파일 추가 |
| `docs/features.md` | 추세 차트·다크 모드·온보딩·AI 인사이트 체크박스 반영 |
| `docs/build-debug.md` | (이미 추가) StateNotifier 비동기 초기화, GoRouter `refreshListenable` 함정 |

---

## UI 정리

- **운동 탭 `_PeriodFilterBar` 제거**: `[일/주/월/년]` 기간 필터 바는 어떤 Provider/필터링과도 연결되지 않은 미사용 UI라 삭제 (`lib/features/exercise/presentation/screens/exercise_screen.dart`).
- **식단 탭 `_WeekDateStrip` 제거**: `[월/화/…/일]` 7일 날짜 스트립을 제거. `selectedDateProvider` 갱신은 바로 위 `DateNavigationBar`(좌우 화살표 + 달력 + "오늘")가 동일하게 처리하므로 중복 (`lib/features/diet/presentation/screens/diet_screen.dart`).
- 두 화면 모두 날짜 선택은 이제 `DateNavigationBar` 하나로 일원화.

---

## 패치: 온보딩 목표 기반 영양 목표 자동 계산

### 개요
온보딩 화면에서 키·체중과 함께 **성별·나이대·피트니스 목표**(다이어트/린매스업/벌크업)를 수집하도록 확장하고, Mifflin-St Jeor BMR × 활동계수 1.55 기반 TDEE에 목표별 보정(-500 / +200 / +400 kcal)과 매크로 분배(단백질 1.8 g/kg · 지방 22.5% · 탄수 나머지)를 적용하여 `nutritionTargetsProvider`의 초기값을 seed한다. 기존 1800/250/150/60 하드코딩 기본값 대비 사용자 체형에 맞춘 값이 즉시 적용된다.

### 신규
- `lib/core/nutrition/nutrition_calculator.dart` — `FitnessGoal` / `UserGender` / `AgeGroup` enum + extension(label/prefsKey/fromPrefsKey) + `calculateTargets(...)` 순수 함수
- `test/core/nutrition/nutrition_calculator_test.dart` — BMR/TDEE/매크로 합산/하한/enum 왕복 검증

### 변경
- `lib/features/onboarding/presentation/screens/onboarding_screen.dart` — 성별 `SegmentedButton`, 나이대 `ChoiceChip`(20대/30대/40대/50대 이상), 목표 `SegmentedButton`(다이어트/린매스업/벌크업), 실시간 `_NutritionPreview` 카드 추가. `_submit()`에서 `SyncPreferences`에 성별/나이대/목표 저장 후 `calculateTargets(...)` 결과를 `nutritionTargetsProvider.update(...)`로 seed
- `lib/core/sync/sync_preferences.dart` — `user_gender` · `user_age_group` · `fitness_goal` 키 추가 (String) + getter/setter 쌍
- `lib/features/settings/presentation/widgets/diet_target_card.dart` — `_GoalRecalculateRow` 추가: 현재 목표 라벨(탭하여 bottom sheet로 변경), '목표 기반 재계산' 버튼(최신 체중 + 저장된 프로필 기반 재계산 후 컨트롤러 채움, 저장은 사용자가 직접 '저장' 탭)

### 공식
- BMR (Mifflin-St Jeor): 남 `10w + 6.25h − 5a + 5`, 여 `10w + 6.25h − 5a − 161` (a=나이대 중앙값)
- TDEE = BMR × 1.55
- 목표 kcal: 다이어트 `TDEE − 500` (하한 `max(1200, weightKg × 22)`), 린매스업 `TDEE + 200`, 벌크업 `TDEE + 400`
- 단백질 = weightKg × 1.8 g, 지방 = kcal × 0.225 / 9, 탄수 = 나머지 (음수 clamp, 10 kcal / 1 g 단위 반올림)

### 미적용 (의도적 제외)
- `user_profiles` DB 테이블 쓰기 — 현재 앱이 해당 테이블을 읽지 않으므로 DB Repository 추가 없이 SharedPreferences만 사용. 추후 Google Sheets 동기화 추가 시 연결 예정.

---

## 브레이킹 체인지 ⚠️

- **첫 실행 강제 온보딩**: 기존 사용자(SharedPreferences 미보유)는 한 번 키/체중 입력 화면을 거친다.
- **`exercise_templates.exercise_type=''` 행 일괄 삭제** (v6에서 처리, v7 진입자에게도 누적 적용).

---

## 다음 단계 (선택)

- [ ] AI 인사이트 영구 캐싱 (같은 날 데이터 변경 없으면 재호출 생략)
- [ ] 설정 화면에서 키 수정 (현재는 온보딩에서만 입력)
- [ ] `user_profiles` Google Sheets 동기화
- [ ] 운동 기록 캘린더 뷰 (부위별 Dot 표시)
- [ ] 스트릭 시스템 (연속 기록 동기부여)
