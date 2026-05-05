import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/nutrition/nutrition_calculator.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/weight/domain/entities/weight_record.dart';
import '../../../../features/weight/presentation/providers/weight_provider.dart';
import '../../../../shared/providers/user_profile_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightFocus = FocusNode();
  final _ageFocus = FocusNode();
  UserGender _gender = UserGender.male;
  ActivityLevel _activity = ActivityLevel.moderate;
  TrainingIntensity _intensity = TrainingIntensity.moderate;
  FitnessGoal _goal = FitnessGoal.leanMassGain;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _heightCtrl.addListener(_refreshPreview);
    _weightCtrl.addListener(_refreshPreview);
    _ageCtrl.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _heightCtrl.removeListener(_refreshPreview);
    _weightCtrl.removeListener(_refreshPreview);
    _ageCtrl.removeListener(_refreshPreview);
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    _weightFocus.dispose();
    _ageFocus.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  NutritionTargets? _previewTargets() {
    final h = double.tryParse(_heightCtrl.text.trim());
    final w = double.tryParse(_weightCtrl.text.trim());
    final age = int.tryParse(_ageCtrl.text.trim());
    if (h == null || h < 100 || h > 250) return null;
    if (w == null || w < 20 || w > 300) return null;
    if (age == null || age < 14 || age > 90) return null;
    return calculateTargets(NutritionCalculationInput(
      heightCm: h,
      weightKg: w,
      gender: _gender,
      age: age,
      goal: _goal,
      activityLevel: _activity,
      intensity: _intensity,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final heightCm = double.parse(_heightCtrl.text.trim());
    final weightKg = double.parse(_weightCtrl.text.trim());
    final age = int.parse(_ageCtrl.text.trim());

    // 키 저장 (m 단위)
    await ref.read(heightMProvider.notifier).setHeight(heightCm / 100);

    // 체중 오늘 날짜로 저장
    final now = DateTime.now();
    await ref.read(weightRecordsProvider.notifier).addRecord(
          WeightRecord(
            uuid: const Uuid().v4(),
            timestamp: DateTime(now.year, now.month, now.day),
            updatedAt: now,
            weight: weightKg,
          ),
        );

    // 사용자 프로필 저장
    final prefs = ref.read(syncPreferencesProvider);
    await prefs.setUserGenderRaw(_gender.prefsKey);
    await prefs.setUserAge(age);
    await prefs.setActivityLevelRaw(_activity.prefsKey);
    await prefs.setTrainingIntensityRaw(_intensity.prefsKey);
    await prefs.setFitnessGoalRaw(_goal.prefsKey);

    // 목표 기반 영양 목표 계산 및 저장
    final targets = calculateTargets(NutritionCalculationInput(
      heightCm: heightCm,
      weightKg: weightKg,
      gender: _gender,
      age: age,
      goal: _goal,
      activityLevel: _activity,
      intensity: _intensity,
    ));
    await ref.read(nutritionTargetsProvider.notifier).update(
          calories: targets.calories,
          carbs: targets.carbs,
          protein: targets.protein,
          fat: targets.fat,
        );

    // 온보딩 완료 플래그
    await ref.read(onboardingDoneProvider.notifier).complete();

    if (mounted) context.go('/exercise');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintTint = isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: mintTint,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.colorMint,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  '처음 오셨군요! 👋',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '맞춤 영양 목표 계산을 위해\n기본 정보를 입력해주세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                _FieldLabel(label: '키 (cm)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _heightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_weightFocus),
                  decoration: _inputDeco(hint: '예) 175'),
                  validator: (v) {
                    final raw = v?.trim() ?? '';
                    if (raw.isEmpty) return '키를 입력해주세요';
                    final d = double.tryParse(raw);
                    if (d == null) return '숫자만 입력 가능합니다 (입력: $raw)';
                    if (d < 100 || d > 250) {
                      return '100~250 사이 값을 입력해주세요 (입력: $d)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '체중 (kg)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _weightCtrl,
                  focusNode: _weightFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_ageFocus),
                  decoration: _inputDeco(hint: '예) 70.5'),
                  validator: (v) {
                    final raw = v?.trim() ?? '';
                    if (raw.isEmpty) return '체중을 입력해주세요';
                    final d = double.tryParse(raw);
                    if (d == null) return '숫자만 입력 가능합니다 (입력: $raw)';
                    if (d < 20 || d > 300) {
                      return '20~300 사이 값을 입력해주세요 (입력: $d)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '만 나이'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ageCtrl,
                  focusNode: _ageFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  decoration: _inputDeco(hint: '예) 31'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '나이를 입력해주세요';
                    final n = int.tryParse(v);
                    if (n == null || n < 14 || n > 90) return '14~90 사이 값을 입력해주세요';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '성별'),
                const SizedBox(height: 8),
                SegmentedButton<UserGender>(
                  segments: UserGender.values
                      .map((g) => ButtonSegment<UserGender>(
                            value: g,
                            label: Text(g.label),
                          ))
                      .toList(),
                  selected: {_gender},
                  onSelectionChanged: (s) =>
                      setState(() => _gender = s.first),
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '활동 수준'),
                const SizedBox(height: 4),
                Text(
                  _activity.description,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ActivityLevel.values.map((a) {
                    return ChoiceChip(
                      label: Text(a.label),
                      selected: _activity == a,
                      onSelected: (_) => setState(() => _activity = a),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '운동 강도 (단백질 기준)'),
                const SizedBox(height: 4),
                Text(
                  '${_intensity.description} · 단백질 ${_intensity.proteinGPerKg.toStringAsFixed(1)}g/kg',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TrainingIntensity.values.map((x) {
                    return ChoiceChip(
                      label: Text(x.label),
                      selected: _intensity == x,
                      onSelected: (_) => setState(() => _intensity = x),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                _FieldLabel(label: '목표'),
                const SizedBox(height: 4),
                Text(
                  _goal.description,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FitnessGoal.values.map((g) {
                    return ChoiceChip(
                      label: Text(g.label),
                      selected: _goal == g,
                      onSelected: (_) => setState(() => _goal = g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                _NutritionPreview(
                  targets: _previewTargets(),
                  tint: mintTint,
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.colorNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '시작하기',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '나중에 설정 화면에서 변경할 수 있어요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco({required String hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Pretendard',
        color: cs.onSurfaceVariant,
        fontSize: 15,
      ),
      filled: true,
      fillColor: cs.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppTheme.colorMint, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _NutritionPreview extends StatelessWidget {
  final NutritionTargets? targets;
  final Color tint;

  const _NutritionPreview({required this.targets, required this.tint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = targets;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppTheme.colorMint),
              const SizedBox(width: 6),
              Text(
                '예상 영양 목표',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (t == null)
            Text(
              '키/체중/나이를 입력하면 자동으로 계산돼요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              '${t.calories} kcal',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '탄 ${t.carbs.toStringAsFixed(0)}g'
              ' · 단 ${t.protein.toStringAsFixed(0)}g'
              ' · 지 ${t.fat.toStringAsFixed(0)}g',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
