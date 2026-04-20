# v7 변경 로그 — Google Sheets → Supabase 전환

> 작성: 2026-04  
> 관련 브랜치: `claude/fitness-app-analysis-Bjivj`

## 배경

v6까지의 동기화 백엔드는 Google Sheets API였다. 스프레드시트는 직관적이었지만 다음의 한계가 누적됨:

1. **스키마 경직** — 컬럼 추가 시 각 사용자 시트를 일괄 마이그레이션할 수단이 없음.
2. **Row 파싱 오버헤드** — A:Z 문자열 셀을 타입별 파싱하는 비용이 기록 수에 비례 증가.
3. **권한 모델 복잡성** — 스프레드시트 생성/공유/재발급 흐름이 사용자 혼동을 유발.
4. **LWW 충돌 해결** — updated_at 기반 LWW를 시트에서 견고하게 구현하기 어려움.

## 변경 요약

- **`googleapis`, `google_sign_in`, `extension_google_sign_in_as_googleapis_auth` 패키지 전면 제거.**
- **Supabase 전면 도입** (`supabase_flutter`, PostgreSQL 테이블):
  - `exercise_records`, `diet_records`, `weight_records`, `exercise_templates`, `food_templates`, `workout_routines`
  - `is_deleted` 컬럼으로 soft-delete 표현
  - `user_id`로 사용자별 격리 (RLS 정책)
- **`GoogleAuthService`는 이름 유지**하되 Supabase OAuth 래퍼로 내부 전환. 향후 `SupabaseAuthService`로 리네임 고려.
- **`SpreadsheetStatusCard`** 위젯 이름 유지(설정 카드) — 향후 `SupabaseStatusCard`로 리네임 고려.
- **`SupabaseService.ensureAllRequiredSheets()` 는 no-op** — Supabase 테이블은 서버 측에서 관리. 호출 경로는 legacy 호환 유지.

## 현재 아키텍처 (v7 이후)

```
UI ↔ Riverpod Provider ↔ Repository(인터페이스)
                              ↓
                         Sqlite<X>Repository (로컬 캐시)
                              ↕
                         SupabaseService (batchPush* / read*Delta)
                              ↕
                         Supabase PostgreSQL
```

- **Push**: `syncStatus != synced` 인 로컬 레코드를 upsert (`onConflict: 'uuid'`).
- **Pull**: 마지막 동기화 이후의 delta를 `updated_at >= lastSyncAt` 로 조회.
- **LWW**: 로컬·리모트 모두 있는 uuid는 `updated_at` 비교로 최신 승리.
- **HardDelete**: `syncStatus == deleted` 이고 push 성공한 레코드는 로컬 DB에서 실제 삭제.

## v9 Supabase 운영 체크리스트 (set_type 컬럼 추가)

DB v9에서 로컬 `exercise_records.set_type` 컬럼이 신설되었으므로, **Supabase 대시보드에서 원격 테이블도 동일 컬럼을 수동 ALTER**해야 한다:

```sql
ALTER TABLE public.exercise_records
ADD COLUMN IF NOT EXISTS set_type text NOT NULL DEFAULT 'work';
```

- 대시보드 → Database → Tables → `exercise_records` → Add column (`text`, NOT NULL, default `'work'`).
- ALTER 이전에 배포된 앱 버전이 push하면 RPC 측에서 에러가 날 수 있으므로, **컬럼 ALTER를 배포보다 먼저** 수행한다.
- 기존 row는 DEFAULT로 전부 `'work'` 가 되며 이는 의도된 동작(과거 데이터는 본세트로 간주).
- `SupabaseService.batchPushExerciseRecords` 의 row 맵에 `'set_type': r.setType.value` 가 추가됨.
- `SupabaseService._rowToExerciseRecord` 는 `SetType.fromString(row['set_type'] as String?)` 로 legacy row(컬럼 없음)도 안전히 `work` 로 fallback.

## 문서 정리 노트

v6 시절 작성된 다음 서술은 본 changelog 작성 시점까지 갱신이 누락되어 있었으며, v9 브랜치에서 함께 정정됨:

- `CLAUDE.md` L8 스택 표기 (`googleapis` → `supabase_flutter`)
- `CLAUDE.md` L12 데이터 흐름 ("Google Sheets API" → "Supabase API")
- `docs/features.md` L57-67 "Google Sheets 동기화" 섹션 (→ "Supabase 동기화")
- `docs/db-schema.md` 버전 이력에 v7 설명 추가

## 잔여 작업 (백로그)

- [ ] `GoogleAuthService` → `SupabaseAuthService` 리네임 (호출자 다수, 신중히)
- [ ] `SpreadsheetStatusCard` → `SupabaseStatusCard` 리네임 (UX 혼동 방지)
- [ ] `SupabaseService.ensureAllRequiredSheets()` no-op 함수 제거 (호출자 정리 후)
- [ ] 오프라인 모드 명시 배너 (features.md 백로그)
