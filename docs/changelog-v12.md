# v12 Changelog — 다국어 지원 + 종목별 권위 1RM 공식

**날짜**: 2026-04-29
**범위**: DB v11 → v12, Supabase migration, 1RM 코치 정확도 개편

---

## 배경

### 1RM 정확도 문제

기존(v11까지) 1RM 코치는 모든 종목에 단일 **Epley 공식** (`weight × (1 + reps/30)`, 1985년) 을 적용했다. NSCA 검증 연구 — **LeSuer et al. 1997**, *J. Strength Cond. Res.* 11(4):211-213, "The Accuracy of Prediction Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift" — 결과:

| 종목 | 가장 정확한 공식 | 비고 |
|------|----------------|------|
| **벤치프레스** | **Mayhew 1992** | 평균 오차 -0.5% |
| **스쿼트** | **Wathen 1994** / Brzycki | 5RM에서 ±2.7~3.1kg 범위 |
| **데드리프트** | **Wathen 1994** | 모든 공식이 과소평가하지만 가장 가까움 |

→ Epley 단일 적용은 종목 특성을 무시한 단순화. 종목별로 검증된 공식 적용 시 추정 정확도 향상.

### 다국어 지원 필요

기존 운동 데이터는 한글 free-form 문자열(`exercise_records.exercise_name = "벤치프레스"`)로 저장. 영어/일본어 사용자 진입 시 동일 종목 매칭 불가능. 향후 글로벌 출시 대비 언어 독립적 식별자(`exercise_key`) 도입.

---

## DB 변경 (v11 → v12)

### Supabase 신규 테이블 (5개, admin-curated, read-all/write-admin)

| 테이블 | 책임 | 시드 |
|--------|------|------|
| `exercise_categories` | 카테고리 마스터 (chest/back/legs/shoulders/biceps/triceps/forearms/core/glutes/calves/olympic) | 11행 |
| `exercise_category_translations` | 카테고리 ko/en 표시명 | 22행 |
| `exercise_definitions` | 운동 정의 (exercise_key PK, category_key FK, is_compound) | **161행** (전 표준 웨이트 종목) |
| `exercise_translations` | 운동 ko/en 표시명 + 검색 별칭 | **322행** |
| `one_rm_formulas` | 종목별 1RM 공식 (formula_type + JSONB coefficients + source + notice_translations) | **24행** (NSCA 검증 종목) |

### SQLite v11→v12 마이그레이션

- 위 5 테이블 신규 생성 (admin-curated 로컬 캐시)
- `exercise_records` 에 `exercise_key TEXT`, `category_key TEXT` 컬럼 추가
- `exercise_templates` 에 `exercise_key TEXT`, `category_key TEXT` 컬럼 추가
- 기존 한글명 → exercise_key 자동 매핑 (M1 — Eager, 52개 default 종목)
- `workout_routines.items_json` / `daily_routine.items_json` 안의 한글명에 `exerciseKey` 필드 백필 (Dart 트랜잭션)
- `exercise_records.exercise_name` / `exercise_templates.name` 컬럼은 **보존** (historical snapshot)

### 1RM 공식 type 시스템

`formula_type` + `coefficients` JSONB 로 4가지 형태 표현:

| type | 수식 | coefficients | 표준 매핑 |
|------|------|--------------|----------|
| `epley` | `W × (1 + k×R)` | `{"k":0.0333}` | Epley(k=1/30), O'Conner(k=0.025) |
| `linear` | `W / (a − b×R)` | `{"a":1.0278,"b":0.0278}` | Brzycki, Lander |
| `exponential` | `(a×W) / (b + c·exp(k×R))` | `{"a":100,"b":52.2,"c":41.9,"k":-0.055}` | **Mayhew**(상체), **Wathen**(하체) |
| `polynomial` | `W × R^p` | `{"p":0.10}` | Lombardi |

알려진 7개 학술 공식을 모두 표현 가능. Admin은 Supabase Studio에서 `coefficients` JSONB 직접 수정으로 공식 튜닝 가능.

### 초기 1RM 공식 시드 (24개 NSCA 검증 종목)

- **Mayhew**: bench_press, incline_bench_press, decline_bench_press, close_grip_bench_press, dumbbell_bench_press, overhead_press, military_press, push_press
- **Wathen**: squat, high_bar_squat, low_bar_squat, front_squat, hack_squat, leg_press, deadlift, sumo_deadlift, romanian_deadlift, trap_bar_deadlift, rack_pull
- **Brzycki**: barbell_row, pendlay_row, t_bar_row, pull_up, chin_up, lat_pulldown

미등록 종목(isolation 운동, 161개 중 137개)은 1RM 코치에 노출되지 않음. Admin이 Studio에서 INSERT로 추가 가능.

---

## Sync 전략

기존 `sync_state.dart` 의 push/pull 사이클과 **분리된 독립 fetch**:

```
사용자가 1RM 코치 진입
  └─> masterDataBundleProvider.read
      └─> SqliteMasterDataRepository.ensureFresh()
          last_fetched = SharedPrefs.getInt('master_data_last_fetched_at')
          if (now - last_fetched > 24h):
            try:
              parallel fetch 5 tables from Supabase
              SQLite 전체 replace (트랜잭션)
              SharedPrefs.setInt(now)
            catch (offline):
              # 기존 캐시 사용, last_fetched 갱신 안 함 → 재시도
          
          return Map<exerciseKey, ExerciseModel>
```

- TTL: **24시간** (한 사용자가 같은 기기에서 반복 진입해도 네트워크 호출 1회)
- 오프라인 안전: 첫 fetch 실패 시 캐시 사용, last_fetched 미갱신 → 재시도
- Admin 수정 반영: 최대 24h 지연 (사용자 합의 사항)

---

## UX 개편

| 화면 | 변경 |
|------|------|
| 1RM 코치 종목 칩 | Supabase 에 1RM 공식이 등록된 종목만 노출 (formulaSpecMap 필터). 미등록 종목은 칩 자체 비표시 |
| 1RM 코치 e1RM 계산 | 종목별 권위 공식 사용 (Mayhew/Wathen/Brzycki). 미등록 종목은 Epley fallback (점진적 호환) |
| % of 1RM 환산표 | `summary.currentE1RM` 기반으로만 표시. e1RM 데이터 없으면 안내 문구로 대체 |
| 1RM 코치 빠른 추정 카드 | **제거** — `currentE1RM` 이 이미 5주 max 로 산출되어 중복. `coachInputWeight/Reps/latestWorkSet/selectedExerciseFormula` Provider 도 함께 정리 |
| 운동 추가 다이얼로그 | 자유 텍스트 입력 차단 → `ExercisePickerField` 로 전환. `exercise_definitions` 에 등록된 종목만 선택 가능 + 부위(`exerciseType`) 자동 분류 |
| 운동 템플릿 추가 (설정) | `ExercisePickerField` 로 통합. 이름 자유 입력 + 부위 ChoiceChip 제거. 검색 결과 0 시 추가 탭으로 picker prefill |
| 카드 표시명 | (향후 v13에서 locale별 번역 표시 적용 예정) |

---

## 마이그레이션 사고 회고

해당 사항 없음 (v12는 신규 기능 + 비파괴 ALTER, 기존 데이터 손실 위험 없음).

**예방 조치**:
- 기존 `exercise_name` 컬럼 보존 → 마이그레이션 매핑 누락 시에도 이전 데이터 표시 가능
- 사용자 커스텀 종목(매핑 누락)은 `exercise_key=NULL` 상태로 1RM 미적용, 다른 모든 기능 정상

---

## 향후 (v13+)

- ja/zh-CN 등 추가 locale (Supabase에 admin이 INSERT)
- 기존 사용자 데이터 매핑 누락 정정 UX (exercise_key=NULL → 표준 종목 매핑 마법사)
- `RoutineItem` / `ExerciseTemplate` 에 `exerciseKey` 필드 정식 도입 (현재는 displayName 만 저장)
- 모든 화면의 운동명 표시를 `exerciseDisplayNameProvider` 로 일관 적용

---

## 참조

- 학술 출처: LeSuer DA, McCormick JH, Mayhew JL, Wasserstein RL, Arnold MD. "The Accuracy of Prediction Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift", *J. Strength Cond. Res.* 11(4):211-213, Nov. 1997.
- 마이그레이션 파일: `supabase/migrations/20260429_0001_master_exercise_data_v12.sql`
- 코드 진입점: `lib/core/training/one_rm_formula.dart`, `lib/features/exercise/data/repositories/sqlite_master_data_repository.dart`, `lib/features/exercise/presentation/providers/master_data_provider.dart`
