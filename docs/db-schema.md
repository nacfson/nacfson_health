# DB 스키마 (SQLite)

> **현재 버전**: v4  
> **DB 파일명**: `nacfson_health.db`  
> **마지막 업데이트**: 2026-04

---

## 버전 이력

| 버전 | 추가 테이블 | 비고 |
|------|-----------|------|
| v1 | `exercise_records` | 초기 출시 |
| v2 | `diet_records` | 식단 기록 추가 |
| v3 | `exercise_templates` | 운동 종목 프리셋 |
| v4 | `food_templates` | 음식 프리셋 (2026-04) |

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
| `updated_at` | INTEGER | 마지막 수정 시각 (ms since epoch) |
| `sync_status` | INTEGER | TemplateSyncStatus 값 |

**TemplateSyncStatus**: `synced(0)` / `created(1)` / `deleted(3)` — `modified(2)` **미사용**  
**지원 연산**: Create · Delete (수정 없음)  
**Pull 병합 전략**: insert-or-skip (uuid 기준, LWW 불필요)

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

## Google Sheets 대응 시트

| DB 테이블 | Sheets 탭 | 헤더 범위 |
|----------|-----------|---------|
| `exercise_records` | `exercise_records` | A1:K1 |
| `diet_records` | `diet_records` | A1:M1 |
| `exercise_templates` | `exercise_templates` | A1:D1 |
| `food_templates` | `food_templates` | A1:G1 (uuid/name/calories/carbs/protein/fat/updatedAt) |

> **동기화 메타데이터** (spreadsheetId, lastSyncTime, 영양 목표값 등)는 `SharedPreferences`에 저장 — DB 외부.

---

## 공통 규칙

- **UUID 자동 생성**: `uuid: ''` (빈 문자열) 전달 시 SQLite 구현체에서 UUID v4 자동 할당
- **컬럼 네이밍**: DB는 `snake_case`, Dart Entity는 `camelCase` — Repository에서 매핑
- **`id` 컬럼**: 로컬 전용, Google Sheets 연동 시 절대 사용 금지 (uuid 사용)
