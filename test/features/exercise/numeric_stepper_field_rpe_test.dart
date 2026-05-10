import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nacfson_health/shared/widgets/numeric_stepper_field.dart';

/// RPE 필드 입력 회귀 테스트.
/// suffixText 가 textAlign:center 와 충돌해 입력 불가가 되는 회귀를 방지하기 위해
/// suffix 슬롯(Widget) 과 textAlignVertical 를 명시한 상태에서
/// 직접 입력·± 버튼 모두 controller 에 정상 반영되는지 확인.
void main() {
  Widget _harness(TextEditingController ctl, FocusNode focus) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 132,
            child: NumericStepperField(
              controller: ctl,
              focusNode: focus,
              suffix: '/10',
              step: 0.5,
              min: 1,
              max: 10,
              textInputAction: TextInputAction.done,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('RPE 필드: 직접 입력한 값이 controller 에 반영', (tester) async {
    final ctl = TextEditingController();
    final focus = FocusNode();
    addTearDown(() {
      ctl.dispose();
      focus.dispose();
    });

    await tester.pumpWidget(_harness(ctl, focus));

    final fieldFinder = find.byType(TextField);
    expect(fieldFinder, findsOneWidget);

    await tester.enterText(fieldFinder, '8');
    expect(ctl.text, '8');

    await tester.enterText(fieldFinder, '8.5');
    expect(ctl.text, '8.5');
  });

  testWidgets('RPE 필드: + 버튼이 min/max 클램프하며 0.5 step 으로 증가', (tester) async {
    final ctl = TextEditingController();
    final focus = FocusNode();
    addTearDown(() {
      ctl.dispose();
      focus.dispose();
    });

    await tester.pumpWidget(_harness(ctl, focus));

    // 빈 상태에서 + 1회 → 0+0.5=0.5, min=1 클램프 → "1"
    final addBtn = find.byIcon(Icons.add);
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await tester.pump();
    expect(ctl.text, '1');

    // + 한 번 더 → 1.5
    await tester.tap(addBtn);
    await tester.pump();
    expect(ctl.text, '1.5');
  });

  testWidgets('RPE 필드: - 버튼이 min 도달 시 자동 비활성', (tester) async {
    final ctl = TextEditingController(text: '1');
    final focus = FocusNode();
    addTearDown(() {
      ctl.dispose();
      focus.dispose();
    });

    await tester.pumpWidget(_harness(ctl, focus));
    final removeBtn = find.byIcon(Icons.remove);
    final IconButton removeIconButton = tester.widget(
      find.ancestor(of: removeBtn, matching: find.byType(IconButton)),
    );
    expect(removeIconButton.onPressed, isNull,
        reason: 'min=1 도달 시 ⊖ 버튼 비활성');
  });

  testWidgets('RPE 필드: 알파벳·특수문자는 inputFormatter 가 차단, 숫자/소수점만 통과',
      (tester) async {
    final ctl = TextEditingController();
    final focus = FocusNode();
    addTearDown(() {
      ctl.dispose();
      focus.dispose();
    });

    await tester.pumpWidget(_harness(ctl, focus));
    final fieldFinder = find.byType(TextField);

    await tester.enterText(fieldFinder, 'abc8.5xyz');
    expect(ctl.text, '8.5');
  });
}
