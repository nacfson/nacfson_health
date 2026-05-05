import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/weight_record.dart';
import '../providers/weight_provider.dart';

class WeightForm extends ConsumerStatefulWidget {
  final WeightRecord? initialRecord;

  const WeightForm({super.key, this.initialRecord});

  @override
  ConsumerState<WeightForm> createState() => WeightFormState();
}

class WeightFormState extends ConsumerState<WeightForm> {
  /// 외부 (RecordFormSheet onConfirmClose) 에서 dirty 여부를 조회하기 위한 진입점.
  bool get isDirty {
    final current = _weightController.text.trim();
    if (current.isEmpty) return false;
    final initial = widget.initialRecord?.weight.toString() ?? '';
    return current != initial || _selectedDate != _originalDate;
  }

  final _weightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  bool _isLoading = false;
  Timer? _holdTimer;

  void _adjustWeight(double delta) {
    final current = double.tryParse(_weightController.text.trim()) ?? 0;
    final next = (current + delta).clamp(0.0, 999.9);
    final formatted =
        next % 1 == 0 ? next.toInt().toString() : next.toStringAsFixed(1);
    _weightController.text = formatted;
    _weightController.selection =
        TextSelection.collapsed(offset: formatted.length);
  }

  void _startAdjustHold(double delta) {
    _adjustWeight(delta);
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _adjustWeight(delta);
    });
  }

  void _stopAdjustHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    _selectedDate = r != null
        ? DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day)
        : DateTime.now();
    if (r != null) {
      _weightController.text = r.weight.toString();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _weightController.dispose();
    super.dispose();
  }

  DateTime get _originalDate {
    final r = widget.initialRecord;
    if (r != null) {
      return DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate != _originalDate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('날짜 확인'),
          content: Text(
            '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일로 기록하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isLoading = true);
    try {
      final weightValue = double.parse(_weightController.text);
      final now = DateTime.now();

      if (widget.initialRecord != null) {
        final updated = widget.initialRecord!.copyWith(
          weight: weightValue,
          timestamp: _selectedDate,
          updatedAt: now,
        );
        await ref.read(weightRecordsProvider.notifier).updateRecord(updated);
      } else {
        final newRecord = WeightRecord(
          timestamp: _selectedDate,
          updatedAt: now,
          weight: weightValue,
        );
        await ref.read(weightRecordsProvider.notifier).addRecord(newRecord);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('저장되었습니다'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDateChanged = _selectedDate != _originalDate;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDateChanged
                        ? AppTheme.warnFg(context)
                        : theme.colorScheme.outline,
                    width: isDateChanged ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일',
                      style: theme.textTheme.bodyLarge,
                    ),
                    Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _LargeStepperButton(
                  icon: Icons.remove,
                  onTap: () => _adjustWeight(-0.1),
                  onLongPressStart: () => _startAdjustHold(-0.1),
                  onLongPressEnd: _stopAdjustHold,
                ),
                Expanded(
                  child: TextFormField(
                    controller: _weightController,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: '0.0',
                      suffixText: 'kg',
                      border: InputBorder.none,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '체중을 입력해주세요';
                      if (double.tryParse(value) == null) {
                        return '숫자만 입력 가능합니다';
                      }
                      return null;
                    },
                  ),
                ),
                _LargeStepperButton(
                  icon: Icons.add,
                  onTap: () => _adjustWeight(0.1),
                  onLongPressStart: () => _startAdjustHold(0.1),
                  onLongPressEnd: _stopAdjustHold,
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isDateChanged
                            ? '${_selectedDate.month}월 ${_selectedDate.day}일로 기록'
                            : (widget.initialRecord != null ? '수정 완료' : '기록 완료'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
  }
}

class _LargeStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _LargeStepperButton({
    required this.icon,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        color: cs.primary,
        constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      ),
    );
  }
}
