# 아키텍처 문서

> **문서 버전**: 2026-04  
> **범위**: 비즈니스 로직, 데이터 흐름, 동기화 프로토콜

---

## 데이터 파이프라인 (3-Tier Architecture)

- **Input (입력 계층)**: 운동 기록(중량/횟수/RPE), 식단 기록(탄단지/만족도) 입력 UI
- **Process (비즈니스 로직 계층)**: 일일 목표 대비 초과/미달 계산, 부위별 볼륨 계산, 전역 상태 관리
- **Output (출력 계층)**: 진행률, 달성도, 점진적 과부하 추세선 등 시각화

---

## 도메인 분리

| 도메인 | 책임 | 엔티티 |
|--------|------|--------|
| **운동** | 날짜별 부위, 종목, 세트, 중량, RPE 누적 기록 및 추적 | `ExerciseRecord` |
| **식단** | 날짜별 식사 종류(아침, 점심, 저녁, 간식), 음식명, 매크로(탄/단/지), 만족도 기록 | `DietRecord` |
| **체중** | 일별 체중 기록, 주/월/년 추세 시각화 (fl_chart) | `WeightRecord` |
| **요약** | 운동·식단·체중 데이터 병합 → 하루 목표 대비 통합 표시 | `DailySummary` |
| **운동 템플릿** | 운동 종목 프리셋 관리, SQLite + Sheets 동기화 (생성·삭제만) | `ExerciseTemplate` |
| **음식 템플릿** | 음식 프리셋 관리 (이름·칼로리·탄단지), SQLite + Sheets 동기화 (생성·삭제만) | `FoodTemplate` |
| **사용자 프로필** | 키/성별/만 나이/활동 수준(5단계)/운동 강도(4단계)/목표(다이어트·린매스(감량)·린매스(증량)·벌크업)/일일 목표 칼로리 (v7 신규 · v10 확장) | `UserProfile` |
| **온보딩** | 첫 실행 키/체중 입력 → SharedPreferences 플래그 + WeightRecord 생성 | (Notifier만) |
| **AI 인사이트** | Gemini 기반 일일 건강 조언 (캐시·일일 호출 상한 3회) | (Provider 합성) |

---

## 아키텍처 원칙

- **낮은 결합도**: UI는 데이터 소스(로컬 DB, 외부 API)를 모름
- **인터페이스 기반**: Repository 인터페이스로 데이터 접근을 추상화
- **상태 무결성**: 탭 전환 시 모든 다이얼로그/바텀시트를 닫는 `popAll` 정책으로 네비게이션 스택 유지
- **반응형 제약**: 데스크톱/웹 환경을 위해 바텀 시트 최대 너비 600px
- **방어적 개발**: 기존 코드 재사용 우선, 중복 구현 금지

---

## 동기화 프로토콜 (4단계)

`lib/core/sync/sync_state.dart` → `_syncAll()` 함수에서 실행. 백엔드는 **Supabase PostgreSQL** (v7 이후, Google Sheets는 제거됨 — `docs/changelog-v7.md` 참고).

| 단계 | 방향 | 내용 |
|------|------|------|
| **1. Push** | 로컬 → Supabase | `sync_status = created/modified/deleted` 항목을 `batchPush*` 로 upsert. soft-delete 는 `is_deleted=true` 플래그. 성공 시 `synced`로 마킹 |
| **2. Pull** | Supabase → 로컬 | `read*Delta(lastSyncAt)` 로 최근 변경 행을 가져와 로컬에 병합 |
| **3. HardDelete** | 로컬 | `sync_status = deleted` + push 반영 완료된 항목을 로컬 DB에서 영구 삭제 |
| **4. Timestamp 갱신** | — | 오류 없을 때만 `lastSyncTimestamp` 업데이트 |

**Pull 병합 전략**:
- 레코드(`exercise_records`, `diet_records`, `weight_records`): LWW (Last-Write-Wins, `updated_at` 기준)
- 템플릿(`exercise_templates`, `food_templates`): insert-or-skip (uuid 중복 시 무시)
- 루틴(`workout_routines`): LWW
- `daily_routine`: 로컬 전용(동기화 안 함)

**`ensureAllRequiredSheets()`**: legacy Google Sheets 시절의 함수 — Supabase 전환 이후 **no-op**. 호출자 정리 전까지 호환용으로 유지. Supabase 테이블 스키마는 서버 측에서 관리.

**컬럼 추가 시 운영 절차**: 로컬 DB 마이그레이션(`database_helper.dart`)에 앞서 Supabase 대시보드에서 테이블 ALTER 필수 (예: v9의 `exercise_records.set_type`).

---

## DB 스키마

전체 테이블 스키마 및 버전 이력은 `docs/db-schema.md` 참조.

**현재 DB 버전**: v7 (테이블 6개: exercise_records · diet_records · exercise_templates · food_templates · weight_records · user_profiles)

---

> 상세 스키마(컬럼 정의, SyncStatus 정책, 마이그레이션 SQL)는 `docs/db-schema.md` 참조.

## AI 인사이트 & 코치 챗봇 데이터 흐름 (v7+)

`lib/core/ai/` 모듈은 세 축으로 구성된다 — **자동 인사이트 카드**, **코치 챗봇**, **사진 음식 분석**.

### 1) 자동 인사이트 카드 — `health_insight_provider.dart`

```
┌──────────────────────────────────────────────────────┐
│  Inputs (Riverpod watch)                              │
│  • selectedDateProvider                               │
│  • dailySummaryProvider                               │
│  • heightMProvider                                    │
│  • latestWeightProvider + weightChartDataProvider     │
│  • dailyActivityProvider (Apple Health/HC, valueOrNull)│
└─────────────────────┬────────────────────────────────┘
                      │
                      ▼  HealthContext 스냅샷 + contentHash
┌──────────────────────────────────────────────────────┐
│  insightCacheProvider (세션 캐시)                     │
│  • 키: YYYYMMDD-{contentHash}                         │
│  • 데이터 변경 시 키 자동 변경 → 새 호출              │
│  • 변경 없으면 HIT — 불필요 재호출 방지                │
└─────────────────────┬────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────────┐
│  GeminiService.getHealthInsight (gemini-2.5-flash-lite) │
│  • 일일 호출 제한 없음                                │
│  • 무한 재호출 방어:                                  │
│    (a) 해시 캐시  (b) UI 60초 디바운스                │
└──────────────────────────────────────────────────────┘
```

수동 새로고침은 `insightLastRefreshAtProvider`에 탭 시각을 기록하고, `insightCanRefreshProvider` 가 60초 경과 여부로 버튼 활성화를 결정한다. 새로고침 시 세션 캐시를 비우고 `ref.invalidate(healthInsightProvider)`.

### 2) 코치 챗봇 — `coach_chat_notifier.dart` + `suggested_prompts_provider.dart`

```
요약 탭 _AiInsightCard "더 물어보기" CTA
                │
                ▼
showCoachChatSheet (90% 하단 모달)
                │
                ├─ 빈 상태 → suggestedPromptsProvider (규칙 기반, API 호출 0)
                │                │
                │                └─ 20+ 규칙을 카테고리 다양성·우선순위로 랭킹
                │
                └─ 메시지 리스트 + 입력창
                         │
                         ▼  coachChatProvider.send(userMessage)
                   ┌──────────────────────────────────────┐
                   │ coachChatCallCountProvider            │
                   │ 키: coach_chat_count_v1, 상한 30회/일  │
                   │ • 초과 → CHAT_DAILY_LIMIT_REACHED 에러 │
                   │ • 통과 → 호출 직전 카운트++           │
                   └───────────────────┬──────────────────┘
                                       ▼
                   ┌──────────────────────────────────────┐
                   │ GeminiService.coachChat               │
                   │ (gemini-2.5-flash, JSON 모드)         │
                   │ • 최근 6턴 history + HealthContext    │
                   │ • 응답 스키마:                        │
                   │   {answer, follow_ups: [..., ..., ...]} │
                   │ • follow_ups 는 같은 호출에 포함      │
                   │   → 추가 API 호출 0                    │
                   └──────────────────────────────────────┘
```

`coachChatProvider` 는 **autoDispose** 로 모달이 닫히면 히스토리 휘발. 어시스턴트 마지막 메시지의 `follow_ups` 를 다음 추천 칩으로 노출해 대화를 이어간다.

**비용 방어 원칙**: 호출 직전 카운트 증가(increment-before) — 네트워크 실패/예외에도 카운트 소모.  
**세션 히스토리**: SharedPreferences 영속 X — 매번 새 대화로 시작.

---

## 외부 활동 데이터 흐름 (Apple Health / Android Health Connect, 2026-04)

`lib/features/activity/` 도메인은 **외부 source of truth (HealthKit / Health Connect)** 에서 활동 데이터를 읽어 오는 유일한 도메인이다. SQLite/Supabase 동기화 대상이 아니며, Riverpod 인메모리 캐시만으로 동작한다.

### 흐름

```
[OS HealthKit / Health Connect]  ← source of truth
                │
                ▼
HealthDataSource (health: ^13.3.1 래퍼)
  ├─ checkAvailability()       — Health Connect 설치 여부 + 권한 보유 확인
  ├─ requestAuthorization()    — OS 권한 시트 호출
  └─ getDailyActivity(date)    — STEPS/ACTIVE/BASAL/HEART_RATE 집계
                │
                ▼
HealthActivityRepository       — 외부 SDK 타입을 도메인 밖으로 노출 안 함
                │
                ▼
Riverpod (autoDispose + keepAlive)
  ├─ activityAuthStatusProvider  — UI 분기 (권한 카드 vs 활동 카드)
  └─ dailyActivityProvider       — 활동 데이터 (권한 미허용 시 null)
                │
        ┌───────┼─────────────────────────┐
        ▼       ▼                         ▼
  ActivitySummaryCard    HealthContext.activity   (Gemini 프롬프트)
  (요약 탭)              (AI 인사이트 캐시 키 + 프롬프트 라인)
```

### 캐시 무효화 트리거 (결정적)
1. **`AppLifecycleState.resumed`**: `main.dart` 의 `_NacfsonHealthAppWithSyncState.didChangeAppLifecycleState` 가 `ref.invalidate(activityAuthStatusProvider)` + `ref.invalidate(dailyActivityProvider)` 호출. 백그라운드에서 OS 가 권한을 토글한 케이스도 함께 재평가.
2. **명시적 권한 요청**: `requestActivityAuthorization(WidgetRef)` 호출 후 두 provider 모두 invalidate.
3. **`selectedDateProvider` 변경**: `dailyActivityProvider` 가 watch 하므로 자동 재계산.

### 권한 거부 처리
- **Android**: `hasPermissions` 가 명확히 false 를 반환 → `ActivityAuthStatus.denied` → Health Connect 앱 deeplink 안내.
- **iOS**: Apple은 read 권한 거부 여부를 앱에 알려주지 않음. `requestAuthorization` 이 항상 "허용" 반환 → 실제 read 결과로 추론 → `DailyActivity.isEmpty` 일 때 양가적 안내 ("권한 또는 데이터 부재").

### Supabase 동기화 미적용 이유
- HealthKit / Health Connect 가 이미 신뢰할 만한 source of truth 역할
- 다기기 동기화 가치 < 별도 테이블 운영 비용 (Phase 1 기준)
- Phase 2 에서 BMR 자동 계산 / Workout 세션 매핑 / 추세 차트 등이 추가될 때 재평가

### 자체 추정 운동 칼로리는 별도 트랙

요약 탭의 운동 카드에 노출되는 "운동 칼로리(추정치)" 는 위 외부 활동 데이터 흐름과는 **완전히 독립**된 트랙이다.

- 입력: `exercise_records` (사용자가 직접 기록한 sets × reps × weight)
- 공식: `kcal = Σ(weight × reps × 0.01 × 부위계수)` — Scott(2011) 단순 모델, 부위계수만 적용 (EPOC·RPE·set_type 보정 없음, warmup/failure 는 `countsTowardVolume` 으로 제외)
- 위치: `lib/features/exercise/domain/exercise_calorie_estimator.dart` + `body_part_calorie_coefficients.dart`
- HealthKit 의 `activeEnergy` 와 **합산하지 않고 분리 표시** — 워치 자동 인식 운동과의 이중 카운팅 방지. `WorkoutPerformance.estimatedCalories` 가 별도 행으로 노출됨.
- 정확도 ±40% 추정치임을 UI 의 ⓘ 아이콘으로 안내.

---

## iOS Live Activity 흐름 (휴식 타이머)

휴식 타이머의 ±15초 / 일시정지·재개 / 종료가 Dynamic Island · Lock Screen · Home 위젯에 즉시 반영되도록, ActivityKit 호출 일체를 자체 native bridge 가 담당한다. ContentState 가 매 update 마다 의미 있게 변하므로 ActivityKit 이 위젯 rebuild 를 throttling 하지 않는다.

### 컴포넌트
- **Flutter UI**: `RestTimerBar` (`lib/features/exercise/presentation/widgets/rest_timer_bar.dart`) — ±15초·일시정지 버튼.
- **State**: `RestTimerNotifier` (`lib/features/exercise/presentation/providers/rest_timer_provider.dart`) — `endAt` 기반 인앱 카운트다운, `addSeconds` 호출 시 외부 표시도 동시 갱신.
- **Service**: `RestNotificationServiceIOS` (`lib/features/exercise/data/rest_notification_service_ios.dart`) — `MethodChannel('nacfson/rest_activity')` 호출 wrapper. `live_activities` 패키지 의존성은 더 이상 사용하지 않는다.
- **Native Bridge**: `RestActivityBridge` (`ios/Runner/RestActivityBridge.swift`) — `start / update / endActivity / endAll / areEnabled / scheduleDismiss` 메서드 핸들러. `Activity.request(..., pushType: nil)` / `Activity.update(ActivityContent(state:staleDate:))` / `Activity.end(...)` 직접 호출.
- **Attributes**: `RestActivityAttributes` — Runner (`RestActivityBridge.swift`) 와 Widget Extension (`ios/RestActivityWidget/RestActivityAttributes.swift`) 양쪽에 **동일한 이름·레이아웃** 으로 선언. ContentState: `endAtMs: Double, isPaused: Bool, exerciseName: String, totalSeconds: Int`.
- **Widget**: `RestActivityWidget` (`ios/RestActivityWidget/RestActivityWidget.swift`) — `ActivityConfiguration(for: RestActivityAttributes.self)`. `context.state.endAtMs` 등을 직접 읽어 `Text(timerInterval: Date()...endDate)` / `ProgressView(timerInterval:)` 에 바인딩.

### 흐름
```
사용자 ±15초 / 일시정지 토글
  → RestTimerBar
  → RestTimerNotifier.addSeconds() / pause()  (state.endAt 갱신, Timer.periodic 으로 인앱 카운트)
  → RestNotificationServiceIOS.update(endAt, isPaused)
  → MethodChannel('nacfson/rest_activity').invokeMethod('update', {activityId, endAtMs, isPaused})
  → RestActivityBridge.update()
  → activity.update(ActivityContent(
      state: RestActivityAttributes.ContentState(endAtMs, isPaused, exerciseName, totalSeconds),
      staleDate: endDate))
  → ActivityKit: ContentState 변경 감지 → 위젯 rebuild trigger
  → SwiftUI: context.state 의 새 endAtMs 로 Text(timerInterval:) 재바인딩
  → Dynamic Island / Lock Screen 카운트다운 즉시 반영
```

### 설계 근거
- `live_activities` 패키지의 `LiveActivitiesAppAttributes.ContentState` 는 `appGroupId: String` 단일 필드라 update 호출 시 **state 변경 없는 update** 가 되어 ActivityKit 이 위젯 rebuild 를 강하게 throttling 했다. 결과적으로 매 update 의 새 `endAtMs` 가 위젯의 `Text(timerInterval:)` 바인딩에 반영되지 않는 race 가 발생.
- 자체 attribute 로 ContentState 를 의미 있게 갱신함으로써 trigger 누락을 해소하고, App Group `UserDefaults` 의 `"\(activity.id)_\(key)"` 우회를 단일 데이터 소스 (ContentState) 로 일원화.
- `pushType: nil` 명시로 Personal Apple ID 팀에서도 `aps-environment` 엔타이틀먼트 불필요. App Store 배포 시 push 기반 update 가 필요해지면 bridge 가 ActivityKit `pushType: .token` 로 전환하면 된다.

### 잔여 정리 (Cleanup)
- `live_activities` / `permission_handler` (iOS) 패키지 의존성은 코드상 사용처가 사라진 뒤 별도 cleanup PR 에서 제거.
- 레거시 `LiveActivitiesAppAttributes` 선언은 이전 버전 잔여 activity 정리 (`endAll`) 경로에서만 유지. 두 버전 이상 경과하면 안전하게 제거 가능.

---

## 라우팅 흐름 (v7)

`lib/core/router/app_router.dart` — Riverpod 상태와 GoRouter redirect를 연결하는 패턴.

```
onboardingDoneProvider (StateNotifier<bool>)
                │ ref.listen
                ▼
_RouterNotifier (ChangeNotifier)
                │ notifyListeners()
                ▼
GoRouter.refreshListenable
                │
                ▼
_RouterNotifier.redirect(context, state)
  • !done && path != '/onboarding' → '/onboarding'
  • done && path == '/onboarding' → '/exercise'
  • else → null (현재 경로 유지)
```

**핵심 함정**: `appRouterProvider` 내부에서 notifier를 가져올 때 `ref.read`만 사용. `ref.watch`로 가져오면 라우터 객체 자체가 재생성되며 네비 스택이 초기화됨. 자세한 사례는 `docs/build-debug.md` #3.

---

### 요약 엔티티 (`DailySummary`) — DB 테이블 아님, 메모리 계산

| 필드 | 타입 | 설명 |
|------|------|------|
| `consumedCalories` | int | 당일 식단 칼로리 합계 |
| `targetCalories` | int | 목표 칼로리 (SharedPreferences에서 읽음) |
| `macroStatus` | Map | 탄/단/지 각각의 섭취량·목표·달성률 |
| `calorieResult` | enum | 달성/초과/미달 → UI 색상 분기용 |
| `isWorkoutDay` | bool | 당일 운동 기록 존재 여부 |
| `targetedMuscles` | List | 당일 자극 부위 목록 (캘린더 Dot 표시용) |
| `totalVolume` | double | 당일 총 운동 볼륨 (중량×횟수×세트 합, kg) |
| `averageRPE` | double | 당일 평균 자각강도 |