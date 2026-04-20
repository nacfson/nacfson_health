import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/nutrition/nutrition_calculator.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../features/weight/presentation/providers/weight_provider.dart';
import '../../../../shared/providers/user_profile_provider.dart';
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

  void _recalculateFromGoal() {
    final prefs = ref.read(syncPreferencesProvider);
    final heightM = ref.read(heightMProvider);
    final latestWeight = ref.read(latestWeightProvider);

    if (latestWeight == null) {
      ErrorOverlay.show(
        title: '체중 기록 없음',
        message: '재계산하려면 체중 기록이 필요합니다. 체중 탭에서 먼저 기록해주세요.',
      );
      return;
    }

    final goal = FitnessGoalX.fromPrefsKey(prefs.fitnessGoalRaw);
    final gender = UserGenderX.fromPrefsKey(prefs.userGenderRaw);
    final ageGroup = AgeGroupX.fromPrefsKey(prefs.userAgeGroupRaw);

    final targets = calculateTargets(NutritionCalculationInput(
      heightCm: heightM * 100,
      weightKg: latestWeight.weight,
      gender: gender,
      ageGroup: ageGroup,
      goal: goal,
    ));

    setState(() {
      _caloriesCtrl.text = targets.calories.toString();
      _carbsCtrl.text = targets.carbs.toStringAsFixed(0);
      _proteinCtrl.text = targets.protein.toStringAsFixed(0);
      _fatCtrl.text = targets.fat.toStringAsFixed(0);
    });
  }

  Future<void> _openGoalPicker() async {
    final prefs = ref.read(syncPreferencesProvider);
    final current = FitnessGoalX.fromPrefsKey(prefs.fitnessGoalRaw);

    final picked = await showModalBottomSheet<FitnessGoal>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text('목표 선택', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final goal in FitnessGoal.values)
                ListTile(
                  leading: Icon(
                    goal == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  title: Text(goal.label),
                  onTap: () => Navigator.of(ctx).pop(goal),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked == null) return;
    await prefs.setFitnessGoalRaw(picked.prefsKey);
    if (mounted) {
      setState(() {}); // 현재 목표 라벨 갱신
      _recalculateFromGoal();
    }
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
              const SizedBox(height: 12),
              _GoalRecalculateRow(
                currentGoalLabel: FitnessGoalX.fromPrefsKey(
                  ref.watch(syncPreferencesProvider).fitnessGoalRaw,
                ).label,
                onChangeGoal: _openGoalPicker,
                onRecalculate: _recalculateFromGoal,
              ),
              const SizedBox(height: 12),
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

class _GoalRecalculateRow extends StatelessWidget {
  final String currentGoalLabel;
  final VoidCallback onChangeGoal;
  final VoidCallback onRecalculate;

  const _GoalRecalculateRow({
    required this.currentGoalLabel,
    required this.onChangeGoal,
    required this.onRecalculate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        InkWell(
          onTap: onChangeGoal,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '현재: $currentGoalLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onRecalculate,
          icon: const Icon(Icons.calculate_outlined, size: 16),
          label: const Text('목표 기반 재계산'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: theme.textTheme.bodySmall,
          ),
        ),
      ],
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
