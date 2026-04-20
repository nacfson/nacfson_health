# DB 스키마 (SQLite)

> **현재 버전**: v8  
> **DB 파일명**: `nacfson_health.db`  
> **마지막 업데이트**: 2026-04

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
| v7 | `user_profiles` 신규 | 온보딩/AI 인사이트 사용자 정보 (2026-04) |
| v8 | `workout_routines`(루틴 프리셋) + `daily_routine`(오늘 루틴) 신규 | 루틴 플래너 + 인라인 세트 입력 (2026-04) |

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

**SyncStatus**: `synced(0)` / `created(1)` / `modified(2)` / `deleted(3)`  
**지원 연산**: Create · Read · Update · Delete (전체 CRUD)

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
| `exercise_type` | TEXT | 부위 (가슴/등/팔/하체/어깨/코어) — v5 추가, default `''` |
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | TemplateSyncStatus 값 |

**TemplateSyncStatus**: `synced(0)` / `created(1)` / `deleted(3)` — `modified(2)` **미사용**  
**지원 연산**: Create · Delete (수정 없음)  
**Pull 병합 전략**: insert-or-skip (uuid 기준, LWW 불필요)  
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

### 6. `user_profiles` _(v7 신규)_

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 로컬 자동증가 (시트 연동 금지) |
| `uuid` | TEXT UNIQUE | 글로벌 PK (UUID v4) |
| `gender` | TEXT | 성별 (male/female/etc) |
| `age_group` | TEXT | 연령대 (예: 20s, 30s) |
| `height` | REAL | 키 (m) |
| `goal` | TEXT | 목표 (lose/maintain/gain) |
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

**동기화 미적용** — 로컬 전용. 사용자가 오늘 어떤 운동을 할 계획인지 기억하기 위한 임시 데이터.  
**지원 연산**: Upsert (1일 1행) · Read · Delete  
**비고**: 카드만 얹은(세트 0인) 상태에서 앱을 닫아도 `exercise_records` 시트엔 아무것도 올라가지 않는다. 실제 세트가 입력될 때만 `exercise_records` insert.

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

## 공통 규칙

- **UUID 자동 생성**: `uuid: ''` (빈 문자열) 전달 시 SQLite 구현체에서 UUID v4 자동 할당
- **컬럼 네이밍**: DB는 `snake_case`, Dart Entity는 `camelCase` — Repository에서 매핑
- **`id` 컬럼**: 로컬 전용, Google Sheets 연동 시 절대 사용 금지 (uuid 사용)
