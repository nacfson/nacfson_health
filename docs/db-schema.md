# DB 스키마 (SQLite)

> **현재 버전**: v12  
> **DB 파일명**: `nacfson_health.db`  
> **마지막 업데이트**: 2026-04-29

---

## 버전 이력

| 버전 | 변경 내용 | 비고 |
|------|----------|------|
| v1 | `exercise_records` | 초기 출시 |
| v2 | `diet_records` | 식단 기록 추가 |
| v3 | `exercise_templates` | 운동 종목 프리셋 |
| v4 | `food_templates` | 음식 프리셋 (2026-04) |
| v5 | `weight_records` 신규 + `exercise_templates.exercise_type` 컬럼 추가 | 체중 기록 + 운동 부위 분류 (2026-04) |
| v6 | `exercise_type=''` 인 잔여 템플릿 삭제 | v5 마이그레이션 기본값 정리 (2026-04) |
| v7 | `user_profiles` 신규 + Google Sheets 동기화 제거(Supabase 전환) | 온보딩/AI 인사이트 (2026-04) |
| v8 | `workout_routines`(루틴 프리셋) + `daily_routine`(오늘 루틴) 신규 | 루틴 플래너 + 인라인 세트 입력 (2026-04) |
| v9 | `exercise_records.set_type` 컬럼 추가 (`warmup`/`work`/`drop`/`failure`) | 세트 타입 구분 + 본세트 기준 볼륨 집계 (2026-04) |
| v10 | `user_profiles` 에 `age` / `activity_level` / `training_intensity` 컬럼 추가 + `age_group` NOT NULL 해제 | 만 나이 직접 입력, 활동계수 5단계, 운동 강도 4단계 (2026-04) |
| v11 | `exercise_templates.rest_seconds_override INTEGER` 컬럼 추가 | 종목별 휴식 시간 오버라이드. NULL=부위 기본값 (2026-04) |
| v12 | 다국어 master 운동 데이터 5 테이블 신규 + `exercise_records`/`exercise_templates` 에 `exercise_key`/`category_key` 추가 + 한글명 자동 매핑 | NSCA 검증 종목별 1RM 공식 + ko/en 번역 + admin-curated 마스터 (2026-04-29) |

### v12 마이그레이션 (다국어 + 종목별 1RM 공식)

**상세는 `docs/changelog-v12.md` 참조.** 핵심 SQL:

```sql
-- 1) admin-curated master 5 테이블 신규
CREATE TABLE exercise_categories (category_key TEXT PRIMARY KEY, display_order INTEGER, updated_at INTEGER);
CREATE TABLE exercise_category_translations (category_key TEXT, locale TEXT, display_name TEXT, updated_at INTEGER, PRIMARY KEY (category_key, locale));
CREATE TABLE exercise_definitions (exercise_key TEXT PRIMARY KEY, category_key TEXT, is_compound INTEGER, default_name TEXT, updated_at INTEGER);
CREATE TABLE exercise_translations (exercise_key TEXT, locale TEXT, display_name TEXT, aliases TEXT, updated_at INTEGER, PRIMARY KEY (exercise_key, locale));
CREATE TABLE one_rm_formulas (exercise_key TEXT PRIMARY KEY, formula_type TEXT, coefficients TEXT, source TEXT, optimal_rep_max INTEGER, notice_translations TEXT, updated_at INTEGER);

-- 2) 기존 user-owned 테이블에 exercise_key/category_key 추가
ALTER TABLE exercise_records ADD COLUMN exercise_key TEXT;
ALTER TABLE exercise_records ADD COLUMN category_key TEXT;
ALTER TABLE exercise_templates ADD COLUMN exercise_key TEXT;
ALTER TABLE exercise_templates ADD COLUMN category_key TEXT;

-- 3) 한글명 → exercise_key 자동 매핑 (M1 — Eager, lib/features/exercise/data/legacy_korean_mapping.dart 의 52개 default 매핑)
-- 4) workout_routines/daily_routine items_json 안의 한글명에 exerciseKey 백필 (Dart 트랜잭션)
```

**TTL 24h pull-only 캐시**: 1RM 코치 진입 시 `SqliteMasterDataRepository.ensureFresh()` 호출 → SharedPreferences `master_data_last_fetched_at` 체크 → 24h 이상 경과 시 5 테이블 병렬 fetch + SQLite 전체 replace. 일반 sync 사이클(`sync_state.dart`)과 분리.

**Supabase 마이그레이션**: `supabase/migrations/20260429_0001_master_exercise_data_v12.sql` — 161개 종목 + 322개 번역 + 24개 1RM 공식 시드 포함. RLS: 인증 사용자 read-only, write 정책 미부여(Studio 직접 수정만).

### v11 마이그레이션 (`exercise_templates.rest_seconds_override`)

```sql
ALTER TABLE exercise_templates ADD COLUMN rest_seconds_override INTEGER;
```

- 종목별 휴식 시간 오버라이드(초). `NULL` 이면 클라이언트에서 부위 기본값을 해석한다.
- 유효 입력 범위: 60~300 (`kMinRestSeconds`/`kMaxRestSeconds` in `lib/features/exercise/domain/body_part_rest_defaults.dart`).
- 기존 템플릿은 NULL 상태로 시작 — 자연스럽게 부위 기본값으로 동작.
- Supabase 원격 DB: `supabase/migrations/20260424_0002_exercise_templates_rest_override.sql` 로 동일 컬럼 추가. 클라이언트 v11 배포 **이전** 서버 마이그레이션 먼저 적용.
- 부위별 기본값(근비대 기준, 코드 상수): 하체 180s · 등 150s · 가슴 120s · 어깨 90s · 팔 60s · 코어 60s · 기타 90s · 유산소 `null`(타이머 미사용).
- 전역 `default_rest_seconds` SharedPreferences 키는 v11 이후 참조되지 않음 (레거시 키 자연 소멸).

### v10 마이그레이션 (`user_profiles` 프로필 정교화)

```sql
ALTER TABLE user_profiles ADD COLUMN age INTEGER NOT NULL DEFAULT 30;
ALTER TABLE user_profiles ADD COLUMN activity_level TEXT NOT NULL DEFAULT 'moderate';
ALTER TABLE user_profiles ADD COLUMN training_intensity TEXT NOT NULL DEFAULT 'moderate';
-- age_group 중앙값으로 age 백필 (20s=25/30s=35/40s=45/50s+=55)
UPDATE user_profiles SET age = 25 WHERE age_group = '20s'  AND age = 30;
UPDATE user_profiles SET age = 35 WHERE age_group = '30s'  AND age = 30;
UPDATE user_profiles SET age = 45 WHERE age_group = '40s'  AND age = 30;
UPDATE user_profiles SET age = 55 WHERE age_group = '50s+' AND age = 30;
-- 레거시 goal 정리
UPDATE user_profiles SET goal = 'lean_gain' WHERE goal = 'lean_mass';
```

- `age_group` 컬럼은 SQLite `DROP COLUMN` 회피를 위해 남겨두고 `NULL` 허용으로 변경 (deprecated — 신규 코드 참조 금지).
- Supabase 원격 DB 는 `supabase/migrations/20260424_0001_user_profiles_age_activity_intensity.sql` 로 동일 변경. `CREATE EXTENSION IF NOT EXISTS moddatetime` 트리거와는 별도.
- SharedPreferences 마이그레이션(`SyncPreferences.migrateLegacyProfile()`): `user_age_group` → `user_age`, `fitness_goal='lean_mass'` → `'lean_gain'` 으로 1회 재작성. `lib/main.dart` 진입 시 자동 호출.

### v9 마이그레이션 (`exercise_records.set_type`)

```sql
ALTER TABLE exercise_records ADD COLUMN set_type TEXT NOT NULL DEFAULT 'work'
```

- 기존 모든 레코드는 DEFAULT로 `'work'` 자동 부여.
- Supabase 원격 테이블에도 동일 컬럼을 대시보드에서 수동 ALTER 필요 (`docs/changelog-v7.md` 의 Supabase 운영 항목 참고).
- 엔티티: `ExerciseRecord.setType: SetType` (enum: `warmup`/`work`/`drop`/`failure`, 기본 `work`).
- 집계 규칙: `countsTowardVolume` getter → `work` + `drop` 만 True (웜업/실패 제외).

---

## 마이그레이션 규칙

- `DatabaseHelper.onUpgrade()`에서 `oldVersion < N` 분기로 누적 처리
- `CREATE TABLE IF NOT EXISTS` 사용 (멱등성 보장)
- 마이그레이션 후 `SyncPreferences.lastSyncTimestamp = 0` 초기화 → 강제 풀 싱크로 LWW 충돌 해결

---

## 테이블 스키마

### 1. `exercise_records`

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `timestamp` | INTEGER | 기록 시각 (ms since epoch) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | SyncStatus 값 (아래 참조) |
| `exercise_type` | TEXT | 부위 (가슴/등/팔/하체/어깨/코어) |
| `exercise_name` | TEXT | 종목명 |
| `current_set` | INTEGER | 세트 번호 |
| `weight` | REAL | 사용 중량 (kg) |
| `reps` | INTEGER | 반복 횟수 |
| `rpe` | REAL | 자각강도 (1~10) |
| `set_type` | TEXT | 세트 타입 (`warmup`/`work`/`drop`/`failure`, DEFAULT `work`) — v9 |

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update · Delete (전체 CRUD)
**볼륨 집계**: `set_type IN ('work', 'drop')` 만 합산 (웜업/실패 제외) — `ExerciseRecord.countsTowardVolume`

---

### 2. `diet_records`

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `timestamp` | INTEGER | 기록 시각 (ms since epoch) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | SyncStatus 값 |
| `meal_type` | TEXT | 식사 유형 (아침/점심/저녁/간식) |
| `food_name` | TEXT | 음식명 |
| `total_calories` | INTEGER | 총 칼로리 (kcal) |
| `carbs` | REAL | 탄수화물 (g) |
| `protein` | REAL | 단백질 (g) |
| `fat` | REAL | 지방 (g) |
| `satisfaction` | INTEGER | 만족도 (1~5) |
| `memo` | TEXT? | 메모 (nullable) |

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update · Delete (전체 CRUD)

---

### 3. `exercise_templates`

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `name` | TEXT UNIQUE | 종목명 |
| `exercise_type` | TEXT | 부위 (가슴/등/팔/하체/어깨/코어/유산소/기타) — v5 추가, default `''` |
| `rest_seconds_override` | INTEGER NULL | 종목별 휴식 시간 오버라이드 (60~300s). NULL 이면 부위 기본값 사용 — v11 추가 |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | TemplateSyncStatus 값 |

**TemplateSyncStatus**: `synced(0)` / `created(1)` / `deleted(3)` — `modified(2)` **미사용**  
**지원 연산**: Create · Delete · 휴식 override 수정(v11 — `sync_status=created` 로 재마킹, Supabase upsert 로 전파)  
**Pull 병합 전략**: insert-or-skip (uuid 기준, LWW 불필요). 클라이언트 측 override 변경은 push 전용 — 원격에서 덮어써도 로컬은 건드리지 않음.  
**v6 정리**: `exercise_type=''`인 행은 마이그레이션 시 일괄 삭제됨

---

### 4. `food_templates` _(v4 신규)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `name` | TEXT UNIQUE | 음식명 |
| `calories` | INTEGER | 칼로리 (kcal) |
| `carbs` | REAL | 탄수화물 (g) |
| `protein` | REAL | 단백질 (g) |
| `fat` | REAL | 지방 (g) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | FoodTemplateSyncStatus 값 |

**FoodTemplateSyncStatus**: `synced(0)` / `created(1)` / `deleted(3)` — `modified(2)` **미사용**  
**지원 연산**: Create · Delete (수정 없음)  
**Pull 병합 전략**: insert-or-skip (uuid 기준, LWW 불필요)  
**칼로리 처리**: 탄단지 자동계산 아님 — 템플릿에 직접 저장

---

### 5. `weight_records` _(v5 신규)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `timestamp` | INTEGER | 기록 시각 (ms since epoch) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | SyncStatus 값 |
| `weight` | REAL | 체중 (kg) |

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update · Delete (전체 CRUD)

---

### 6. `user_profiles` _(v7 신규, v10 확장)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `gender` | TEXT | 성별 (`male`/`female`) |
| `age_group` | TEXT (nullable) | _deprecated (v10)_ — `age` 컬럼으로 이관 |
| `age` | INTEGER | 만 나이 (기본 30). BMR 계산에 직접 사용 |
| `height` | REAL | 키 (m) |
| `goal` | TEXT | 목표 (`diet` / `lean_cut` / `lean_gain` / `bulk_up`) |
| `activity_level` | TEXT | 활동 수준 (`sedentary` / `light` / `moderate` / `active` / `very_active`) — TDEE 배수 결정 |
| `training_intensity` | TEXT | 운동 강도 (`low` / `moderate` / `high` / `very_high`) — 단백질 g/kg 결정 |
| `target_calories` | INTEGER | 일일 목표 칼로리 (kcal) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | SyncStatus 값 |

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update (Delete 비공개 — 1인 1프로필)  
**연관 모듈**: `lib/features/onboarding/`, `lib/core/ai/health_insight_provider.dart` (BMI 계산용 height 참조)  
**참고**: 키(height) 영구 저장은 SharedPreferences `user_height_m`(meter)와 이중화 — 빠른 접근/오프라인 우선

---

### 7. `workout_routines` _(v8 신규)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (서버 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `name` | TEXT | 루틴명 (예: "가슴 & 삼두") |
| `items_json` | TEXT | `[{"type":"가슴","name":"벤치 프레스"}, ...]` 직렬화 |
| `created_at` | INTEGER | 생성 시각 (ms since epoch) |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | `SyncStatus` 값 (0/1/2/3) |

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update · Delete  
**Pull 병합 전략**: LWW (`updated_at` 기준)  
**비고**: 자주 사용하는 운동 조합 프리셋. 오늘 루틴 구성 후 "루틴으로 저장"으로 이름 붙여 보관.

---

### 8. `daily_routine` _(v8 신규, 로컬 전용)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 |
| `date` | TEXT UNIQUE | `YYYY-MM-DD` (로컬 자정 기준) |
| `items_json` | TEXT | 해당 일자에 계획된 운동 항목 직렬화 |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |

**동기화 미적용** — 로컬 전용. 오늘 운동 카드의 컨테이너 역할 (v9+).  
**지원 연산**: Upsert (1일 1행) · Read · Delete  
**비고**:
- 카드만 얹은(세트 0인) 상태에서 앱을 닫아도 `exercise_records` 는 변함없다. 실제 세트가 입력될 때만 `exercise_records` insert.
- v9+ 규칙: 세트 저장 시 `InlineSetInput._submit` 이 `RoutinePlannerNotifier.addItem` 을 자동 호출하여 루틴에 편입시킨다. 앱 로드 시 `RoutinePlannerNotifier._load` 의 자기치유 로직이 "기록은 있으나 루틴에 없는" 운동을 자동 편입(기존 데이터 보정).
- "운동 제거" 메뉴(`ExerciseGroupCard`)는 `daily_routine` 항목과 함께 선택 날짜의 `exercise_records` 를 `deleteByExerciseNameOnDate` 로 일괄 soft delete 한다.

---

## Google Sheets 대응 시트

| DB 테이블 | Sheets 탭 | 헤더 범위 |
|----------|-----------|---------|
| `exercise_records` | `exercise_records` | A1:I1 |
| `diet_records` | `diet_records` | A1:K1 |
| `exercise_templates` | `exercise_templates` | A1:D1 (uuid/name/exerciseType/updatedAt) |
| `food_templates` | `food_templates` | A1:G1 |
| `weight_records` | `weight_records` | A1:D1 (uuid/timestamp/updatedAt/weight) |
| `user_profiles` | _시트 동기화 미적용_ | 로컬 전용 (v7 시점) |
| `workout_routines` | `workout_routines` | uuid/name/items_json/created_at/updated_at/is_deleted (Supabase, v8) |
| `daily_routine` | _시트 동기화 미적용_ | 로컬 전용 (v8) — 오늘 루틴 계획 |

> Supabase 측 `workout_routines` 테이블은 별도 SQL 마이그레이션으로 사전에 생성되어야 한다 (`uuid TEXT PK`, `user_id UUID`, `name TEXT`, `items_json JSONB`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ`, `is_deleted BOOLEAN`). 테이블이 없으면 동기화 사이클 중 해당 단계만 오류로 기록되고 다른 동기화는 정상 진행된다.

> **동기화 메타데이터** (spreadsheetId, lastSyncTime, 영양 목표값 등)는 `SharedPreferences`에 저장 — DB 외부.

---

## Supabase 서버 스키마 관리

- Supabase 쪽 스키마·인덱스·트리거는 `supabase/migrations/` 하위에 SQL 파일로 버전 관리한다.
- 새 sync 대상 테이블을 추가할 때는 반드시 `set_updated_at` 트리거(`extensions.moddatetime(updated_at)`)를 함께 만든다.
  - 이 트리거가 없으면 외부 SQL 경로(Supabase Studio, 관리 스크립트, Edge Function 등)로 UPDATE 된 row 가 delta pull(`updated_at > lastSync`)에 걸리지 않아 다른 기기로 변경이 전파되지 않는 silent drift 가 발생한다.
  - delta pull 은 `lib/core/sync/base_supabase_sync_service.dart` 의 `readDelta` 가 담당.
- `updated_at` 컬럼은 `TIMESTAMPTZ` 타입이어야 `extensions.moddatetime` 이 동작한다. 새 테이블을 설계할 때 타입 정합을 확인할 것.
- 현재 sync 대상 테이블: `exercise_records`, `diet_records`, `weight_records`, `exercise_templates`, `food_templates`, `workout_routines`.
- 트리거 적용 확인 쿼리:
  ```sql
  SELECT event_object_table, trigger_name, action_statement
  FROM information_schema.triggers
  WHERE event_object_schema = 'public'
    AND event_manipulation = 'UPDATE'
  ORDER BY event_object_table;
  ```
- 스키마 변경 후에는 이 문서의 테이블 섹션도 함께 갱신한다.

### 마이그레이션 작성·적용 작업 체크리스트 (반드시 준수)

**SQL 파일 작성과 원격 DB 적용은 동일 작업 단위에서 함께 완료한다.** 작성만 하고 push 를 미루면 다음 클라이언트 배포에서 컬럼/트리거 누락으로 PGRST204 / silent drift 가 발생한다 (실사례: v11 `rest_seconds_override` — [docs/changelog-v11.md](changelog-v11.md) "사고 회고" 참조).

1. **SQL 작성** — `supabase/migrations/YYYYMMDD_NNNN_<snake_case>.sql`. 모든 DDL 은 idempotent (`ADD COLUMN IF NOT EXISTS`, `CREATE EXTENSION IF NOT EXISTS`, `DROP TRIGGER IF EXISTS` 후 CREATE) 로 작성.
2. **원격 적용** — 작성과 동시에 둘 중 하나로 push:
   - Supabase MCP `apply_migration` (write 모드일 때).
   - Supabase Studio → SQL Editor → 파일 내용 붙여넣고 Run.
3. **적용 검증** — `mcp__supabase__execute_sql` 또는 Studio 에서 `information_schema.columns` / `information_schema.triggers` 조회로 변경이 실제 반영됐는지 확인. `mcp__supabase__list_migrations` 또는 `supabase_migrations.schema_migrations` 가 비어 있으면 push 가 안 된 것.
4. **문서 동기화** — [CLAUDE.md](../CLAUDE.md) 의 "DB 버전" 라인, 본 문서의 "버전 이력" 표 + 마이그레이션 SQL 섹션, [docs/features.md](features.md) 체크박스, `docs/changelog-vN.md` 신규 작성. CLAUDE.md "참조 문서 목록" 표에도 새 changelog 등록.
5. **문제 발생 시** — 본 섹션과 관련 changelog 에 사고 회고 + 재발 방지 하네스 프롬프트를 즉시 추가 (CLAUDE.md "실수 발생 시" 규칙).

**금지**: 마이그레이션 SQL 파일 작성 후 원격 push 없이 클라이언트 코드 (DB 버전 증가, 새 컬럼 read/write) 를 배포하는 것.

---

## 공통 규칙

- **UUID 자동 생성**: `uuid: ''` (빈 문자열) 전달 시 SQLite 구현체에서 UUID v4 자동 할당
- **컬럼 네이밍**: DB는 `snake_case`, Dart Entity는 `camelCase` — Repository에서 매핑
- **`id` 컬럼**: 로컬 전용, Google Sheets 연동 시 절대 사용 금지 (uuid 사용)
