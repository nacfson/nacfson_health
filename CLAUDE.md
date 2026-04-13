# CLAUDE.md

이 문서는 AI 어시스턴트가 본 레포지토리의 코드를 작성하고 수정할 때 반드시 준수해야 하는 핵심 컨텍스트와 규칙입니다.

## 1. 프로젝트 및 스택 개요
- **목표**: 구글 폼/시트 대체 개인 맞춤형 피트니스 & 식단 통합 대시보드
- **스택**: Flutter, Dart, Riverpod (StateNotifier+Provider), go_router (ShellRoute), sqflite, googleapis
- **UX 원칙**: 폼보다 빠른 입력, 시트보다 직관적인 결과 시각화

## 2. 핵심 아키텍처 & 데이터 흐름
- **흐름**: UI → Provider(StateNotifier) → Repository(Interface) → SQLite(구현체) ↔ SyncService ↔ Google Sheets API
- **진입점 (`main.dart`)**: `SharedPreferences` 초기화 후 `ProviderScope.overrides`로 `syncPreferencesProvider`, `googleAuthServiceProvider` 주입 필수. (기본값 UnimplementedError)
- **동기화 트리거**: 앱 진입 시 `GoogleAuthService.restoreSession()` 실행. `AppLifecycleState.resumed` 상태 시 `_triggerSync()` 자동 호출.

## 3. 도메인 모듈 구조
| 도메인 | 핵심 기능 | 관련 Provider |
|--------|----------|---------------|
| exercise | 운동 기록 (가슴/등... 순서 고정), 볼륨 계산 | `todayExerciseGroupedProvider`, `todayTotalVolumeProvider` |
| diet | 식단 기록, 매크로(탄/단/지) 관리 | `todayDietGroupedProvider`, `todayDietSummaryProvider` |
| summary | 일일 요약 (fl_chart 시각화) | `dailySummaryProvider` (목표치 참조) |
| sync | 구글 시트 동기화, Auth, 목표값 관리 | `syncStateProvider`, `nutritionTargetsProvider` |
| settings | 운동·음식 템플릿 관리 (SQLite + 시트 동기화) | `exerciseTemplatesProvider`, `foodTemplatesProvider` |

## 4. 데이터베이스 및 스키마 주요 규칙
- **UUID 자동 생성**: 레코드 생성 시 `uuid: ''` (빈 문자열)을 넘기면 `SqliteRepository`에서 UUID v4 자동 할당.
- **DB 네이밍**: SQLite 컬럼은 `snake_case`, Dart Entity는 `camelCase` 사용 (Repository에서 매핑).
- **SyncStatus**: `0=synced`, `1=created`, `2=modified`, `3=deleted`. exercise/diet 레코드는 전체 CRUD. 템플릿(`TemplateSyncStatus`, `FoodTemplateSyncStatus`)은 `modified(2)` 없이 생성/삭제만 지원.
- **DB 버전**: 현재 v4. 테이블: `exercise_records`(v1) · `diet_records`(v2) · `exercise_templates`(v3) · `food_templates`(v4). 전체 스키마는 `docs/db-schema.md` 참조.
- **마이그레이션**: `DatabaseHelper.onUpgrade()`에서 처리. 완료 후 `lastSyncTimestamp=0`으로 초기화하여 강제 동기화(LWW 충돌 해결) 유도.

## 5. UI 및 UX 규칙
- **Bottom Sheet (`sheet_state_provider.dart`)**: `openSheet()` 헬퍼 사용. 동일 타입 호출 시 토글, 타 타입 호출 시 기존 창 교체.
- **RecordFormSheet**: 슬라이드/페이드 애니메이션, 키보드 패딩 적용, 최대 너비 600px 제한.
- **탭 전환**: 하단 네비게이션 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`).
- **테마**: Material 3, `seedColor: Colors.deepPurple`. (Card는 elevation=2, radius=12 기본 적용으로 추가 스타일 불필요).

## 6. 🚨 예외 처리 및 오류 가시화 (필수)
모든 DB 작업, 동기화, 폼 제출 작업은 반드시 `try/catch`로 감싸고, 실패 시 사용자가 알 수 있도록 UI 피드백을 제공해야 합니다.
- **낮은 심각도 (동기화/네트워크 실패)**: `ErrorOverlay` (자동 닫힘)
- **중간 심각도 (저장 실패)**: `SnackBar`
- **높은 심각도 (DB 오픈 실패 등)**: `AlertDialog`
- **금지사항**: `try/catch` 없는 `await`, 로그(`debugPrint`)만 남기고 UI 피드백을 생략하는 행위.

## 7. 문서 업데이트 의무
- 기능 추가/변경 시 관련 문서를 즉시 동기화할 것.
- DB 테이블 변경 → `docs/db-schema.md` 업데이트 필수.
- 기능 완료 → `docs/features.md` 체크박스 반영 필수.

## 8. 참조 문서
- `docs/db-schema.md` — DB 버전 이력, 전체 테이블 스키마, 마이그레이션 SQL
- `docs/features.md` — 구현 완료 기능 체크리스트, 구현 패턴, 백로그
- `docs/architecture.md` — 동기화 프로토콜, 도메인 분리 구조
- `docs/ui-architecture.md` — 위젯 계층도, 네비게이션 구조