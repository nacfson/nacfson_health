import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';

class DietTargetCard extends ConsumerStatefulWidget {
  const DietTargetCard({super.key});

  @override
  ConsumerState<DietTargetCard> createState() => _DietTargetCardState();
}

class _DietTargetCardState extends ConsumerState<DietTargetCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _caloriesCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final targets = ref.read(nutritionTargetsProvider);
    _caloriesCtrl = TextEditingController(text: targets.calories.toString());
    _carbsCtrl = TextEditingController(text: targets.carbs.toStringAsFixed(0));
    _proteinCtrl = TextEditingController(text: targets.protein.toStringAsFixed(0));
    _fatCtrl = TextEditingController(text: targets.fat.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _caloriesCtrl.dispose();
    _carbsCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(nutritionTargetsProvider.notifier).update(
            calories: int.parse(_caloriesCtrl.text.trim()),
            carbs: double.parse(_carbsCtrl.text.trim()),
            protein: double.parse(_proteinCtrl.text.trim()),
            fat: double.parse(_fatCtrl.text.trim()),
          );
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '목표 저장 완료',
          message: '영양 목표가 저장되었습니다.',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      debugPrint('DietTargetCard._save error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '저장 실패',
          message: '목표 저장 중 오류가 발생했습니다: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.track_changes, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('영양 목표', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '요약 탭에서 목표 대비 달성률을 확인할 수 있습니다.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TargetField(
                      controller: _caloriesCtrl,
                      label: '칼로리',
                      unit: 'kcal',
                      isInteger: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TargetField(
                      controller: _carbsCtrl,
                      label: '탄수화물',
                      unit: 'g',
                      color: Colors.orange[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TargetField(
                      controller: _proteinCtrl,
                      label: '단백질',
                      unit: 'g',
                      color: Colors.blue[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TargetField(
                      controller: _fatCtrl,
                      label: '지방',
                      unit: 'g',
                      color: Colors.yellow[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? '저장 중...' : '저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String unit;
  final Color? color;
  final bool isInteger;

  const _TargetField({
    required this.controller,
    required this.label,
    required this.unit,
    this.color,
    this.isInteger = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        labelStyle: color != null
            ? TextStyle(color: color, fontWeight: FontWeight.w600)
            : null,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return '입력해주세요';
        final n = isInteger ? int.tryParse(v.trim()) : double.tryParse(v.trim());
        if (n == null) return '숫자를 입력하세요';
        if ((isInteger ? (n as int) : (n as double)) <= 0) return '0보다 커야 합니다';
        return null;
      },
    );
  }
}
