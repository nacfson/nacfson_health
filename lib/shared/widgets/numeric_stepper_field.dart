import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 좌우 ± 버튼 + 가운데 TextField 조합 숫자 입력기.
///
/// - 텍스트 직접 입력과 ± 버튼 미세 조정을 동시에 지원.
/// - long-press 시 100ms 간격으로 자동 반복 가속.
/// - `integer: true` 면 정수만 (회 입력), 아니면 [step] 자릿수에 맞춰 소수.
/// - [min] / [max] 로 클램프. ± 버튼은 클램프 한계에서 자동 비활성.
/// - `inputFormatters` 는 내부적으로 숫자/소수점만 허용.
class NumericStepperField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? suffix;
  final double step;
  final double? min;
  final double? max;
  final bool integer;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const NumericStepperField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.suffix,
    this.step = 1.0,
    this.min,
    this.max,
    this.integer = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<NumericStepperField> createState() => _NumericStepperFieldState();
}

class _NumericStepperFieldState extends State<NumericStepperField> {
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  double _currentValue() {
    return double.tryParse(widget.controller.text.trim()) ?? 0;
  }

  String _format(double v) {
    if (widget.integer) return v.toInt().toString();
    if (v % 1 == 0) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
  }

  void _adjust(double delta) {
    var next = _currentValue() + delta;
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    final formatted = _format(next);
    widget.controller.text = formatted;
    widget.controller.selection =
        TextSelection.collapsed(offset: formatted.length);
    setState(() {});
  }

  void _startHold(double delta) {
    _adjust(delta);
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _adjust(delta);
    });
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  bool get _canDecrement {
    if (widget.min == null) return true;
    return _currentValue() > widget.min!;
  }

  bool get _canIncrement {
    if (widget.max == null) return true;
    return _currentValue() < widget.max!;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: Icons.remove,
          onTap: _canDecrement ? () => _adjust(-widget.step) : null,
          onLongPressStart:
              _canDecrement ? () => _startHold(-widget.step) : null,
          onLongPressEnd: _stopHold,
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType:
                TextInputType.numberWithOptions(decimal: !widget.integer),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.integer ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
              ),
            ],
            textAlign: TextAlign.center,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: widget.label,
              suffixText: widget.suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          onTap: _canIncrement ? () => _adjust(widget.step) : null,
          onLongPressStart:
              _canIncrement ? () => _startHold(widget.step) : null,
          onLongPressEnd: _stopHold,
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const _StepperButton({
    required this.icon,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return GestureDetector(
      onLongPressStart: enabled ? (_) => onLongPressStart?.call() : null,
      onLongPressEnd: enabled ? (_) => onLongPressEnd?.call() : null,
      onLongPressCancel: enabled ? () => onLongPressEnd?.call() : null,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
        color: enabled ? cs.primary : cs.outlineVariant,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
