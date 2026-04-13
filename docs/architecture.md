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
| **요약** | 두 데이터 병합 → 하루 목표 대비 현재 섭취량/운동 소비량 통합 표시 | `DailySummary` |
| **운동 템플릿** | 운동 종목 프리셋 관리, SQLite + Sheets 동기화 (생성·삭제만) | `ExerciseTemplate` |
| **음식 템플릿** | 음식 프리셋 관리 (이름·칼로리·탄단지), SQLite + Sheets 동기화 (생성·삭제만) | `FoodTemplate` |

---

## 아키텍처 원칙

- **낮은 결합도**: UI는 데이터 소스(로컬 DB, 외부 API)를 모름
- **인터페이스 기반**: Repository 인터페이스로 데이터 접근을 추상화
- **상태 무결성**: 탭 전환 시 모든 다이얼로그/바텀시트를 닫는 `popAll` 정책으로 네비게이션 스택 유지
- **반응형 제약**: 데스크톱/웹 환경을 위해 바텀 시트 최대 너비 600px
- **방어적 개발**: 기존 코드 재사용 우선, 중복 구현 금지

---

## 동기화 프로토콜 (4단계)

`lib/core/sync/sync_state.dart` → `_syncAll()` 함수에서 실행.

| 단계 | 방향 | 내용 |
|------|------|------|
| **1. Push** | 로컬 → 시트 | `sync_status = created/modified/deleted` 항목을 시트에 업서트·삭제 후 `synced`로 마킹 |
| **2. Pull** | 시트 → 로컬 | `lastSyncTime` 이후 변경된 행을 가져와 로컬에 병합 |
| **3. HardDelete** | 로컬 | `sync_status = deleted` + 시트 반영 완료된 항목을 로컬 DB에서 영구 삭제 |
| **4. Timestamp 갱신** | — | 오류 없을 때만 `lastSyncTimestamp` 업데이트 |

**Pull 병합 전략**:
- 레코드(`exercise_records`, `diet_records`): LWW (Last-Write-Wins, `updated_at` 기준)
- 템플릿(`exercise_templates`, `food_templates`): insert-or-skip (uuid 중복 시 무시)

**ensureAllRequiredSheets()**: 동기화 전 필수 시트 존재를 멱등으로 보장 (없는 시트만 생성).

---

## DB 스키마

전체 테이블 스키마 및 버전 이력은 `docs/db-schema.md` 참조.

**현재 DB 버전**: v4 (테이블 4개: exercise_records · diet_records · exercise_templates · food_templates)

---

> 상세 스키마(컬럼 정의, SyncStatus 정책, 마이그레이션 SQL)는 `docs/db-schema.md` 참조.

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