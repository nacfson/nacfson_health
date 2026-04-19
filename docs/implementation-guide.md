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
- **비동기 _load() 금지**: `OnboardingNotifier`, `HeightNotifier`, `InsightCallCountNotifier`처럼 SharedPreferences 의존 Notifier는 main.dart에서 미리 로드한 값을 `overrideWith((ref) => Notifier(initial))` 로 주입할 것. UI 첫 빌드에서 플리커가 발생하지 않게 하기 위함 (참조: `lib/main.dart`, `docs/build-debug.md` #2).

---

## 신규 도메인 외 자주 쓰는 패턴 (v6/v7 추가)

### 1. `FutureProvider.autoDispose` + 일일 호출 상한 + 세션 캐시

외부 API(Gemini 등) 호출을 캐싱·제한하는 표준 형태. 출처: [`lib/core/ai/health_insight_provider.dart`](../lib/core/ai/health_insight_provider.dart).

- **세션 캐시 Provider**: `StateProvider<Map<String, T>>`. 캐시 키는 `YYYYMMDD` 문자열 (헬퍼: `insightCacheKey(DateTime)`).
- **카운트 Notifier**: `StateNotifier<Map<String, int>>` + SharedPreferences. 키 예: `insight_call_count_v1` (스키마 변경 시 `_v2` 로 bump).
- **호출 직전 증가**(increment-before): 네트워크 실패 시에도 카운트 소모 → 비용 방어 우선.
- **상한 초과 시**: `throw StateError('DAILY_LIMIT_REACHED')` — UI는 `AsyncValue.error` 분기에서 안내.
- **상수 위치**: 같은 파일 상단에 `const kInsightDailyLimit = 3` 형태로 노출.

### 2. 온보딩 1회성 플래그 패턴

출처: [`lib/shared/providers/user_profile_provider.dart`](../lib/shared/providers/user_profile_provider.dart).

- 키: `onboarding_done` (bool), `user_height_m` (double, **meter 단위**).
- Notifier 생성자는 `initial` 파라미터를 받아 main.dart에서 주입.
- `complete()` / `setHeight()` 같은 액션은 항상 state 갱신 + SharedPreferences write를 함께 수행.

### 3. GoRouter `refreshListenable` 패턴

출처: [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).

- Riverpod 상태(예: `onboardingDoneProvider`)와 GoRouter redirect를 연결할 땐 ChangeNotifier 어댑터(`_RouterNotifier`) + `refreshListenable: notifier` 조합.
- GoRouter는 한 번만 생성해야 하므로 `appRouterProvider` 내부에서 `ref.read`로 notifier를 가져옴 (`ref.watch` 금지 — 라우터 객체가 통째로 재생성되어 네비 스택이 초기화됨).
- 자세한 함정 사례는 `docs/build-debug.md` #3 참조.

### 4. SharedPreferences 직접 호출 금지 — `SyncPreferences` 일원화

출처: [`lib/core/sync/sync_preferences.dart`](../lib/core/sync/sync_preferences.dart).

- 새로운 영구 키 추가 시 항상 `SyncPreferences`에 getter/setter를 만들고 그 래퍼만 호출.
  - 예: 테마 모드는 `themeModeRaw` / `setThemeModeRaw` 사용 (`ThemeModeNotifier`).
- **예외**: 부트스트랩 단계의 main.dart는 `SharedPreferences.getInstance()` 직접 호출 가능 (Notifier 초기값 로드 목적).
  - 이 경우에도 키 문자열은 Notifier 정의 파일의 `_kXxxKey` 상수와 일치시켜야 함 (drift 방지).

---

## 관련 문서

| 문서 | 참조 내용 |
|------|----------|
| `docs/db-schema.md` | 전체 테이블 스키마, 버전 이력, Sheets 대응 |
| `docs/architecture.md` | 동기화 프로토콜 4단계, 데이터 흐름, AI 인사이트 흐름 |
| `docs/features.md` | 완료/백로그 체크리스트 |
| `docs/build-debug.md` | StateNotifier 비동기 초기화 함정, GoRouter refreshListenable 함정 |
