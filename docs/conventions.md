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
- **테마 파일**: `lib/core/theme/app_theme.dart` — `lightTheme` + `darkTheme` 양쪽 정의 필수
- **테마 모드 전환**: `themeModeProvider` (`StateNotifierProvider<ThemeModeNotifier, ThemeMode>`) — `system`/`light`/`dark` 3-way, `SyncPreferences.themeModeRaw`에 영구 저장 (직접 `SharedPreferences` 호출 금지)
- **다크 잔여 흰색 금지**: glassmorphic NavBar, TriRing 트랙(다크 22% / 라이트 12%), AI 인사이트 카드, BMI 바, 차트 목표선, Autocomplete 드롭다운 등은 반드시 `Theme.of(context).colorScheme` 토큰을 경유 — 하드코딩 흰색 금지
- **ChipTheme.labelStyle 색상 필수**: `ChipThemeData.labelStyle`에는 반드시 `color`를 지정 (`chipFg` 토큰 또는 `colorScheme.onSurface`). 생략 시 Material 3 기본값이 배경과 충돌해 라이트 테마에서 흰색으로 표시되는 버그 발생. `ActionChip`/`ChoiceChip`에서 `labelStyle`을 재정의할 때도 반드시 `color`를 함께 명시
- **위젯에서 색상 참조 원칙 (2026-04 강화)**:
  - 위젯 빌드 함수에서는 반드시 **`Theme.of(context).colorScheme`** 토큰을 사용 (`cs.surface`, `cs.onSurface`, `cs.onSurfaceVariant`, `cs.outlineVariant`, `cs.surfaceContainerHighest`, `cs.error`, `cs.onPrimary` 등)
  - `AppTheme.colorBg / colorSurface / colorText* / colorHairBorder` 라이트 전용 static 상수는 **`AppTheme.lightTheme`/`darkTheme` 정의부(app_theme.dart) 내부에서만** 참조 — 위젯 코드에서 직접 사용 금지
  - 브랜드 포인트 컬러(민트/산호/카테고리 등)가 필요할 때는 `AppTheme.catDiet(context)` / `catSleep(context)` / `lunchTint(context)` / `snackTint(context)` / `warnBg(context)` / `warnFg(context)` 헬퍼 사용 — 내부에서 brightness 분기 자동 처리
  - `Colors.white` / `Colors.red` 등 직접 참조는 **의도적 브랜드 유지**(navy 히어로 내부 텍스트 등)에 한해 허용. 일반 강조/오류 표시는 `cs.error`, `cs.onPrimary`, `cs.onInverseSurface` 사용
  - `const TextStyle(color: AppTheme.*)` 패턴은 금지 — `TextStyle`의 `const`를 제거하고 `cs.*`를 주입

---

## 3. 폰트 규칙

- **기본 폰트**: Pretendard (Regular 400 / Medium 500 / SemiBold 600 / Bold 700)
- **위치**: `assets/fonts/Pretendard-*.ttf` — `pubspec.yaml`의 `flutter.fonts` 섹션에 등록
- **이유**: 한글 가독성 + 숫자/영문 일관성 (Roboto/SF 혼용 시 베이스라인 불일치)
- **사용**: `ThemeData.fontFamily: 'Pretendard'` (`app_theme.dart`) — 위젯 단위에서 별도 지정 금지

---

## 3-1. 운동 도메인 규칙

- **볼륨 공식**: `weight × reps` (세트 번호는 표시용이며 볼륨 계산에 포함하지 않음). v8 이전에는 `weight × reps × currentSet`이었으나 정정됨.
- **세트 번호 자동 관리**: UI/Provider 레벨에서 직접 입력하지 않음.
  - 추가: `ExerciseNotifier.addSetAutoNumber` — 같은 운동/같은 날짜의 max(currentSet) + 1
  - 삭제: `ExerciseNotifier.deleteSetAndRenumber` — 삭제 후 timestamp 순으로 1..N 재부여 (수정된 row는 자동 modified)
- **루틴 = 오늘 카드 컨테이너 (v9+)**:
  - 오늘 탭의 운동 카드는 `daily_routine` 항목을 기준으로만 렌더링된다 (`todayExerciseCardsProvider`). 루틴에 없는 운동은 카드로 표시되지 않는다.
  - 세트 저장(`InlineSetInput._submit`) 시점에 `RoutinePlannerNotifier.addItem` 이 자동 호출되어 같은 이름이 없으면 루틴에 편입된다 (중복은 무시).
  - 앱 로드 시 `RoutinePlannerNotifier._load` 가 기록은 있지만 루틴에 없는 운동을 자동 편입(self-heal)한다 — 이번 리팩터링 이전 데이터 보정용.
  - "운동 제거" 메뉴(`ExerciseGroupCard`)는 `daily_routine` 항목 + 선택 날짜의 `exercise_records` 를 함께 soft delete. 기록이 있으면 확인 다이얼로그 경유.
  - 루틴(`daily_routine`)은 로컬 전용이라 자유롭게 수정 가능. `workout_routines` 프리셋은 여전히 Supabase LWW.

---

## 4. Bottom Sheet 사용 규칙

- **상태 관리**: `lib/core/providers/sheet_state_provider.dart`의 `openSheet()` 헬퍼 사용 — `showModalBottomSheet`/`showDialog` 직접 호출 금지
- **토글 동작**: 동일 타입 호출 시 토글(열려있으면 닫기), 타 타입 호출 시 기존 창 교체
- **FAB 자동 숨김**: `bottom_nav_shell.dart`의 `_showFab`는 `activeSheetProvider`를 watch — 별도 setState/Notifier 불필요
- **반응형 너비**: 데스크톱/웹 대응을 위해 `ConstrainedBox` 최대 너비 **600px** 제한
- **배치**: `Align(alignment: Alignment.bottomCenter)` — 넓은 화면에서도 하단 중앙
- **컨테이너**: `RecordFormSheet` — `DraggableScrollableSheet` 기반, `initial 0.85 / min 0.45 / max 0.95`
- **스크롤 일원화**: 시트 내부 폼은 외부 `scrollController`(DraggableScrollableSheet 제공)에 연결 — 중첩 ScrollView 금지
- **키보드 대응**: `DraggableScrollableSheet`가 자동 처리 (별도 `MediaQuery.viewInsets` 계산 불필요)

---

## 5. 탭 전환 규칙

- 하단 네비게이션 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- Shell Navigator + Root Navigator 모두 `popUntil(isFirst)` 호출

---

## 6. 예외 처리 의무

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

## 7. 문서 업데이트 의무

- 기능 추가/변경 시 관련 문서 즉시 동기화
- DB 테이블 변경 → `docs/db-schema.md` 업데이트 필수
- 기능 완료 → `docs/features.md` 체크박스 반영 필수
- 실수 발생, 같은 코드 수정 반복 시 → 관련 docs 가이드라인에 하네스 프롬프트 추가

---

## 8. 기존 코드 재사용

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
