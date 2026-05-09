# v12-4 변경 로그 — InlineSetInput 폭 회귀 hot-fix

> 작성: 2026-05-09
> DB 버전: v12 (변경 없음 — UX hot-fix)

## 배경

v12-3 PR6 에서 `inline_set_input` 의 kg/회/RPE 입력을 모두 `NumericStepperField`(좌우 ± 버튼 + TextField) 로 통일한 결과, 한 행 `Row` 의 고정 폭(약 406 px)이 좁은 화면(iPhone 13 mini = 375pt) 의 카드 가용 폭(~335 px)을 초과. `Expanded` TextField 들이 0 폭 근처로 압축되며 인접한 ± 버튼들만 붙어 보여 사용자에겐 *"+ - + - 가 두 개씩 나오는"* 시각 버그로 인지됨.

사용자 보고:
> "현재 운동 루틴에 있는 것에서 값을 추가할려고 클릭을 하게 되면 여러 UI가 겹쳐 나와서 값을 넣을 수 없는 구조"
> "정확한 문제는 루틴에서 값을 추가할 때 + - + - 가 두 개 나오는 것 같음"

v12-3 changelog "잠재 리스크 §3" 의 *"작은 IconButton 36x44 — 손가락 큰 사용자 미세 조정 시 오탭 위험"* 이 좁은 화면에서 입력 불능 회귀로 드러난 케이스. 1차로 ± 32 + IconButton 36 + SetTypeSelector 44 로 폭을 줄였으나 여전히 ~11 px 부족 → 2행 레이아웃으로 근본 해결.

DB 스키마 변경 없으므로 v12-3 → v12-4 패치 릴리즈.

---

## 변경 요약

### 1. InlineSetInput 2행 레이아웃 (근본 해결)

`lib/features/exercise/presentation/widgets/inline_set_input.dart` 의 `build()` 를 한 행 → 두 행으로 재구성.

**Before (한 행, 폭 ≈ 406 px 필요)**:
```
[세트타입] [- kg +] [- 회 +] [- RPE +] [✓] [✗]
```

**After (두 행, 어떤 폭에서도 안전)**:
```
[세트타입]                              [✓ 저장] [✗ 닫기]
[- kg +]      [- 회 +]      [- RPE +]
```

- 첫 줄: `Spacer()` 로 좌(타입 선택) / 우(저장·닫기) 분리. IconButton 두 개는 표준 터치 타겟 `minWidth: 44, minHeight: 44` 로 복원 (1차 fix 의 36 보다 정석).
- 둘째 줄: `Expanded` 3개로 NumericStepperField 균등 분배. 카드 가용 폭 335 px 기준 각 칸 약 105 px → ± 32 × 2 = 64 px + TextField 41 px → 라벨(`kg`/`회`/`RPE`) + 숫자 표시 충분.
- 세로로 한 줄 늘어나지만(약 56 px → 112 px), 카드 안의 ListView 가 `shrinkWrap: true` 이므로 부모 `CustomScrollView` 가 자동 스크롤 흡수. v12-3 PR3 의 세로 터치 타겟 44 규칙 유지.

### 2. 1차 fix 변경 유지

다음은 다른 사용처에서도 안전하므로 그대로 둠 (보너스 폭 여유):

- `lib/shared/widgets/numeric_stepper_field.dart:179` — `_StepperButton.constraints` `minWidth: 36 → 32`
- `lib/features/exercise/presentation/widgets/inline_set_input.dart` `_SetTypeSelector.constraints` `minWidth: 52 → 44`, padding `horizontal 6 → 4`
- `initState` 의 `addPostFrameCallback` 에 `Scrollable.ensureVisible(alignment: 0.5, 300ms)` — 카드가 화면 하단 가까이 있을 때 키보드와 입력 행이 겹치지 않도록 부모 `CustomScrollView` 자동 스크롤 보장

---

## 검증

- iPhone 13 mini 375 pt 가용 폭 335 px 기준 — 두 줄 어느 쪽도 overflow 없음
- 각 NumericStepperField 의 TextField 가 충분한 폭(>40 px) 으로 라벨·숫자 표시
- ± 버튼이 인접한 다른 NumericStepperField 의 버튼과 시각적으로 붙어 보이지 않음
- `flutter analyze` clean (No issues found)
- 기능 회귀 없음: `_submit()` 검증 메시지(v12-3 PR2), 휴식 타이머 자동 시작, 연속 입력 후 _weightFocus 복귀 모두 그대로

---

## 사용자 재빌드 안내

Flutter / Xcode 빌드 캐시가 stale 일 가능성이 있어, 적용 안 보이면 다음 순서로 재빌드 권장:

```bash
flutter clean
cd ios && pod install && cd ..
flutter run -d <device-udid>
```

또는 Xcode 에서 `Product → Clean Build Folder` (⇧⌘K) 후 Run.

---

## 잠재 리스크

1. **세로 공간 +56 px**: 카드가 약간 길어지지만 부모 CustomScrollView 가 자동 흡수. 1RM 칩이 있는 카드도 영향 없음.
2. **NumericStepperField ± 32 px**: 다른 사용처(weight_form 은 `_LargeStepperButton` 자체 구현이라 영향 없음, 즉 본 수정 영향 받는 곳은 InlineSetInput 만) 에 영향 없음. 향후 NumericStepperField 를 다른 좁은 컨테이너에서 쓸 때도 폭 여유가 더 생긴 것이라 안전.
3. **2행 레이아웃 시각 변화**: 사용자가 한 행에 익숙해 있다면 일시 적응 필요. 다만 한 행 레이아웃은 입력 불능 상태였으므로 사용성은 개선만.

---

## 본 라운드 제외

- `RecordFormSheet`, `weight_form` 등 다른 폼은 컬럼(세로) 레이아웃이라 영향 없음 — 손대지 않음.
- 미커밋 상태인 `template_picker_sheet.dart` (220 ms 딜레이) / `direct_routine_input_dialog.dart` (autofocus:false) 변경은 별도 진입점(FAB → 시트 → 직접 입력 다이얼로그) fix 로, 함께 커밋할지는 사용자 판단.

---

## 향후 검토

- `LayoutBuilder` 로 큰 화면(>=480 px) 에서는 다시 한 행 레이아웃으로 돌아가는 responsive 분기를 둘지 검토. 단순함을 위해 본 라운드는 모든 폭에서 2행 통일.
- `NumericStepperField` 자체에 `compact: bool` 옵션을 추가해 인라인 컨텍스트에서 ± 폭을 조절하도록 책임 분리.
