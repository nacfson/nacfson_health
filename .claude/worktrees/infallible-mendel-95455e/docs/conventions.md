# 코딩 컨벤션

> **문서 버전**: 2026-04  
> **범위**: 프로젝트 전반의 코딩 스타일, 네이밍, 테마, UI 규칙

---

## 1. DB 네이밍

| 레이어 | 컨벤션 | 예시 |
|--------|--------|------|
| SQLite 컬럼 | `snake_case` | `exercise_type`, `sync_status`, `updated_at` |
| Dart Entity 필드 | `camelCase` | `exerciseType`, `syncStatus`, `updatedAt` |
| Repository 매핑 | `_toMap()` / `_fromMap()` | snake ↔ camel 변환 |

---

## 2. 테마 규칙

- **디자인 시스템**: Material 3
- **Seed Color**: `Colors.deepPurple`
- **Card 기본 스타일**: `elevation=2`, `borderRadius=12` (추가 스타일 불필요)
- **테마 파일**: `lib/core/theme/app_theme.dart`

---

## 3. Bottom Sheet 사용 규칙

- **상태 관리**: `sheet_state_provider.dart`의 `openSheet()` 헬퍼 사용
- **토글 동작**: 동일 타입 호출 시 토글(열려있으면 닫기), 타 타입 호출 시 기존 창 교체
- **반응형 너비**: 데스크톱/웹 대응을 위해 `ConstrainedBox` 최대 너비 **600px** 제한
- **배치**: `Align(alignment: Alignment.bottomCenter)` — 넓은 화면에서도 하단 중앙
- **키보드 대응**: `SingleChildScrollView` + `MediaQuery.of(context).viewInsets.bottom` 패딩
- **컨테이너**: `RecordFormSheet` — 슬라이드/페이드 애니메이션 적용

---

## 4. 탭 전환 규칙

- 하단 네비게이션 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- Shell Navigator + Root Navigator 모두 `popUntil(isFirst)` 호출

---

## 5. 예외 처리 의무

> 상세 전략과 코드 예시는 `docs/error-handling.md` 참조

모든 DB 작업, 동기화, 폼 제출 작업은 반드시 `try/catch`로 감싸고 UI 피드백 제공:

| 심각도 | 상황 | UI 컴포넌트 |
|--------|------|-----------|
| 낮음 | 동기화/네트워크 실패 | `ErrorOverlay` (자동 닫힘) |
| 중간 | 저장 실패 | `SnackBar` |
| 높음 | DB 오픈 실패 | `AlertDialog` |

**금지사항**:
- `try/catch` 없는 `await`
- 로그(`debugPrint`)만 남기고 UI 피드백 생략

---

## 6. 문서 업데이트 의무

- 기능 추가/변경 시 관련 문서 즉시 동기화
- DB 테이블 변경 → `docs/db-schema.md` 업데이트 필수
- 기능 완료 → `docs/features.md` 체크박스 반영 필수
- 실수 발생, 같은 코드 수정 반복 시 → 관련 docs 가이드라인에 하네스 프롬프트 추가

---

## 7. 기존 코드 재사용

- 새 기능 구현 전, 프로젝트 내 기존 코드·유틸리티·패턴 중 재사용 가능한 것이 있는지 먼저 확인
- 새 코드 작성 전에 재사용 가능성을 공유하고 계획 조율
- 중복 구현 금지

---

## 관련 문서

| 문서 | 참조 내용 |
|------|----------|
| `docs/error-handling.md` | 심각도별 예외 처리 상세 전략 및 코드 예시 |
| `docs/implementation-guide.md` | 새 도메인 추가 10단계, SyncStatus 정의 |
| `docs/ui-architecture.md` | 위젯 계층도, 애니메이션 상세 |
