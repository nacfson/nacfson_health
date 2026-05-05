# CLAUDE.md

이 문서는 AI 어시스턴트가 본 레포지토리의 코드를 작성하고 수정할 때 반드시 준수해야 하는 핵심 컨텍스트와 규칙입니다.

## 프로젝트 요약

- **목표**: 개인 맞춤형 피트니스 & 식단 통합 대시보드
- **스택**: Flutter, Dart, Riverpod (StateNotifier+Provider), go_router (ShellRoute), sqflite, supabase_flutter, fl_chart
- **DB 버전**: v12 (테이블 13개: exercise_records · diet_records · exercise_templates · food_templates · weight_records · user_profiles · workout_routines · daily_routine + v12 신규 5개 admin-curated 마스터: exercise_categories · exercise_category_translations · exercise_definitions · exercise_translations · one_rm_formulas. v12: 다국어 지원(ko/en) + 종목별 권위 1RM 공식 — exercise_records/templates 에 exercise_key 컬럼 추가, NSCA LeSuer 1997 검증 기반 Mayhew/Wathen/Brzycki 공식 적용, 1RM 코치 진입 시 Supabase TTL 24h fetch)
- **탭 구조**: 운동 | 식단 | 체중 | 요약 | 설정
- **UX 원칙**: 폼보다 빠른 입력, 시트보다 직관적인 결과 시각화
- **데이터 흐름**: UI → Provider(StateNotifier) → Repository(Interface) → SQLite(구현체) ↔ SupabaseService ↔ Supabase API

## Task Routing (반드시 준수할 것)

작업의 종류에 따라 코드를 수정하기 전 아래의 연관 문서를 반드시 먼저 읽고 지시사항을 따르세요.

- **아키텍처, 데이터 흐름, 동기화 로직 수정 시**: `docs/architecture.md`
- **DB 테이블/컬럼 변경, 마이그레이션 작성 시**: `docs/db-schema.md`
- **Supabase 서버 스키마/트리거 수정, 신규 sync 테이블 추가 시**: `docs/db-schema.md` 의 "Supabase 서버 스키마 관리" 섹션 및 `supabase/migrations/` 확인
- **UI 위젯/레이아웃/네비게이션 수정 시**: `docs/ui-architecture.md`
- **도메인 모듈(exercise/diet/weight/sync/settings/activity) 수정 시**: `docs/domains.md`
- **Apple Health / Android Health Connect 연동, 활동 데이터(걸음/심박/칼로리) 변경 시**: `docs/architecture.md` 의 "외부 활동 데이터 흐름" 섹션 + `docs/build-debug.md` 의 "Apple Health & Android Health Connect 디버깅" 섹션
- **에러 처리, try/catch 패턴 작성 시**: `docs/error-handling.md`
- **기능 완료/백로그 업데이트 시**: `docs/features.md`
- **새 도메인/테이블 추가 시**: `docs/implementation-guide.md`
- **코딩 컨벤션, 네이밍 규칙 확인 시**: `docs/conventions.md`
- **빌드 오류, 런타임 크래시, 프리뷰 실행 문제 발생 시**: `docs/build-debug.md`
- **StateNotifier 초기화, GoRouter redirect, dispose() ref 사용 시**: `docs/build-debug.md`

## 문서 업데이트 의무

- 기능 추가/변경 시 관련 문서를 즉시 동기화할 것.
- DB 테이블 변경 → `docs/db-schema.md` 업데이트 필수.
- 기능 완료 → `docs/features.md` 체크박스 반영 필수.
- 실수 발생 시 → 관련 docs 가이드라인에 하네스 프롬프트 추가.

### 마이그레이션 (DB / Supabase) — 무조건 다음 문서를 함께 업데이트할 것

DB 버전 증가 또는 `supabase/migrations/` 신규 SQL 파일 작성·적용 시, 같은 작업 단위에서 **반드시** 다음을 모두 갱신한다 (하나라도 누락 시 PR 미완성으로 간주):

1. **이 파일 (`CLAUDE.md`)** — 위 "프로젝트 요약" 의 **DB 버전** 라인 (버전 숫자 + 새 컬럼/테이블 한 줄 요약).
2. **`docs/db-schema.md`** — "버전 이력" 표에 한 행 추가 + 새 버전 마이그레이션 SQL 상세 섹션 작성 + 영향받는 테이블 스키마 본문 갱신.
3. **`docs/features.md`** — 새 기능 체크박스 추가 (구현 완료 항목) + 레거시 항목 취소선 처리.
4. **`docs/changelog-vN.md`** — 새 버전 changelog 파일 신규 작성 (배경 / DB 변경 / 사고 회고(있으면) / UX 개편).
5. **이 파일 (`CLAUDE.md`) 의 "참조 문서 목록" 표** — 새 changelog 행 등록.
6. **Supabase 마이그레이션의 경우 — 원격 DB 적용까지 동일 작업 단위에서 완료**. 작성만 하고 push 누락 상태로 클라이언트 배포 금지. 절차·검증 쿼리는 `docs/db-schema.md` "마이그레이션 작성·적용 작업 체크리스트" 참조.

## 참조 문서 목록

| 문서 | 설명 |
|------|------|
| `docs/architecture.md` | 동기화 프로토콜, 도메인 분리 구조, 데이터 흐름 |
| `docs/db-schema.md` | DB 버전 이력, 전체 테이블 스키마, 마이그레이션 SQL |
| `docs/ui-architecture.md` | 위젯 계층도, 네비게이션 구조, 애니메이션 |
| `docs/domains.md` | 도메인 모듈별 책임과 Provider 매핑 |
| `docs/error-handling.md` | 심각도별 예외 처리 전략, 금지사항 |
| `docs/features.md` | 구현 완료 기능 체크리스트, 백로그 |
| `docs/implementation-guide.md` | 새 도메인 추가 10단계, UUID/SyncStatus 규칙 |
| `docs/conventions.md` | 코딩 컨벤션, 네이밍, 테마, UI 규칙 |
| `docs/changelog-v5.md` | v5 변경 로그 (운동 템플릿 & UI 개선) |
| `docs/changelog-v5-1.md` | v5.1 변경 로그 (기존 데이터 정리 & 설정 UI 개선) |
| `docs/changelog-v6.md` | v6 변경 로그 (DB v7, AI 인사이트, 온보딩, 다크 모드, Pretendard) |
| `docs/changelog-v7.md` | v7 변경 로그 (Google Sheets → Supabase 전환) |
| `docs/changelog-v11.md` | v11 변경 로그 (`rest_seconds_override` + 부위별 휴식 + 템플릿 카드 UX 개편 + Supabase 마이그레이션 사고 회고) |
| `docs/changelog-v12.md` | v12 변경 로그 (다국어 ko/en + 종목별 권위 1RM 공식 + admin-curated 운동 마스터 데이터 + TTL 24h 캐시) |
| `docs/changelog-v12-1.md` | v12-1 변경 로그 (보안 하드닝 — dart-define 전환 + iOS OAuth ID + iOS 휴식 알림 안정화 + ExercisePickerField 통합 + 1RM 빠른 추정 카드 제거) |
| `docs/changelog-v12-2.md` | v12-2 변경 로그 (B/C 그룹 audit — 빈 catch 정리 + master data throttle + 휴식 타이머 race 가드 + RecordFormSheet onConfirmClose + showAppSnackBar + Semantics + legacy_korean_mapping 회귀 테스트) |
| `docs/changelog-v12-3.md` | v12-3 변경 로그 (UI/UX HIGH 7건 — 다크 토큰 매크로 + 검증 메시지 친절화 + 터치 타겟 44 + DietForm swipe-down 경고 + 로딩 상태 spinner + NumericStepperField + 식단 SnackBar Undo) |
| `docs/build-debug.md` | 빌드 타겟, Riverpod 초기화, GoRouter, dispose, macOS 포커스, Gemini 디버깅 |

## Git 환경 설정

- `extensions.worktreeConfig=false` (`~/.gitconfig` 전역 설정)
  - 모든 git worktree가 공통 `.git/config`를 사용하도록 전역 강제