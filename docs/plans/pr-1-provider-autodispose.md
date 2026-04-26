# 후속 PR #1 — 1RM 코치 Provider `autoDispose` 적용 + `keepAlive` 윈도우

> **상위 작업**: 1RM 코치 메인 PR (이전 commit) 의 후속 최적화 시리즈 1/3
> **연관 PR**: #2 종목별 입력값 자동 초기화 + 칩 자동 스크롤 (별도 plan), #3 PrRepository 단위 테스트 (별도 plan)
> **DB 마이그레이션**: 없음
> **공개 API 변경**: 없음 (Provider 시그니처는 유지, lifecycle 만 변경)

---

## 0. Context — 왜 이 PR 이 필요한가

1RM 코치 메인 PR 에서 신규로 추가된 4개 Riverpod Provider 가 모두 **일반 (non-autoDispose) 변형**으로 정의됨.
일반 Provider 는 한 번 인스턴스화되면 앱 lifetime 동안 dispose 되지 않으며, 의존하는 다른 Provider (특히 `exerciseRecordsProvider`) 가 변경될 때마다 **백그라운드에서 자동 재계산** 된다.

전수 재검사 §3 에서 식별된 문제:
- 사용자가 1RM 코치 화면을 닫고 다른 탭에서 운동 세트를 추가/수정해도 4개 Provider 모두 invalidate → 재계산 (= DB 쿼리 발동).
- 특히 `topPrsProvider` 는 한 번 호출에 최대 30~45 DB 쿼리 (#2 N+1 이슈와 결합) — 보지 않는 화면을 위해 비싼 쿼리가 반복 실행됨.
- 메모리: PrSummary 객체 + family 의 모든 인스턴스가 유지됨. 종목 수가 늘어나면 누적.

해결 원칙:
1. **`autoDispose`** — listener 가 0 이 되면 dispose. 화면 닫히면 재계산 안 됨.
2. **`ref.keepAlive()` + Timer 윈도우** — 짧은 간격 재진입 (예: 칩 A→B→A 전환) 시 캐시 유지로 깜빡임 방지.

---

## 1. 변경 대상 Provider (4개)

모두 `lib/features/exercise/presentation/providers/one_rm_coach_provider.dart` 에 정의됨.

| # | Provider | 현재 타입 | 변경 후 타입 | 사용처 |
|---|----------|-----------|--------------|--------|
| 1 | `topExerciseNamesProvider` | `FutureProvider` | `FutureProvider.autoDispose` | `ExerciseChips` (1RM 코치 풀스크린 상단) |
| 2 | `prSummaryProvider` | `FutureProvider.family` | `FutureProvider.family.autoDispose` + `keepAlive` 30초 | `_Body` (1RM 코치), `topPrsProvider` 내부 호출 |
| 3 | `topPrsProvider` | `FutureProvider` | `FutureProvider.autoDispose` | `RecentPrCard` (요약 탭) |
| 4 | `oneRmCoachNoteProvider` | `FutureProvider.family` | `FutureProvider.family.autoDispose` | `CoachNoteCard` (1RM 코치) |

---

## 2. Riverpod `autoDispose` 동작 원리 (배경 지식)

### 2-1. listener counting
- 일반 `Provider`: 한 번 read/watch 되면 `ProviderContainer` 안에 인스턴스가 영구 보관 (앱 종료까지).
- `autoDispose`: listener (= `ref.watch` 한 위젯/Provider) 의 수를 추적. **`listener.count == 0` 이 되는 순간 즉시 dispose** (microtask 큐에 dispose 예약).

### 2-2. `family + autoDispose`
- family 의 각 파라미터 인스턴스가 **독립적인 lifecycle**.
- 예: `prSummaryProvider('스쿼트')` 와 `prSummaryProvider('벤치프레스')` 는 별개로 dispose.
- 사용자가 칩 A → B 로 전환하면, A 의 listener 가 0 이 되어 즉시 dispose. 다시 A 로 돌아가면 새 인스턴스 생성 + 새 쿼리 실행.

### 2-3. `ref.keepAlive()` 과 Timer 윈도우
```dart
final link = ref.keepAlive();
Timer(Duration(seconds: 30), link.close);
```
- `keepAlive()` 호출 시점부터 listener 수와 무관하게 살아있음.
- `link.close()` 호출 시 다시 일반 autoDispose 규칙 적용 (그 시점 listener 가 0 이면 dispose).
- 효과: "30초 안에 같은 종목 재선택 시 캐시 사용, 그 이상이면 새로 쿼리".

### 2-4. autoDispose 의존성 전파
- `autoDispose` Provider 가 일반 Provider 를 watch 하는 것은 OK.
- 일반 Provider 가 `autoDispose` Provider 를 watch 하려면 명시적으로 `ref.watch(autoDisposeProvider)` 가능 (Riverpod 2.x 부터 제약 완화됨).
- 우리 케이스: `topPrsProvider(autoDispose)` → `prSummaryProvider(family.autoDispose)` 호출 — 같은 autoDispose 계열이므로 안전.

---

## 3. 변경 코드 — Before/After

### 3-1. `topExerciseNamesProvider`

#### Before
```dart
/// 1RM 코치 칩에 노출할 종목 후보 (최근 90일 볼륨 상위 8개).
final topExerciseNamesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopExerciseNames();
});
```

#### After
```dart
/// 1RM 코치 칩에 노출할 종목 후보 (최근 90일 볼륨 상위 8개).
///
/// **lifecycle**: autoDispose. 1RM 코치 화면이 닫히면 dispose.
/// 다른 탭(요약/운동/식단/체중/설정)에서 운동 세트가 추가되어도
/// `exerciseRecordsProvider` invalidate 가 이 Provider 까지 전파되지 않는다
/// (이미 dispose 되었으므로). 다시 1RM 코치 진입 시 새로 쿼리.
final topExerciseNamesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopExerciseNames();
});
```

**SQL 쿼리 자체는 동일** (`SELECT exercise_name, SUM(weight*reps) ... GROUP BY ... LIMIT 8`).
변경되는 것은 **쿼리가 실행되는 빈도**.

### 3-2. `prSummaryProvider` (family + autoDispose + keepAlive 30초)

#### Before
```dart
/// 선택된 종목의 PR 요약 (FutureProvider.family).
final prSummaryProvider =
    FutureProvider.family<PrSummary, String>((ref, exerciseName) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getPrSummary(exerciseName);
});
```

#### After
```dart
/// 선택된 종목의 PR 요약 (FutureProvider.family).
///
/// **lifecycle**: family.autoDispose + keepAlive 30 초 윈도우.
/// 사용자가 칩 A → B → A 로 빠르게 전환할 때 30 초 안의 재선택은
/// 캐시 히트 (DB 쿼리 X). 30 초 경과 후에는 listener 0 이면 dispose.
///
/// **재계산 트리거**:
///   1. 화면이 활성 상태에서 `exerciseRecordsProvider` 변경 (세트 추가/수정)
///   2. 30 초 keepAlive 윈도우 종료 + listener 0 + 재진입
final prSummaryProvider = FutureProvider.family
    .autoDispose<PrSummary, String>((ref, exerciseName) async {
  // 빠른 칩 전환 / 화면 짧은 잠시 떠남 시 캐시 유지
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 30), link.close);
  ref.onDispose(timer.cancel);

  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getPrSummary(exerciseName);
});
```

**핵심 포인트**:
- `ref.keepAlive()` 가 반환하는 `link` 를 30초 후에 `close` → 일반 autoDispose 규칙 복귀.
- `ref.onDispose(timer.cancel)` 로 Timer 누수 방지 (Provider 가 어떤 이유로든 dispose 되면 Timer 취소).
- `exerciseRecordsProvider` 변경 시에는 `keepAlive` 와 무관하게 invalidate (Provider 본체가 재실행됨).

**SQL 쿼리 동일** (`getPrSummary` 의 5주 work/drop 조회 + failure count).

### 3-3. `topPrsProvider`

#### Before
```dart
/// 요약 탭 RecentPrCard 용 — 상위 3개 PR.
final topPrsProvider = FutureProvider<List<PrSummary>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopPrs();
});
```

#### After
```dart
/// 요약 탭 RecentPrCard 용 — 상위 3개 PR.
///
/// **lifecycle**: autoDispose.
/// 요약 탭에서 다른 탭으로 이동하면 RecentPrCard 가 unmount 되지 않을 수
/// 있다 (BottomNavShell + NoTransitionPage 가 화면을 메모리에 유지).
/// 따라서 이 autoDispose 의 실질 효과는 "앱 종료" 또는 "강제 invalidate"
/// 까지는 거의 영구. 그래도 명시적으로 autoDispose 로 두면:
///   - 향후 BottomNavShell 의 keepAlive 정책이 바뀌어도 자동 적응.
///   - `ref.invalidate(topPrsProvider)` 호출 시 다음 read 까지 결과 폐기.
final topPrsProvider =
    FutureProvider.autoDispose<List<PrSummary>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopPrs();
});
```

> **주의**: 현재 BottomNavShell 동작상 요약 탭 RecentPrCard 는 사실상 영구 listener.
> 따라서 본 변경의 실질 효과는 "미미" 하지만 **시멘틱 일관성** 과 **미래 변경 대비** 차원에서 적용.
> 실제 큰 성능 이득은 #2 N+1 PR 에서 발생 (병렬화 + 풀 축소).

**SQL 동일** (`getTopExerciseNames` 1회 + 종목당 `getPrSummary` N회).

### 3-4. `oneRmCoachNoteProvider` (family + autoDispose)

#### Before
```dart
final oneRmCoachNoteProvider =
    FutureProvider.family<String, CoachNoteRequest>((ref, req) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(req.cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;
  // ...
});
```

#### After
```dart
/// **lifecycle**: family.autoDispose.
/// CoachNoteCard 가 unmount 되거나 종목/신호등이 바뀌면 listener 0 → dispose.
/// SharedPreferences 캐시는 영속이므로 dispose 후 재진입 시에도
/// 같은 날짜·종목·신호등이면 즉시 캐시 히트 (Gemini 호출 X).
final oneRmCoachNoteProvider = FutureProvider.family
    .autoDispose<String, CoachNoteRequest>((ref, req) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(req.cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;
  // ... 이하 변경 없음
});
```

**Gemini API 호출 / SharedPreferences 캐시 로직 동일.**
변경되는 것은 family 인스턴스의 메모리 lifecycle.

---

## 4. Provider 의존성 그래프 변화

### Before
```
exerciseRecordsProvider (StateNotifier, persistent)
  │
  ├─watch─→ topExerciseNamesProvider (Future, persistent)        ← 한번 생성되면 영구
  │
  ├─watch─→ prSummaryProvider(family, persistent)                 ← 종목별로 누적
  │            │
  │            └─사용처─→ _Body, topPrsProvider
  │
  └─watch─→ topPrsProvider (Future, persistent)                   ← 한번 생성되면 영구
                │
                └─호출─→ prSummaryProvider(family) × 15

oneRmCoachNoteProvider(family, persistent)                        ← 종목×신호등×날짜 별 누적
```

### After
```
exerciseRecordsProvider (StateNotifier, persistent)               ← 변경 없음
  │
  ├─watch─→ topExerciseNamesProvider (autoDispose)
  │            └─dispose 시점: 1RM 코치 화면 닫힐 때
  │
  ├─watch─→ prSummaryProvider(family.autoDispose + keepAlive 30s)
  │            └─dispose 시점: 화면 닫고 30초 + 재진입 안 함
  │            └─keepAlive 효과: 칩 빠른 전환 시 캐시 유지
  │
  └─watch─→ topPrsProvider (autoDispose)
                └─dispose 시점: BottomNavShell 정책 의존 (사실상 영구)

oneRmCoachNoteProvider(family.autoDispose)
   └─dispose 시점: CoachNoteCard 사라지거나 다른 종목/신호등 선택 시
```

---

## 5. 사용자 시나리오별 동작 비교 (정확한 쿼리 수)

### 시나리오 A: 1RM 코치 진입 → 스쿼트 보기 → 닫기 → 다른 탭에서 세트 추가 → 재진입

| 단계 | Before — 쿼리 수 | After — 쿼리 수 |
|------|------------------|-----------------|
| 진입 (스쿼트 자동 선택) | `getTopExerciseNames` ×1 + `getPrSummary('스쿼트')` ×2 | 동일 ×3 |
| 칩 데이터 화면 표시 | 0 | 0 |
| **화면 닫음** | — (Provider 모두 살아있음) | **dispose 트리거 (30초 후 prSummary 도)** |
| 다른 탭에서 세트 추가 | `exerciseRecordsProvider` invalidate → **topExerciseNames + prSummary 자동 재실행 = 추가 ×3** | **0** (Provider 가 이미 dispose) |
| 1RM 코치 재진입 (30초 이내) | 캐시 히트 = 0 | `keepAlive` 효과로 0 (단, topExerciseNames 는 autoDispose 라 ×1 발생) |
| 1RM 코치 재진입 (30초 이후) | 캐시 히트 = 0 (단 백그라운드 재계산 결과 사용) | 새 쿼리 ×3 |

**총 쿼리 수 (30초 이후 재진입 기준)**:
- Before: 3 (진입) + 3 (백그라운드) + 0 (재진입, 캐시) = **6**
- After: 3 (진입) + 0 (닫힘 후 백그라운드 X) + 3 (재진입, 새 계산) = **6**

→ **총 쿼리 수는 동일**, 하지만 **언제 비용이 발생하는지가 다름**.
- Before: 사용자가 다른 작업 중인데 백그라운드 쿼리 발생 (UI 끊김 위험)
- After: 사용자가 명시적으로 화면 진입할 때만 쿼리 (예측 가능한 비용)

### 시나리오 B: 1RM 코치에서 칩으로 종목 A → B → A 전환 (각 5초 간격)

| 단계 | Before | After (keepAlive 없으면) | After (keepAlive 30초) |
|------|--------|--------------------------|------------------------|
| 진입 (A 자동 선택) | `prSummary(A)` ×2 | 동일 ×2 | 동일 ×2 |
| A → B 전환 (5초 후) | `prSummary(B)` ×2. A 는 메모리 유지 | `prSummary(A)` dispose, `prSummary(B)` ×2 | `prSummary(B)` ×2. A 는 keepAlive |
| B → A 전환 (10초 후) | A 캐시 히트 = 0 | `prSummary(A)` ×2 (재쿼리) | A 캐시 히트 = 0 |

**칩 빈번 전환 시**:
- Before: 매번 새 종목만 쿼리. **최적**.
- After (keepAlive 없으면): A → B → A 시 A 쿼리 2번. **회귀**.
- After (keepAlive 30초): A → B → A 시 A 쿼리 1번. **Before 와 동일**. ✓

→ **`keepAlive` 30 초 윈도우는 회귀 방지에 필수.**

### 시나리오 C: 1RM 코치 진입 → 30분 백그라운드 → 다시 보기

| 단계 | Before | After |
|------|--------|-------|
| 진입 | `prSummary(A)` ×2 | ×2 |
| 30분 백그라운드 동안 다른 탭에서 세트 10개 추가 | **invalidate 마다 ×2 = ×20** | **0** (dispose 됨) |
| 다시 보기 | 캐시 히트 = 0 | 새 쿼리 ×2 |

**총 쿼리**:
- Before: 2 + 20 + 0 = **22**
- After: 2 + 0 + 2 = **4**

→ **백그라운드 시간이 길수록 After 가 압도적으로 유리**.

### 시나리오 D: 요약 탭 RecentPrCard

| 단계 | Before | After |
|------|--------|-------|
| 요약 탭 첫 진입 | `topPrs` ×~31 (15 names + 15×2 summaries + 1) | 동일 ~31 |
| 다른 탭으로 이동 | RecentPrCard widget 살아있음 (BottomNavShell) | 동일 |
| 운동 탭에서 세트 추가 | invalidate → ~31 백그라운드 재계산 | RecentPrCard 가 여전히 watch 하므로 **autoDispose 효과 X = 동일 ~31** |

→ 본 PR 만으로는 RecentPrCard 의 백그라운드 재계산 문제 해결 안 됨. **#2 N+1 PR 에서 병렬화/풀 축소로 비용 자체를 낮추는 것이 본질적 해결**.

---

## 6. 잠재 부작용 / 회귀 가능성

| 부작용 | 가능성 | 완화 방법 |
|--------|--------|-----------|
| 칩 빠른 전환 시 깜빡임 (재쿼리) | 중간 | `keepAlive` 30초 ✓ |
| 화면 재진입 시 로딩 인디케이터 표시 | 낮음 (쿼리 < 50ms 일 가능성 높음) | `previous.maybeWhen(data: ...)` 로 이전 데이터 유지 가능 (이번 PR 범위 밖) |
| Timer 누수 | 매우 낮음 | `ref.onDispose(timer.cancel)` ✓ |
| `topPrsProvider` 가 호출하는 `prSummaryProvider(family.autoDispose)` 의 lifecycle 충돌 | 낮음 | `topPrsProvider` 자체가 ref.read 가 아닌 `repo.getTopPrs()` 를 직접 호출하므로 family 와 무관. 영향 없음 ✓ |

---

## 7. 영향받는 파일 (이번 PR 범위)

### 수정 (1개 파일, ~20 줄)
| 파일 | 변경 |
|------|------|
| [lib/features/exercise/presentation/providers/one_rm_coach_provider.dart](../lib/features/exercise/presentation/providers/one_rm_coach_provider.dart) | 4 Provider 의 변형 변경 + `prSummaryProvider` 에 `keepAlive` Timer + `dart:async` import |

### 신규 (0개)

### 영향받지 않음
- UI 위젯 코드 변경 없음 (`ref.watch(prSummaryProvider(name))` 호출 패턴 동일)
- Repository 코드 변경 없음
- DB 스키마 변경 없음
- 테스트 코드 변경 없음 (단, 새 테스트는 #3 PR 에서)

---

## 8. 예상 diff 전체 (참고용)

```diff
+import 'dart:async';
 import 'package:flutter/foundation.dart' show debugPrint;
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:shared_preferences/shared_preferences.dart';
 // ...

 final prRepositoryProvider = Provider<PrRepository>((ref) {
   return SqlitePrRepository();
 });

-final topExerciseNamesProvider = FutureProvider<List<String>>((ref) async {
+/// **lifecycle**: autoDispose — 1RM 코치 화면 닫히면 dispose.
+final topExerciseNamesProvider =
+    FutureProvider.autoDispose<List<String>>((ref) async {
   ref.watch(exerciseRecordsProvider);
   final repo = ref.watch(prRepositoryProvider);
   return repo.getTopExerciseNames();
 });

 final selectedCoachExerciseProvider = StateProvider<String?>((ref) => null);
 final coachInputWeightProvider = StateProvider<double>((ref) => 80.0);
 final coachInputRepsProvider = StateProvider<int>((ref) => 5);

-final prSummaryProvider =
-    FutureProvider.family<PrSummary, String>((ref, exerciseName) async {
+/// **lifecycle**: family.autoDispose + keepAlive 30 초 윈도우.
+/// 칩 A→B→A 빠른 전환 시 캐시 히트 (회귀 방지).
+final prSummaryProvider = FutureProvider.family
+    .autoDispose<PrSummary, String>((ref, exerciseName) async {
+  final link = ref.keepAlive();
+  final timer = Timer(const Duration(seconds: 30), link.close);
+  ref.onDispose(timer.cancel);
+
   ref.watch(exerciseRecordsProvider);
   final repo = ref.watch(prRepositoryProvider);
   return repo.getPrSummary(exerciseName);
 });

-final topPrsProvider = FutureProvider<List<PrSummary>>((ref) async {
+/// **lifecycle**: autoDispose — BottomNavShell 정책 변경 대비.
+final topPrsProvider =
+    FutureProvider.autoDispose<List<PrSummary>>((ref) async {
   ref.watch(exerciseRecordsProvider);
   final repo = ref.watch(prRepositoryProvider);
   return repo.getTopPrs();
 });

-final oneRmCoachNoteProvider =
-    FutureProvider.family<String, CoachNoteRequest>((ref, req) async {
+/// **lifecycle**: family.autoDispose.
+/// 종목/신호등 변경 시 dispose. SharedPreferences 캐시는 영속.
+final oneRmCoachNoteProvider = FutureProvider.family
+    .autoDispose<String, CoachNoteRequest>((ref, req) async {
   final prefs = await SharedPreferences.getInstance();
   // ... 이하 동일
```

---

## 9. 검증 방법

### 9-1. 정적 분석
```bash
flutter analyze lib/features/exercise/presentation/providers/one_rm_coach_provider.dart
```
기대: 0 issues. `Timer` 사용으로 인한 `dart:async` import 누락이 가장 흔한 실수.

### 9-2. 단위 테스트
- 본 PR 자체에는 새 테스트 없음 (Provider lifecycle 은 통합 동작이라 단위 테스트로 검증 어려움).
- 기존 테스트 (`test/core/training/`) 통과 확인:
  ```bash
  flutter test test/core/training/
  ```

### 9-3. 수동 검증 시나리오 (UI)

**A. 화면 닫고 운동 기록 추가 → 재진입 (시나리오 A 검증)**
1. 1RM 코치 진입 → 스쿼트 e1RM 표시 확인
2. 닫기 (X 버튼)
3. 운동 탭에서 스쿼트 100kg×3 새 세트 추가
4. **30초 이상 대기** (keepAlive 윈도우 종료)
5. 1RM 코치 재진입 → e1RM 이 새 세트 반영해 갱신되었는지 확인 (스쿼트 100×3 → e1RM 110)

**B. 칩 빠른 전환 (시나리오 B 검증)**
1. 1RM 코치 진입 → 스쿼트 선택 → 데이터 표시
2. 벤치프레스 칩 탭 → 데이터 표시
3. **즉시** 스쿼트 칩 다시 탭 → **로딩 인디케이터 없이 즉시 데이터 표시 (keepAlive 캐시)** 확인
4. 30초 후 스쿼트 → 벤치 → 스쿼트 → **이번엔 로딩 인디케이터 잠깐 보일 수 있음** (윈도우 종료)

**C. 백그라운드 시간 길어도 메모리 안정 (시나리오 C 검증)**
1. 1RM 코치 진입 후 닫기
2. 다른 탭에서 운동 세트를 5~10개 빠르게 추가
3. (개발자) Flutter DevTools 의 Memory 탭에서 PrSummary 인스턴스가 누적되지 않는지 확인 — Before 에서는 누적, After 에서는 0

**D. CoachNoteCard 캐시 (시나리오 D 검증)**
1. 1RM 코치 → 스쿼트 진입 → Gemini 코치 노트 생성 후 표시
2. 닫기 → 30초 대기 → 재진입
3. 같은 신호등 유지 시 **Gemini API 호출 없이 즉시 표시** (SharedPreferences 캐시 히트)
4. (검증 방법) Network 인스펙터 또는 GeminiService 로그로 호출 0 회 확인

### 9-4. 빌드 검증
```bash
flutter build ios --no-codesign --debug
```

---

## 10. 작업 순서

1. `lib/features/exercise/presentation/providers/one_rm_coach_provider.dart` 편집
   - `dart:async` import 추가
   - 4 Provider 변형 변경
   - `prSummaryProvider` 에 `keepAlive` + Timer 블록 삽입
   - 각 Provider 위에 lifecycle 주석 보강
2. `flutter analyze` (해당 파일만)
3. `flutter test test/core/training/`
4. `flutter build ios --no-codesign --debug`
5. 수동 검증 (§9-3 A~D)
6. [docs/domains.md](../docs/domains.md) 의 exercise 도메인 Provider 매핑에 lifecycle 주석 추가:
   - `prSummaryProvider*` (autoDispose + 30s keepAlive)
   - 다른 3개도 `*` (autoDispose) 표시
7. 본 plan 파일 §11 의 "완료 후 측정값" 채우기 (수동 측정)
8. PR 생성

---

## 11. 완료 후 측정값 (PR 작성 시 채울 것)

| 메트릭 | Before (current main) | After (이 PR) |
|--------|------------------------|---------------|
| 시나리오 A 30분 백그라운드 동안 DB 쿼리 횟수 | _측정 필요_ | _측정 필요_ |
| 시나리오 B 칩 A→B→A (10초 내) 쿼리 횟수 | 0 (캐시) | 0 (keepAlive) |
| 시나리오 B 칩 A→B→A (1분 후) 쿼리 횟수 | 0 (캐시) | 2 (재쿼리) |
| `_Body` build 호출 횟수 (60초간 다른 탭 작업) | _측정 필요_ | _측정 필요_ |

측정 도구: `debugPrint` 임시 삽입 또는 `flutter logs` 의 sqflite 로그.

---

## 12. 보류/후속 결정사항

- **`previous.maybeWhen(data: ...)` 패턴으로 재진입 시 이전 데이터 즉시 표시 (깜빡임 방지)**
  - 이번 PR 에 포함하면 UI 코드 (`_Body`) 까지 손대야 함 → scope 확장.
  - 별도 마이크로 PR 로 분리 검토.
- **`keepAlive` 윈도우를 30초로 정한 근거가 휴리스틱**
  - 사용자 행동 패턴 데이터 없음. 5분 이상으로 늘리면 메모리 누수에 가까워지고, 10초 미만이면 칩 전환 회귀 위험.
  - 30초가 안전한 중간값. 사용 후 조정 가능.
- **`exerciseRecordsProvider` 자체의 autoDispose 화** — scope 밖. 메인 데이터 소스라 영구 유지가 합리.

---

## 13. 다른 후속 PR 와의 관계

| PR | 관계 |
|----|------|
| #2 종목별 입력값 자동 초기화 + 칩 자동 스크롤 | **이 PR 위에 쌓임**. `selectedCoachExerciseProvider` listen → 입력 weight/reps 갱신 로직 추가. autoDispose 영향 없음 (StateProvider 는 변경 안 함). |
| #3 PrRepository 단위 테스트 | **독립**. 본 PR 과 충돌 없음. 어느 순서로 머지해도 OK. |
| (메인 PR 의 #2 N+1 fix) | **별개 단발 fix 로 권장**. autoDispose 와 결합 시 시나리오 D 의 비용도 함께 줄어 누적 효과. |
