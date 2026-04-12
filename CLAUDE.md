# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요
- **목표**: 구글 폼/시트 대체 개인 맞춤형 피트니스 & 식단 통합 대시보드
- **SDK**: Dart ^3.11.4, Flutter
- **플랫폼**: iOS, Android, macOS, Windows, Linux, Web
- **UX 원칙**: 입력은 폼보다 빠르고 단순하게, 결과 시각화는 시트보다 직관적으로

---

## 핵심 패키지

| 패키지 | 버전 | 용도 |
|--------|------|------|
| flutter_riverpod | ^2.6.1 | 상태 관리 (StateNotifier + Provider) |
| go_router | ^14.8.1 | 라우팅 (ShellRoute, rootNavigatorKey) |
| sqflite | ^2.4.2 | 로컬 SQLite DB |
| googleapis / googleapis_auth | ^14.0.0 / ^1.5.0 | Google Sheets API + OAuth |
| google_sign_in | ^6.2.0 | Google 로그인 |
| shared_preferences | ^2.3.0 | spreadsheetId, lastSyncTimestamp 저장 |
| uuid | ^4.5.1 | UUID v4 생성 |

---

## 개발 명령어

```bash
flutter pub get                    # 의존성 설치
flutter analyze                    # 정적 분석 (lint check)
flutter test                       # 전체 테스트
flutter test test/widget_test.dart # 단일 테스트 파일
flutter run                        # 실행 (디바이스 선택)
flutter run -d <device_id>         # 특정 디바이스에서 실행
flutter build apk                  # Android APK 빌드
flutter build ios                  # iOS 빌드
flutter build web                  # Web 빌드
```

---

## 아키텍처 개요

### 데이터 흐름
```
UI → Provider (StateNotifier) → Repository (interface) → SQLite 구현체
                                                          ↓
                                              SyncService (Background)
                                                          ↓
                                                   Google Sheets API
```

### 앱 진입점 패턴
`main.dart`에서 `SharedPreferences`를 초기화 후 `ProviderScope`의 `overrides`로 주입한다.
`syncPreferencesProvider`는 기본값이 `UnimplementedError`이므로 반드시 오버라이드해야 한다.
앱이 `AppLifecycleState.resumed` 상태가 될 때 `_triggerSync()`가 자동 호출된다(Google 연동 + spreadsheetId 존재 시).

### 모듈 구조 (도메인 기반)

| 도메인 | Entity | Repository | Provider |
|--------|--------|------------|----------|
| exercise | ExerciseRecord | ExerciseRepository + SqliteExerciseRepository | ExerciseNotifier, todayExerciseRecordsProvider, todayExerciseGroupedProvider, todayTotalVolumeProvider |
| diet | DietRecord | DietRepository + SqliteDietRepository | DietNotifier, todayDietRecordsProvider, todayDietGroupedProvider, todayDietSummaryProvider |
| summary | DailySummary | - | dailySummaryProvider |
| sync | - | - | syncStateProvider, isSyncingProvider, isSignedInProvider, currentAccountProvider |

### 핵심 파일
| 파일 | 경로 | 설명 |
|------|------|------|
| DatabaseHelper | `lib/core/database/database_helper.dart` | sqflite 싱글톤, DB v2 (`nacfson_health.db`) |
| app_router | `lib/core/router/app_router.dart` | go_router 설정, ShellRoute로 하단 네비게이션, rootNavigatorKey |
| BottomNavShell | `lib/shared/widgets/bottom_nav_shell.dart` | 4탭 (운동/식단/요약/설정) 네비게이션 쉘 |
| RecordFormSheet | `lib/shared/widgets/record_form_sheet.dart` | Bottom Sheet 컨테이너 — 슬라이드+페이드 애니메이션, 키보드 패딩, 최대 너비 600px |
| ErrorOverlay | `lib/shared/widgets/error_overlay.dart` | 오류/정보 메시지 오버레이 (자동 닫기, 페이드 애니메이션) |
| EmptyState | `lib/shared/widgets/empty_state.dart` | 공통 빈 상태 위젯 |
| sheet_state_provider | `lib/core/providers/sheet_state_provider.dart` | `activeSheetProvider` + `openSheet()` 헬퍼 (토글/교체 로직 포함) |
| ExerciseRecord | `lib/features/exercise/domain/entities/exercise_record.dart` | Entity + SyncStatus enum |
| DietRecord | `lib/features/diet/domain/entities/diet_record.dart` | Entity + SyncStatus enum |
| ExerciseForm | `lib/features/exercise/presentation/widgets/exercise_form.dart` | 운동 기록 입력 폼 |
| DietForm | `lib/features/diet/presentation/widgets/diet_form.dart` | 식단 기록 입력 폼 |
| ExerciseRecordCard | `lib/features/exercise/presentation/widgets/exercise_record_card.dart` | 운동 기록 카드 (Dismissible, 수정/삭제) |
| DietRecordCard | `lib/features/diet/presentation/widgets/diet_record_card.dart` | 식단 기록 카드 (Dismissible, 매크로 게이지) |
| GoogleAuthService | `lib/core/sync/google_auth_service.dart` | OAuth 인증 (googleapis_auth + AccessTokenCredentials) |
| GoogleSheetsService | `lib/core/sync/google_sheets_service.dart` | Sheets API (batch push, delta pull) |
| SyncPreferences | `lib/core/sync/sync_preferences.dart` | SharedPreferences 래퍼 — spreadsheetId, lastSyncTimestamp |
| sync_state | `lib/core/sync/sync_state.dart` | Riverpod providers + SyncStateNotifier + `_syncAll()` 내부 함수 |
| SpreadsheetStatusCard | `lib/features/settings/presentation/widgets/spreadsheet_status_card.dart` | 스프레드시트 연동 상태 카드 |

---

## Entity 스키마 (v2 - 동기화 메타데이터)

### 공통 필드
| 필드 | 타입 | 설명 |
|------|------|------|
| id | int? | LOCAL ONLY — 시트 연동 시 사용 금지 |
| uuid | String | 글로벌 PK (UUID v4). 빈 문자열 전달 시 Repository에서 자동 생성 |
| timestamp | DateTime | 생성 시간 (unix ms) |
| updatedAt | DateTime | 수정 시간 (충돌 해결 LWW 기준, unix ms) |
| syncStatus | SyncStatus | 0=synced, 1=created, 2=modified, 3=deleted |

### ExerciseRecord 도메인 필드
`exerciseType` (가슴/등/하체/어깨/팔/코어/유산소/기타), `exerciseName`, `currentSet`, `weight`, `reps`, `rpe`
- 계산 프로퍼티: `volume = weight * reps * currentSet`
- `todayExerciseGroupedProvider` 표시 순서는 위 typeOrder 고정값 기준

### DietRecord 도메인 필드
`mealType`, `foodName`, `totalCalories`, `carbs`, `protein`, `fat`, `satisfaction`, `memo` (nullable)

### SyncStatus enum
```dart
enum SyncStatus {
  synced(0),    // 시트와 동일
  created(1),  // Insert 필요
  modified(2), // Update 필요
  deleted(3);  // Soft Delete
}
```
`SyncStatus` enum은 `exercise_record.dart`와 `diet_record.dart`에 각각 별도로 정의됨 (공유 파일 없음 — 의도적 설계).

---

## 테마

- `AppTheme.lightTheme` — Material 3, `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`
- CardTheme: elevation=2, radius=12 (카드 위젯에서 별도 스타일 불필요)
- InputDecoration: `OutlineInputBorder(radius=8)` + `filled: true`

---

## 주요 규칙

### Repository 패턴
- 항상 인터페이스 (`ExerciseRepository`)를 먼저 참조하고, 구현체 (`SqliteExerciseRepository`)로 주입
- Sync 관련 메서드: `getPendingSync()`, `markAsSynced()`, `mergeRemoteRecords()`, `hardDeleteSyncedDeleted()`
- **UUID 자동 생성**: `ExerciseRecord(uuid: '')` 처럼 빈 문자열을 전달하면 `SqliteExerciseRepository.add()`에서 UUID v4를 자동 할당
- **DB 네이밍**: SQLite 컬럼은 snake_case(`exercise_type`), Dart Entity는 camelCase(`exerciseType`)로 Repository가 매핑

### Bottom Sheet 패턴
`openSheet()` 함수(`sheet_state_provider.dart`)를 통해 Bottom Sheet를 열 것.
- 같은 타입을 다시 호출하면 닫힘(토글)
- 다른 타입이 이미 열려 있으면 먼저 닫고 새로 열림
- `RecordFormSheet` 위젯으로 내용을 감싸면 애니메이션·키보드 패딩·최대 너비가 자동 적용됨

### UI 규칙
- Bottom Sheet 최대 너비 600px (`ConstrainedBox`)
- 키보드 대응: `SingleChildScrollView` + `MediaQuery.of(context).viewInsets.bottom`
- 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- `print` 대신 `debugPrint` 사용 (`avoid_print` lint)

### 오류 가시화 규칙 (필수)
오류가 발생할 수 있는 **모든** 작업은 반드시 사용자가 즉시 식별할 수 있는 UI 피드백을 제공해야 한다.

**대상 작업 (예외 없이 적용)**
- DB 작업: `insert`, `update`, `delete`, `query` 등 sqflite 호출
- 동기화 작업: Google Sheets push/pull, OAuth 인증, 토큰 갱신
- 폼 제출: 운동/식단 기록 저장, 수정, 삭제
- SharedPreferences 읽기/쓰기

**구현 방법**
```dart
// Provider (StateNotifier) 에서 오류 발생 시 → ErrorOverlay 표시
try {
  await _repository.add(record);
} catch (e, st) {
  debugPrint('$e\n$st');
  // 반드시 UI에 전달
  ref.read(errorOverlayProvider.notifier).show('저장 실패: $e');
  return; // 또는 상태를 에러로 전환
}
```

**오류 표시 계층 (심각도에 따라 선택)**
| 심각도 | 방법 | 사용 시점 |
|--------|------|----------|
| 낮음 | `ErrorOverlay` (자동 닫힘) | 동기화 실패, 네트워크 오류 등 복구 가능 |
| 중간 | `SnackBar` | 폼 저장 실패 등 사용자 액션 결과 |
| 높음 | `AlertDialog` | DB 열기 실패, 데이터 손상 등 치명적 오류 |

**금지 사항**
- `catch (e) { debugPrint(e.toString()); }` 만 하고 UI 피드백 없이 끝내는 것
- 오류를 무시하고 빈 화면이나 빈 리스트를 보여주는 것
- `try/catch` 없이 `await` DB/네트워크 호출을 하는 것

### Summary 하드코딩 값
`dailySummaryProvider`(`summary_provider.dart`)의 목표치는 현재 하드코딩:
- 목표 칼로리: 1800 kcal
- 탄수화물: 250g / 단백질: 150g / 지방: 60g

### Google Sheets 연동
- 인증: `GoogleAuthService` (googleapis_auth + AccessTokenCredentials)
- 시트 구조: Sheet1=`exercise_records`, Sheet2=`diet_records`
- 동기화 흐름: Push (로컬→시트) → Pull (시트→로컬, LWW 병합) → Hard Delete → Timestamp 갱신
- `syncPreferencesProvider`는 `main.dart`의 `ProviderScope.overrides`에서 반드시 주입

---

## 문서 위치

| 문서 | 경로 |
|------|------|
| 비즈니스 아키텍처 | `docs/architecture.md` |
| UI/네비게이션 아키텍처 | `docs/ui-architecture.md` |

---

## 문서 관리 규칙

> **중요**: 작업 완료 시 반드시 관련 md 파일을 업데이트

- 코드 변경 시 `CLAUDE.md`의 핵심 파일 테이블, 데이터 흐름 즉시 업데이트
- UI/UX 변경 시 `docs/ui-architecture.md` 관련 섹션 즉시 업데이트
- 완료된 기능은 TODO에서 ✅ 체크박스로 표시
