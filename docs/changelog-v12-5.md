# v12-5 변경 로그 — 칼로리 자동 계산 (Atwater)

> 작성: 2026-05-10
> DB 버전: v12 (변경 없음 — UX 개편, 컬럼 유지)

## 배경

v12-4 까지 식단 기록(`DietForm`) 과 음식 템플릿 추가 폼(`FoodTemplateCard` 추가 탭) 에서 사용자는 **칼로리(kcal)** 와 **탄단지(carbs/protein/fat)** 를 모두 별도 입력해야 했다.

문제:
1. **입력 부담** — 한 음식당 4개 숫자를 모두 채워야 하므로 빠른 기록이 어렵다.
2. **데이터 불일치 위험** — 사용자가 kcal 만 잘못 입력해도 검증 통과 (예: 탄 30g·단 20g·지 5g 인데 kcal 는 100 으로 오타). 매크로 합산과 저장된 kcal 가 어긋나 요약/차트가 부정확.
3. **AI 분석 / 템플릿 picker** 도 kcal 와 매크로를 모두 채워주지만, 출처별로 산출 방식이 달라 사용자가 보는 값이 일관되지 않음.

영양학적으로 kcal 은 매크로에서 결정된다 (Atwater 계수: 탄 4 / 단 4 / 지 9 kcal/g). 이를 직접 적용해 **kcal 입력란을 제거하고, 매크로에서 자동 계산되는 read-only 미리보기로 대체**한다.

DB 스키마 변경 없으므로 v12-4 → v12-5 패치 릴리즈.

---

## 변경 요약

### 1. Atwater 계산기 신규 (`lib/core/nutrition/atwater_calculator.dart`)

순수 함수 1개 — 호출부 어디서나 동일 결과 보장:

```dart
int kcalFromMacros(double carbs, double protein, double fat) {
  if (!carbs.isFinite || !protein.isFinite || !fat.isFinite) return 0;
  if (carbs < 0 || protein < 0 || fat < 0) return 0;
  return (carbs * 4 + protein * 4 + fat * 9).round();
}
```

비유한값(NaN/Infinity)·음수는 0 으로 안전 변환한다. 호출부 validator·inputFormatter 가 1차 차단하지만, 외부 키보드/복붙·미래 호출자 보호를 위해 함수 자체에서도 이중 방어. 단위 테스트 9건 (`test/core/nutrition/atwater_calculator_test.dart`) — 정상 6 + NaN/Infinity/음수 가드 3.

### 2. `DietForm` 칼로리 입력란 제거

- `_caloriesController` 필드 + 5곳의 set/clear 호출 제거.
- 칼로리 `TextFormField` 블록 (이전 340~353행) 통째 제거.
- 매크로 3개 `TextFormField` 에 `onChanged: (_) => setState(() {})` 추가 → 라벨 즉시 갱신.
- 매크로 Row 아래에 `_KcalPreview` 위젯 추가 — `자동 계산 (탄·단×4 + 지×9): 245 kcal` 형태로 `cs.primaryContainer` 배경 + `cs.primary` 텍스트.
- `_submit()` 에서 `kcalFromMacros(carbs, protein, fat)` 로 산출하여 `total_calories` 컬럼에 저장.
- `_applyRecord` (최근 식사 칩) / `_applyAnalysis` (AI 사진 분석) / `_openTemplatePicker` (음식 템플릿 picker) 의 kcal 컨트롤러 set 호출 모두 제거 — **외부 출처의 kcal 값을 무시하고 항상 매크로에서 재계산**. 일관 규칙 우선.
- `isDirty` getter 의 calories 비교 제거. (수정 모드에서 매크로만 dirty 추적)

### 3. `FoodTemplateCard` 추가 탭 칼로리 입력란 제거

- `_caloriesCtrl` 필드 + init/dispose 등록 제거.
- 추가 탭 폼에서 칼로리 `TextFormField` 제거 → 칼로리+탄수 Row 와 단백질+지방 Row 두 줄을 → **탄·단·지 한 줄 + kcal 미리보기 한 줄** 로 재구성.
- `onChanged` 로 라벨 갱신.
- `_addTemplate()` 에서 `kcalFromMacros(carbs, protein, fat)` 로 산출하여 `calories` 컬럼에 저장.
- 빈 이름 안내 문구 "음식 이름과 매크로(칼로리/탄·단·지)를 입력하세요." → "음식 이름과 매크로(탄·단·지)를 입력하세요. 칼로리는 자동 계산됩니다."

### 4. 검색 탭 ListTile subtitle (`food_template_card.dart` 290행) 은 변경 없음

과거에 등록된 템플릿의 `t.calories` 는 historical 값이라 그대로 표시. 신규 등록 시점부터는 자동 산출된 값이 들어가므로 일관성 자연 회복.

### 5. NumericStepperField / InlineSetInput 일관성 보강 (v12-4 hot-fix 후속)

InlineSetInput 의 폭 회귀를 막은 v12-4 hot-fix 에 이어, 라벨 잘림·suffix 정렬·자동 포커스 회귀를 함께 정리:

- **`NumericStepperField`**: `label` 을 optional 로 변경, `suffix` 파라미터를 `String` (suffixText) 대신 `Widget` 으로 받도록 변경 — 좁은 필드에서 `suffixText` 가 입력 텍스트 위에 겹쳐 보이는 회귀 차단. `showSteppers` 옵션 추가 (false 시 ± 버튼 제거 — 중량처럼 직접 타이핑이 일반적인 입력에 적용). ± 버튼 minWidth 32 → 28 px (터치 타겟 48 세로 유지).
- **`InlineSetInput`**: 필드 라벨을 NumericStepperField 의 floating label 대신 외부 `_LabeledField` 래퍼로 분리. Expanded 전체 폭을 라벨 영역으로 쓸 수 있어 "강도 (RPE 1-10)" 같은 긴 라벨도 잘리지 않음. flex 비율 1:2:2 (중량/횟수/RPE) 로 폭 안정. `_SetTypeSelector` minWidth 44 → 96, 한 글자(웜/본/드/실) → 풀 텍스트(웜업/본세트/드롭세트/실패) 노출. 첫 행 가용 폭이 넉넉하므로 가독성 우선.
- **`DirectRoutineInputDialog`**: `ExercisePickerField.autofocus` true → false. 다이얼로그 enter 애니메이션과 키보드 enter 가 겹쳐 칩 리스트가 입력창 위로 솟아 보이는 회귀 차단.
- **`TemplatePickerSheet`**: 검색창 시각 정렬 마이너 보강.

회귀 테스트: `test/features/exercise/numeric_stepper_field_rpe_test.dart` 4 케이스 (직접 입력 / ± step 0.5 클램프 / min 도달 시 ⊖ disabled / inputFormatter 차단).

### 6. 매크로 입력 방어 보강 (회귀 차단)

자기 audit 결과 v12-5 초기 설계에 다음 회귀 위험이 있었고 PR 마감 전 보강:

- **공백 입력 → FormatException**: `_submit` 가 `text.isEmpty` 만 보고 `double.parse` 호출 → 공백만 입력("   ") 시 unhandled exception. `double.tryParse(text.trim()) ?? 0` 으로 안전화.
- **NaN/Infinity 통과**: validator 가 `n < 0` 만 검증 → `double.tryParse("NaN")` 통과 후 Atwater `.round()` 폭발. validator 에 `!n.isFinite` 가드 + `inputFormatters: FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))` 로 외부 키보드/복붙 차단. atwater 함수에도 함수 자체 가드 추가 (위 §1).
- **`_KcalPreview` overflow**: Row 안 raw Text 두 개 + Icon 이 좁은 화면(SE2)·시스템 큰 글자(textScaleFactor 1.5+) 에서 RenderFlex overflowed. 첫 Text 를 `Expanded` + `TextOverflow.ellipsis` 로 감싸고 `Semantics(label: '자동 계산된 칼로리 N 킬로칼로리')` 추가.

영향 파일: `lib/core/nutrition/atwater_calculator.dart`, `lib/features/diet/presentation/widgets/diet_form.dart`, `lib/features/settings/presentation/widgets/food_template_card.dart`.

---

## DB 변경 없음 (마이그레이션 없음)

- `diet_records.total_calories` / `food_templates.calories` 컬럼은 그대로 유지 (sync 호환·과거 기록 보존·요약 차트 영향 0).
- 저장 시점에 derived 값을 컬럼에 기록. 읽기 경로(요약·차트·식단 카드) 는 기존 그대로 컬럼 값을 사용 — 추가 작업 무.

---

## 디자인 결정 회고

**Q. 왜 컬럼을 제거하지 않았나?**
- v6 이전 기록은 사용자가 직접 입력한 kcal 가 매크로와 다를 수 있는 historical 값 — Atwater 로 재계산해버리면 과거 데이터를 변조하는 셈.
- 요약/차트/Supabase sync 가 모두 컬럼을 직접 읽으므로 derived getter 로 대체 시 영향 범위가 너무 넓음.
- 저장 시점에 자동 계산하는 것만으로 사용자 입력 단순화·신규 데이터 일관성 보장 둘 다 달성. 컬럼 유지가 가장 안전한 절충.

**Q. AI 사진 분석의 kcal 도 무시하는 게 맞나?**
- AI 가 추정한 kcal 와 매크로에서 Atwater 로 산출한 값이 다를 수 있다 (식이섬유/알코올 등 비-Atwater 요소 반영 가능).
- "칼로리는 매크로에 맞게 계산" 원칙을 지키려면 출처에 관계없이 일관 규칙 적용. 사용자가 보는 라벨 = 저장되는 kcal = Atwater(매크로). 두 값이 어긋나면 오히려 혼란.
- AI 분석 결과 카드 (`photo_analysis_card.dart`) 자체에서는 AI 의 kcal 추정값을 그대로 표시 (참고용). 폼에 적용하는 시점부터 매크로만 컨트롤러로 채워지고 kcal 라벨은 Atwater 결과.

**Q. 수정 모드 진입 시 기존 kcal 표시를 유지하지 않아도 되나?**
- 매크로를 컨트롤러에 채우면 `_KcalPreview` 가 그 매크로 기반 kcal 을 자동 표시. 과거에 잘못 저장된 kcal 가 있어도 저장 시 매크로 기반으로 재계산되므로 자연 보정.
- 사용자가 매크로를 손대지 않고 다른 필드(만족도/메모) 만 수정해도 저장 시 kcal 는 동일 매크로 기반 값으로 재기록 — 멱등.

---

## 영향 받는 파일

**신규**:
- `lib/core/nutrition/atwater_calculator.dart`
- `test/core/nutrition/atwater_calculator_test.dart`

**수정**:
- `lib/features/diet/presentation/widgets/diet_form.dart` — 칼로리 입력 제거, `_KcalPreview` 추가, `_submit` 에서 derived 사용
- `lib/features/settings/presentation/widgets/food_template_card.dart` — 추가 탭 칼로리 입력 제거, kcal 미리보기 추가, `_addTemplate` 에서 derived 사용
- `docs/db-schema.md` — `diet_records.total_calories` / `food_templates.calories` 의 처리 노트 갱신
- `docs/features.md` — v12-5 체크박스 추가
- `CLAUDE.md` — 참조 문서 목록에 `docs/changelog-v12-5.md` 등록

---

## 검증

- `flutter test test/core/nutrition/atwater_calculator_test.dart` — Atwater 단위 테스트 6건 모두 PASS
- `flutter analyze` — 본 작업 관련 신규 issue 0건
- 수동 시나리오: 식단 신규 추가 / AI 분석 적용 / 음식 템플릿 picker / 수정 모드 / 다크 모드 / 음식 템플릿 추가 탭 — 모두 라이브 라벨 갱신 + 저장 후 카드/요약 일치 확인
