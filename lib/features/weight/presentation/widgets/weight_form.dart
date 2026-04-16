import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../../domain/entities/weight_record.dart';
import '../providers/weight_provider.dart';

class WeightForm extends ConsumerStatefulWidget {
  final WeightRecord? initialRecord;

  const WeightForm({super.key, this.initialRecord});

  @override
  ConsumerState<WeightForm> createState() => _WeightFormState();
}

class _WeightFormState extends ConsumerState<WeightForm> {
  final _weightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialRecord != null) {
      _weightController.text = widget.initialRecord!.weight.toString();
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final weightValue = double.parse(_weightController.text);
      final now = DateTime.now();

      if (widget.initialRecord != null) {
        final updated = widget.initialRecord!.copyWith(
          weight: weightValue,
          updatedAt: now,
        );
        await ref.read(weightRecordsProvider.notifier).updateRecord(updated);
      } else {
        final newRecord = WeightRecord(
          timestamp: now,
          updatedAt: now,
          weight: weightValue,
        );
        await ref.read(weightRecordsProvider.notifier).addRecord(newRecord);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RecordFormSheet(
      title: widget.initialRecord != null ? '체중 수정' : '체중 기록',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _weightController,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: '0.0',
                suffixText: 'kg',
                border: InputBorder.none,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) return '체중을 입력해주세요';
                if (double.tryParse(value) == null) return '숫자만 입력 가능합니다';
                return null;
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Text(
                  widget.initialRecord != null ? '수정 완료' : '기록 완료',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
