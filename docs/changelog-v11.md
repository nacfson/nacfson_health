# v11 변경 로그 — 종목별 휴식 시간 오버라이드 + UX 개편

> 작성: 2026-04
> DB 버전: v10 → v11

## 배경

v10 까지의 휴식 타이머는 단일 전역 기본값 (`default_rest_seconds` SharedPreferences 키, 60/90/120/180 4단계) 만 가지고 있었다. 부위별 회복 특성이 무시되어 사용자가 매 세트 수동 조정 → 마찰. v11 은 **부위 기본값 + 종목별 오버라이드** 2단 체계로 전환하여 자동화 수준을 높이는 것이 목표.

## DB 변경

### v11 마이그레이션

```sql
ALTER TABLE exercise_templates ADD COLUMN rest_seconds_override INTEGER;
```

- 종목별 휴식 시간 오버라이드(초). `NULL` 이면 클라이언트가 부위 기본값을 해석한다.
- 유효 입력 범위: 60~300 (`kMinRestSeconds`/`kMaxRestSeconds` in [body_part_rest_defaults.dart](lib/features/exercise/domain/body_part_rest_defaults.dart)).
- 기존 템플릿은 NULL 로 시작 — 자연스럽게 부위 기본값으로 동작.
- 부위별 기본값(근비대 기준 코드 상수): 하체 180s · 등 150s · 가슴 120s · 어깨 90s · 팔 60s · 코어 60s · 기타 90s · 유산소 `null`(타이머 미사용).
- 전역 `default_rest_seconds` SharedPreferences 키는 v11 이후 참조되지 않음 (레거시 키 자연 소멸).

### Supabase 원격 마이그레이션

파일: [supabase/migrations/20260424_0002_exercise_templates_rest_override.sql](supabase/migrations/20260424_0002_exercise_templates_rest_override.sql)

```sql
ALTER TABLE public.exercise_templates
  ADD COLUMN IF NOT EXISTS rest_seconds_override INTEGER;
```

## 사고 회고 — 2026-04-26 PGRST204

설정 화면 동기화 시 다음 에러:

> Could not find the 'rest_seconds_override' column of 'exercise_templates' in the schema cache, code: PGRST204

**원인**: 4/24 Supabase 마이그레이션 SQL 파일은 작성됐지만 **원격 DB 에 push 가 누락**됨. 클라이언트 v11 은 새 컬럼 포함 row 를 push 하는데 서버 schema cache 에 컬럼 없음 → PostgREST 거절.

**검증 (Supabase MCP `execute_sql` 직접 조회):**

```sql
SELECT * FROM supabase_migrations.schema_migrations;
-- → relation does not exist (단 한 번도 push 된 적 없음)

SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='exercise_templates';
-- → rest_seconds_override 부재 확인

SELECT * FROM information_schema.triggers
WHERE event_object_schema='public' AND event_manipulation='UPDATE';
-- → 트리거 0건 (set_updated_at 미설치)
```

**복구**: Supabase Studio SQL Editor 또는 MCP `apply_migration` 로 SQL 파일 실행. idempotent (`ADD COLUMN IF NOT EXISTS`) 라 안전.

**남은 이슈**:
- `set_updated_at` 트리거는 4/26 시점에도 0건. [supabase/migrations/20260423_0001_add_updated_at_triggers.sql](supabase/migrations/20260423_0001_add_updated_at_triggers.sql) 도 함께 적용 필요. 미설치 시 외부 경로 UPDATE 가 다른 기기로 전파되지 않는 silent drift 발생.
- `user_profiles` 테이블은 원격에 부재. v10 마이그레이션이 ALTER TABLE 만 하므로 적용 시 실패. user_profiles 가 sync 대상에 포함되어야 하는지 정책 결정 후 별도 작업.

**예방책 (CLAUDE.md / db-schema.md 에 반영)**: Supabase 마이그레이션 SQL 파일 작성과 원격 적용은 **동일 커밋·동일 작업 단위에서 완료**. push 누락 상태로 클라이언트 배포 금지.

## UX 개편 (v11.1)

### `ExerciseTemplateCard` (운동 템플릿 카드)
- `ExpansionTile` 제거 — 설정 진입 즉시 노출.
- **검색/추가 SegmentedButton 탭 분리**:
  - 검색 탭 — 입력 시에만 매칭 칩 노출. 매칭 0 건이면 "추가 탭으로 이동" 링크.
  - 추가 탭 — 이름 + 부위 ChoiceChip. 이미 보유한 이름이면 인라인 헬퍼 + 추가 버튼 disabled.
- 휴식 편집 BottomSheet — BottomNav 겹침 / 세 자리 수 표시 잘림 버그 수정.
- 기본 템플릿 16 → 56 종 확장 (시드 플래그 v2).

### `FoodTemplateCard` (음식 템플릿 카드)
- 동일하게 `ExpansionTile` 제거 + 검색/추가 SegmentedButton 탭 분리.
- 추가 탭 — 이름 + 매크로(칼로리 / 탄·단·지) 입력. 중복 시 추가 버튼 disabled.

### 휴식 타이머 통합
- 종목별 오버라이드 편집은 `ExerciseTemplateCard` 칩 탭(설정 탭)에서만. 세션 중 ±15초 조정은 해당 세션에 한해 일시 적용.
- 레거시 `RestTimerSettingsCard` 제거 — 부위 기본값 + 종목 오버라이드 체계로 일원화.

## 업데이트된 문서

- [CLAUDE.md](CLAUDE.md) — DB 버전 라인 v11.
- [docs/db-schema.md](docs/db-schema.md) — 버전 이력 + v11 마이그레이션 상세.
- [docs/features.md](docs/features.md) — `ExerciseTemplateCard` / `FoodTemplateCard` v11.1 체크박스, 부위별 기본 휴식 항목, 레거시 `RestTimerSettingsCard` 제거 표시.
