import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

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
  final _weightFocus = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final heightCm = double.parse(_heightCtrl.text.trim());
    final weightKg = double.parse(_weightCtrl.text.trim());

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
                // 로고 / 일러스트
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
                  '정확한 BMI와 건강 분석을 위해\n기본 정보를 입력해주세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // ── 키 입력 ──
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
                    if (v == null || v.isEmpty) return '키를 입력해주세요';
                    final d = double.tryParse(v);
                    if (d == null || d < 100 || d > 250) return '올바른 키를 입력해주세요';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── 체중 입력 ──
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
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _inputDeco(hint: '예) 70.5'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '체중을 입력해주세요';
                    final d = double.tryParse(v);
                    if (d == null || d < 20 || d > 300) return '올바른 체중을 입력해주세요';
                    return null;
                  },
                ),
                const SizedBox(height: 40),

                // ── 시작 버튼 ──
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
