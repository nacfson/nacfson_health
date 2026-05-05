# v12-3 변경 로그 — UI/UX HIGH 7건

> 작성: 2026-05
> DB 버전: v12 (변경 없음 — UX 폴리싱)

## 배경

v12-2 audit 직후 사용자 요청으로 5탭 메인 화면 / 입력 폼 / 차트·테마 영역의 UX 단차를 3개 Explore agent 병렬 조사 (65건 식별) → HIGH 7개 카테고리만 본 라운드에 처리. v12-2 가 "현 패턴 일관 처리, 추가 헬퍼 신설은 over-engineering" 으로 close 한 영역과 인접한 항목 (로딩 상태 spinner) 은 동기 List Provider 한정으로 진행 — `xxxRecordsInitialLoadingProvider` 추가는 audit 의 AsyncValue Provider 영역과 다른 layer.

DB 스키마 변경 없으므로 v12-2 → v12-3 패치 릴리즈.

---

## 변경 요약 (한 줄 요약 7건)

1. **PR 1 — 다크 모드 색상 토큰 정리**: `app_theme.dart` 에 매크로 라벨 토큰 (`macroCarbsFg`/`macroProteinFg`/`macroFatFg`) 신설, 7개 위젯의 `Colors.white/deepOrange/orange/blue[400]/yellow[700]/amber.shade700` 하드코딩을 `AppTheme.warnFg`/`catDiet`/`onInverseSurface` 등 헬퍼로 교체.
2. **PR 2 — 입력 검증 메시지 친절화**: validator 에러 메시지에 현재 입력값과 권장 범위를 명시 (예: `'0~9999 사이 값을 입력해주세요 (입력: -50)'`). `diet_form` 칼로리·탄단지, `inline_set_input` 중량·반복·RPE, `onboarding_screen` 키 검증.
3. **PR 3 — 터치 타겟 44x44 보장**: `diet_record_card` 템플릿 등록 IconButton constraints 32→44, `summary_screen` 정보 아이콘·AI 새로고침을 `GestureDetector`→`IconButton(tooltip)` 교체, `weight_screen` "오늘 기록 추가" 를 `InkWell + minHeight 44` 로 변경.
4. **PR 4 — DietForm swipe-down 손실 경고**: `_DietFormState`→`DietFormState` public 화 + `bool get isDirty` getter (신규 모드: 입력 1자라도 / 수정 모드: 초기값 비교). `diet_screen` add/edit 시트 호출처에 `GlobalKey<DietFormState>` + `_confirmDiscardIfDirty`. `RecordFormSheet.onConfirmClose` API 는 v12-2 에서 이미 도입.
5. **PR 5 — 콜드 스타트 로딩 spinner**: `exerciseRecordsInitialLoadingProvider`/`dietRecordsInitialLoadingProvider`/`weightRecordsInitialLoadingProvider` (StateProvider) + `dailySummaryInitialLoadingProvider` (derived). Notifier 들이 `Ref` 받아 `_loadRecords()` 끝에 false 로 set. 4개 화면이 `isInitialLoading && isEmpty` 시 `CircularProgressIndicator` 노출 → 빈 리스트 vs 로딩 중 시각 구분.
6. **PR 6 — NumericStepperField 신규**: `lib/shared/widgets/numeric_stepper_field.dart` — 좌우 ± `IconButton` + 가운데 `TextField`, long-press 100ms 가속, `min`/`max` 클램프(한계 도달 시 ± 자동 비활성), `step`·`integer`·`suffix` 옵션. `inline_set_input` kg(0.5)/회(1)/RPE(0.5) 적용 — 기존 `_NumField` 제거. `weight_form` 은 fontSize 32 큰 폰트 유지 위해 별도 `_LargeStepperButton` ±0.1kg.
7. **PR 7 — 식단 삭제 SnackBar Undo (5초)**: `DietNotifier` 에 `softDelete(uuid)`/`restoreSoftDelete(uuid)`/`commitAllPending()` + `_pendingDeletes` 캐시 + 5초 `Timer` 보관. `diet_screen` 의 swipe delete 가 `softDelete` 호출 + `showAppSnackBar('삭제됨 · $name', action: SnackBarAction(label: '되돌리기'))`. **사고 방지 가드**: `SyncStateNotifier.performSync()` 진입 직전 `_dietNotifier.commitAllPending()` 강제 호출 → 5초 윈도우에 걸친 pending delete 가 sync push 에서 누락되지 않음.

---

## 범위 조정 (운동 도메인 Undo 보류)

`exercise_record_card` 의 swipe delete 도 같은 패턴 적용 검토했으나, `ExerciseNotifier.deleteSetAndRenumber` 가 단일 세트 삭제 후 같은 운동·같은 날짜 세트들의 `currentSet` 을 timestamp 순 1..N 으로 일괄 재부여한다. SnackBar Undo 로 복원하려면 renumber 도 reverse (모든 세트의 currentSet 을 원본으로 복원, 각각 `_repository.update`) 해야 함. 부분 실패 시 set 번호가 깨질 위험 → 이번 라운드 보류, 운동 도메인 전용 설계로 분리.

운동 카드 swipe delete 는 기존 `confirmDismiss` 다이얼로그 유지. 식단 카드만 본 라운드에서 SnackBar Undo 적용.

---

## RPE chip 안 적용 (계획 변경)

원안 plan 에서 RPE 1~10 을 만족도 별점 5개와 일관되게 chip 선택 UI 로 대체할 계획이었으나, `inline_set_input` 의 한 줄 레이아웃 (`[세트타입][kg][회][RPE][✓][✗]`) 에 chip 10개는 들어가지 않음. RPE 도 `NumericStepperField` (step 0.5, min 1, max 10) 로 통일 — 별점 일관성보다 입력 흐름 연속성 우선.

---

## 잠재 리스크 / 회귀 가드

1. **PR 5 race condition**: `isInitialLoading == true` 인 동안 사용자가 + 버튼으로 `addRecord` 호출 가능. 가능성은 매우 낮음 (SQLite getAll() 은 수십~수백 ms). Notifier 큐잉 안 함 — 발생 시 두 번째 state set 이 첫 번째를 덮을 뿐 데이터 손실은 없음.
2. **PR 7 Sync 동시성**: `performSync()` 진입 직전 `commitAllPending()` 호출이 핵심 가드. 사용자가 swipe→Undo 5초 윈도우 내에 sync 가 트리거되면 5초 기다리지 않고 즉시 commit → SnackBar action 은 이후 무동작 (`_pendingDeletes` 비어 있어 `restoreSoftDelete` 가 early return). 사용자에게 알리지 않으면 혼동 가능 — 다만 sync 는 일반 사용 흐름에서 자주 발생 안함 (수동 트리거 + auth 콜백). 차후 사용자 신고 시 메시지 갱신 검토.
3. **PR 6 RPE 입력**: 작은 IconButton 36x44 — 손가락 큰 사용자 미세 조정 시 오탭 위험. 사용자 피드백 후 step 단위 조정 또는 chip 으로 전환 검토.
4. **PR 1 신규 토큰 hex 임의값**: `colorMacroProteinFg/Dark`, `colorMacroFatFg/Dark` 의 hex 는 디자인 시스템 정식 정의 없이 결정. 디자이너 review 권장.
5. **DietForm public 화**: `_DietFormState`→`DietFormState` 는 단순 rename, 외부 직접 참조 없으므로 안전. `WeightFormState` 와 동일 패턴.

---

## 본 라운드 제외 (별도 라운드 후보)

- **MED**: FAB 숨김 시 사용자 피드백 (과거 날짜), DateNavigationBar 주/월 점프, Empty 상태 톤 통일, GestureDetector→IconButton 추가 마이그레이션, 반응형 (큰 화면 max width)
- **LOW**: 탭 재선택 시 스크롤 톱, BorderRadius 표준화, 타이포그래피 토큰화 (AI 인사이트 카드 / coach_chat_sheet / weight_screen 의 직접 fontSize), AI 인사이트 빈 응답 분기

위 항목은 사용자 영향이 직접적이지 않거나 디자인 변경이 큰 영역. v13 또는 별도 폴리싱 라운드에서 묶음 처리.

---

## 변경 파일 (24개)

### 신규 (1)
- `lib/shared/widgets/numeric_stepper_field.dart`

### 수정 — Theme (1)
- `lib/core/theme/app_theme.dart` — 매크로 토큰 3쌍 + helper 3개

### 수정 — Diet (5)
- `lib/features/diet/presentation/widgets/diet_form.dart` — DietFormState public + isDirty + 검증 메시지 + 매크로 라벨 (선택)
- `lib/features/diet/presentation/widgets/diet_record_card.dart` — IconButton constraints 44
- `lib/features/diet/presentation/widgets/calorie_trend_chart.dart` — `Colors.deepOrange` → `catDiet`
- `lib/features/diet/presentation/widgets/analysis_result_sheet.dart` — `Colors.orange` 4곳 → `warnFg/warnBg`
- `lib/features/diet/presentation/screens/diet_screen.dart` — swipe-down 가드 + 로딩 분기 + softDelete + Undo SnackBar
- `lib/features/diet/presentation/providers/diet_provider.dart` — Ref 주입 + isInitialLoadingProvider + softDelete/restore/commitAllPending

### 수정 — Exercise (3)
- `lib/features/exercise/presentation/widgets/inline_set_input.dart` — 검증 메시지 + NumericStepperField 적용
- `lib/features/exercise/presentation/screens/exercise_screen.dart` — 로딩 분기
- `lib/features/exercise/presentation/providers/exercise_provider.dart` — Ref 주입 + isInitialLoadingProvider

### 수정 — Weight (4)
- `lib/features/weight/presentation/widgets/weight_form.dart` — `Colors.amber.shade700` → `warnFg`, ±0.1kg `_LargeStepperButton`
- `lib/features/weight/presentation/widgets/weight_chart_card.dart` — 툴팁 `Colors.white` → `onInverseSurface`
- `lib/features/weight/presentation/screens/weight_screen.dart` — InkWell minHeight 44 + 로딩 분기
- `lib/features/weight/presentation/providers/weight_provider.dart` — Ref 주입 + isInitialLoadingProvider

### 수정 — Summary (2)
- `lib/features/summary/presentation/screens/summary_screen.dart` — 정보 아이콘·AI 새로고침 IconButton + 로딩 분기
- `lib/features/summary/presentation/providers/summary_provider.dart` — `dailySummaryInitialLoadingProvider`

### 수정 — Settings / Onboarding / Sync (4)
- `lib/features/settings/presentation/widgets/spreadsheet_status_card.dart` — 라이트 `Colors.orange[*]` 비대칭 해소
- `lib/features/settings/presentation/widgets/diet_target_card.dart` — 매크로 라벨 토큰화
- `lib/features/onboarding/presentation/screens/onboarding_screen.dart` — 키/체중 검증 톤 통일
- `lib/core/sync/sync_state.dart` — `performSync()` 진입 직전 `_dietNotifier.commitAllPending()` 가드

### Docs (4)
- `docs/changelog-v12-3.md` (신규)
- `docs/features.md` — v12-3 섹션 추가
- `docs/ui-architecture.md` — §4.5 NumericStepperField 행 추가
- `docs/conventions.md` — §2 매크로 라벨 컬러 가이드 추가
- `CLAUDE.md` — 참조 문서 목록에 v12-3 등록
