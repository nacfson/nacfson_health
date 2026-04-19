# 새 도메인 추가 구현 가이드

> **문서 버전**: 2026-04  
> **범위**: 새 도메인/테이블 추가 시 따라야 하는 구현 순서 및 코딩 규칙

---

## 구현 10단계

새 도메인(테이블) 추가 시 아래 순서로 구현:

```
1.  Entity           lib/features/{domain}/domain/entities/{entity}.dart
2.  DB 마이그레이션   lib/core/database/database_helper.dart (version++, onCreate, onUpgrade)
3.  Repository 인터페이스  lib/features/{domain}/data/repositories/{entity}_repository.dart
4.  SQLite 구현체     lib/features/{domain}/data/repositories/sqlite_{entity}_repository.dart
5.  Provider         lib/features/{domain}/presentation/providers/{entity}_provider.dart
6.  GoogleSheetsService  ensureAllRequiredSheets + push + pull 메서드 추가
7.  GoogleAuthService    createSpreadsheet 시트 목록에 추가
8.  sync_state.dart  SyncStateNotifier 주입 + _syncAll 단계 추가
9.  UI 위젯          설정 카드 or 폼 드롭다운
10. docs 업데이트    db-schema.md + features.md + architecture.md + domains.md + ui-architecture.md
```

---

## UUID 규칙

- **UUID 자동 생성**: 레코드 생성 시 `uuid: ''` (빈 문자열)을 넘기면 `SqliteRepository`에서 UUID v4 자동 할당.
- **`id` 컬럼**: 로컬 전용 (`INTEGER PRIMARY KEY AUTOINCREMENT`). Google Sheets 연동 시 절대 사용 금지 — `uuid` 사용.

---

## DB 네이밍 규칙

- **SQLite 컬럼**: `snake_case` (예: `exercise_type`, `sync_status`)
- **Dart Entity**: `camelCase` (예: `exerciseType`, `syncStatus`)
- **매핑**: Repository 구현체(Sqlite~Repository)의 `_toMap()` / `_fromMap()` 메서드에서 변환

---

## SyncStatus 정의

### 레코드 계열 (exercise_records, diet_records, weight_records)

| 값 | 이름 | 의미 |
|----|------|------|
| 0 | `synced` | 시트와 동일 |
| 1 | `created` | Insert 필요 |
| 2 | `modified` | Update 필요 |
| 3 | `deleted` | Soft Delete (Push 후 HardDelete) |

**지원 연산**: 전체 CRUD (Create · Read · Update · Delete)  
**Pull 병합 전략**: LWW (Last-Write-Wins) — `updated_at` 기준으로 최신 레코드 우선

### 템플릿 계열 (exercise_templates, food_templates)

| 값 | 이름 | 의미 |
|----|------|------|
| 0 | `synced` | 시트와 동일 |
| 1 | `created` | Insert 필요 |
| 3 | `deleted` | Soft Delete |

> ⚠️ `modified(2)` **미사용** — 템플릿은 수정 없이 생성·삭제만 지원

**지원 연산**: Create · Delete (수정 없음)  
**Pull 병합 전략**: insert-or-skip (uuid 기준, LWW 불필요)

---

## DB 마이그레이션 규칙

- `DatabaseHelper.onUpgrade()`에서 `oldVersion < N` 분기로 누적 처리
- `CREATE TABLE IF NOT EXISTS` 사용 (멱등성 보장)
- 마이그레이션 후 `SyncPreferences.lastSyncTimestamp = 0` 초기화 → 강제 풀 싱크로 LWW 충돌 해결

---

## 진입점 (main.dart) 주입 규칙

- `SharedPreferences` 초기화 후 `ProviderScope.overrides`로 `syncPreferencesProvider`, `googleAuthServiceProvider` 주입 필수 (기본값 UnimplementedError).
- 앱 시작 시 `GoogleAuthService.restoreSession()` 실행.
- `AppLifecycleState.resumed` 상태 시 `_triggerSync()` 자동 호출.

---

## 관련 문서

| 문서 | 참조 내용 |
|------|----------|
| `docs/db-schema.md` | 전체 테이블 스키마, 버전 이력, Sheets 대응 |
| `docs/architecture.md` | 동기화 프로토콜 4단계, 데이터 흐름 |
| `docs/features.md` | 완료/백로그 체크리스트 |
