# 도메인 모듈 구조

> **문서 버전**: 2026-04  
> **범위**: 각 도메인의 핵심 기능과 관련 Provider 매핑

| 도메인 | 핵심 기능 | 관련 Provider |
|--------|----------|---------------|
| **exercise** | 운동 기록 (가슴/등... 순서 고정), 볼륨 계산(weight × reps), 루틴 플래너(오늘+프리셋), 인라인 세트 입력, 휴식 타이머 (인앱 + iOS Live Activity + Android 알림), 부위별 기본 휴식 + 종목 override (v11), **1RM 코치**(Epley e1RM + 5주 추세 + 도전 신호등 + Gemini 노트, `lib/core/training/`) | `todayExerciseGroupedProvider`, `todayExerciseCardsProvider`, `todayTotalVolumeProvider`, `routinePlannerProvider`, `workoutRoutinesProvider`, `latestSetOfTodayProvider`, `restTimerProvider`, `restNotificationServiceProvider`, `prRepositoryProvider`, `prSummaryProvider`, `topPrsProvider`, `topExerciseNamesProvider`, `selectedCoachExerciseProvider`, `coachInputWeightProvider`, `coachInputRepsProvider`, `oneRmCoachNoteProvider` |
| **diet** | 식단 기록, 매크로(탄/단/지) 관리, 최근 기록 재추가 · 카드→템플릿 원탭 등록 | `todayDietGroupedProvider`, `todayDietSummaryProvider`, `recentUniqueDietRecordsProvider` |
| **weight** | 체중 기록, 추세 시각화 (주/월/년 필터) | `latestWeightProvider`, `weightChartDataProvider`, `todayWeightProvider`, `chartViewTypeProvider` |
| **summary** | 일일 요약 (fl_chart 시각화) | `dailySummaryProvider` (목표치 참조) |
| **sync** | 구글 시트 동기화, Auth, 목표값 관리 | `syncStateProvider`, `nutritionTargetsProvider` |
| **settings** | 운동·음식 템플릿 관리 (SQLite + 시트 동기화), 기록 폼에서는 `shared/widgets/template_picker_sheet.dart`로 공통 피커 호출 | `exerciseTemplatesProvider`, `foodTemplatesProvider` |
| **theme** | 다크/라이트/시스템 모드 전환 (shared_preferences 영구 저장) | `themeModeProvider` (`ThemeModeNotifier`) |
| **onboarding** | 첫 실행 키/체중/만 나이/활동 수준/운동 강도/목표 입력 + 라우팅 게이트 (`refreshListenable`) | `onboardingDoneProvider`, `heightMProvider` |
| **ai** | Gemini 기반 건강 인사이트 + 코치 챗봇 (데이터 해시 캐시 + 60초 디바운스 + 세션 휘발 챗) | `healthInsightProvider`, `insightCacheProvider`, `insightLastRefreshAtProvider`, `insightCanRefreshProvider`, `suggestedPromptsProvider`, `coachChatProvider`, `coachChatCallCountProvider`, `foodVisionAnalysisProvider` |
| **activity** | Apple Health(HealthKit) / Android Health Connect 활동 데이터(걸음/활동·기초대사 칼로리/평균·안정 시·최대 심박) 조회 — **로컬 캐시만**(Supabase 미동기화), 앱 resume 시 자동 invalidate, 권한 거부/iOS read 불투명성 양가적 안내 | `activityRepositoryProvider`, `healthDataSourceProvider`, `activityAuthStatusProvider`, `dailyActivityProvider` |

---

## 영양 계산 (`lib/core/nutrition/nutrition_calculator.dart`)

순수 함수 `calculateTargets(NutritionCalculationInput)` 하나로 집중 — UI/Provider/DB 어디서도 같은 결과를 재현.

### 입력 (`NutritionCalculationInput`)

| 필드 | 타입 | 비고 |
|------|------|------|
| `heightCm` | `double` | 100 ~ 250 검증 |
| `weightKg` | `double` | 20 ~ 300 검증 |
| `gender` | `UserGender` | `male` / `female` |
| `age` | `int` | 만 나이 (14 ~ 90) — v10 부터 연령대가 아닌 직접 입력 |
| `goal` | `FitnessGoal` | `diet` / `leanMassCut` / `leanMassGain` / `bulkUp` |
| `activityLevel` | `ActivityLevel` | 5단계 — TDEE 배수 결정. 기본 `moderate` |
| `intensity` | `TrainingIntensity` | 4단계 — 단백질 g/kg 결정. 기본 `moderate` |

### 공식

1. **BMR** (Mifflin-St Jeor) — `10·W + 6.25·H − 5·age + (남 +5 / 여 −161)`
2. **TDEE** — `BMR × activityLevel.multiplier` (1.2 / 1.375 / 1.55 / 1.725 / 1.9)
3. **목표 kcal** —
   - `diet`: `TDEE − 500`, 하한 `max(1200, weightKg × 22)`
   - `leanMassCut`: `TDEE − 200`
   - `leanMassGain`: `TDEE + 200`
   - `bulkUp`: `TDEE + 500`
4. **매크로 분배** (10 kcal 반올림 후)
   - 단백질: `weightKg × intensity.proteinGPerKg` (1.8 / 2.0 / 2.2 / 2.4)
   - 지방: `kcal × 22.5% ÷ 9`
   - 탄수: 나머지 (0 클램프)

### 하위호환

- `FitnessGoalX.fromPrefsKey('lean_mass')` → `leanMassGain` (v9 이전 저장값 보호).
- `SyncPreferences.migrateLegacyProfile()` 가 `user_age_group` → `user_age`, `fitness_goal` 레거시 값을 1회 재작성.
