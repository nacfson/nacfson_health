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

  Future<void> _recalculateFromGoal() async {
    final prefs = ref.read(syncPreferencesProvider);
    final heightM = ref.read(heightMProvider);

    // WeightNotifier가 비동기 refresh로 초기화되므로 latestWeightProvider는
    // 화면 진입 직후 일시적으로 null일 수 있음. 저장소를 직접 조회해 오탐 방지.
    final repo = ref.read(weightRepositoryProvider);
    final latestWeight = await repo.getLatest();

    if (!mounted) return;
    if (latestWeight == null) {
      ErrorOverlay.show(
        title: '체중 기록 없음',
        message: '재계산하려면 체중 기록이 필요합니다. 체중 탭에서 먼저 기록해주세요.',
      );
      return;
    }

    final goal = FitnessGoalX.fromPrefsKey(prefs.fitnessGoalRaw);
    final gender = UserGenderX.fromPrefsKey(prefs.userGenderRaw);
    final activity = ActivityLevelX.fromPrefsKey(prefs.activityLevelRaw);
    final intensity =
        TrainingIntensityX.fromPrefsKey(prefs.trainingIntensityRaw);

    final targets = calculateTargets(NutritionCalculationInput(
      heightCm: heightM * 100,
      weightKg: latestWeight.weight,
      gender: gender,
      age: prefs.userAge,
      goal: goal,
      activityLevel: activity,
      intensity: intensity,
    ));

    setState(() {
      _caloriesCtrl.text = targets.calories.toString();
      _carbsCtrl.text = targets.carbs.toStringAsFixed(0);
      _proteinCtrl.text = targets.protein.toStringAsFixed(0);
      _fatCtrl.text = targets.fat.toStringAsFixed(0);
    });
  }

  Future<T?> _openPicker<T>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelBuilder,
    String Function(T)? subtitleBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final v in values)
                ListTile(
                  leading: Icon(
                    v == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  title: Text(labelBuilder(v)),
                  subtitle: subtitleBuilder != null
                      ? Text(subtitleBuilder(v))
                      : null,
                  onTap: () => Navigator.of(ctx).pop(v),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openGoalPicker() async {
    final prefs = ref.read(syncPreferencesProvider);
    final current = FitnessGoalX.fromPrefsKey(prefs.fitnessGoalRaw);

    final picked = await _openPicker<FitnessGoal>(
      title: '목표 선택',
      values: FitnessGoal.values,
      current: current,
      labelBuilder: (g) => g.label,
      subtitleBuilder: (g) => g.description,
    );
    if (picked == null) return;
    await prefs.setFitnessGoalRaw(picked.prefsKey);
    if (!mounted) return;
    setState(() {});
    await _recalculateFromGoal();
  }

  Future<void> _openActivityPicker() async {
    final prefs = ref.read(syncPreferencesProvider);
    final current = ActivityLevelX.fromPrefsKey(prefs.activityLevelRaw);

    final picked = await _openPicker<ActivityLevel>(
      title: '활동 수준',
      values: ActivityLevel.values,
      current: current,
      labelBuilder: (a) => '${a.label} (×${a.multiplier})',
      subtitleBuilder: (a) => a.description,
    );
    if (picked == null) return;
    await prefs.setActivityLevelRaw(picked.prefsKey);
    if (!mounted) return;
    setState(() {});
    await _recalculateFromGoal();
  }

  Future<void> _openIntensityPicker() async {
    final prefs = ref.read(syncPreferencesProvider);
    final current = TrainingIntensityX.fromPrefsKey(prefs.trainingIntensityRaw);

    final picked = await _openPicker<TrainingIntensity>(
      title: '운동 강도 (단백질 기준)',
      values: TrainingIntensity.values,
      current: current,
      labelBuilder: (x) =>
          '${x.label} (${x.proteinGPerKg.toStringAsFixed(1)}g/kg)',
      subtitleBuilder: (x) => x.description,
    );
    if (picked == null) return;
    await prefs.setTrainingIntensityRaw(picked.prefsKey);
    if (!mounted) return;
    setState(() {});
    await _recalculateFromGoal();
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
    final prefs = ref.watch(syncPreferencesProvider);
    final goalLabel = FitnessGoalX.fromPrefsKey(prefs.fitnessGoalRaw).label;
    final activityLabel =
        ActivityLevelX.fromPrefsKey(prefs.activityLevelRaw).label;
    final intensityLabel =
        TrainingIntensityX.fromPrefsKey(prefs.trainingIntensityRaw).label;

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
              _ProfileChip(label: '목표: $goalLabel', onTap: _openGoalPicker),
              const SizedBox(height: 6),
              _ProfileChip(
                  label: '활동: $activityLabel', onTap: _openActivityPicker),
              const SizedBox(height: 6),
              _ProfileChip(
                  label: '강도: $intensityLabel', onTap: _openIntensityPicker),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _recalculateFromGoal,
                  icon: const Icon(Icons.calculate_outlined, size: 16),
                  label: const Text('프로필 기반 재계산'),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: theme.textTheme.bodySmall,
                  ),
                ),
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

class _ProfileChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ProfileChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(
              label,
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
