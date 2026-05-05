import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/user_profile_provider.dart';
import '../providers/weight_provider.dart';
import '../widgets/weight_chart_card.dart';
import '../widgets/weight_form.dart';
import '../../../../shared/widgets/record_form_sheet.dart';

class WeightScreen extends ConsumerWidget {
  const WeightScreen({super.key});

  void _openAddSheet(BuildContext context) {
    final formKey = GlobalKey<WeightFormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
      // BottomNavShell 의 glassmorphic 하단 탭 바가 시트를 가리지 않는다.
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) => RecordFormSheet(
        title: '체중 기록 추가',
        onConfirmClose: () => _confirmDiscardIfDirty(ctx, formKey),
        child: WeightForm(key: formKey),
      ),
    );
  }

  Future<bool> _confirmDiscardIfDirty(
    BuildContext context,
    GlobalKey<WeightFormState> formKey,
  ) async {
    final state = formKey.currentState;
    if (state == null || !state.isDirty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('작성 중인 내용이 사라집니다'),
        content: const Text('닫을까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestWeight = ref.watch(latestWeightProvider);
    final todayWeight  = ref.watch(todayWeightProvider);
    final isInitialLoading =
        ref.watch(weightRecordsInitialLoadingProvider);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('체중')),
      body: (isInitialLoading && latestWeight == null)
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  _WeightHeroCard(
                    latestWeight: latestWeight?.weight,
                    hasTodayRecord: todayWeight != null,
                    onAddTap: () => _openAddSheet(context),
                  ),
                  const SizedBox(height: 12),
                  _BmiBar(weightKg: latestWeight?.weight),
                  const SizedBox(height: 12),
                  const WeightChartCard(),
                ],
              ),
            ),
    );
  }
}

// ── 체중 히어로 카드 ─────────────────────────────────────────────────────────

class _WeightHeroCard extends StatelessWidget {
  final double? latestWeight;
  final bool hasTodayRecord;
  final VoidCallback onAddTap;

  const _WeightHeroCard({
    this.latestWeight,
    required this.hasTodayRecord,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.colorNavy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.colorNavy.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '현재 체중',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: AppTheme.colorTextDim,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      latestWeight != null
                          ? latestWeight!.toStringAsFixed(1)
                          : '--.-',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        'kg',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          color: AppTheme.colorTextDim,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!hasTodayRecord)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onAddTap,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.colorMint.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.colorMint.withOpacity(0.4)),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '오늘 기록 추가',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              color: AppTheme.colorMint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hasTodayRecord)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.colorMint.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '오늘 기록됨',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  color: AppTheme.colorMint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── BMI 그라디언트 바 ─────────────────────────────────────────────────────────

class _BmiBar extends ConsumerWidget {
  final double? weightKg;
  const _BmiBar({this.weightKg});

  double? _bmi(double heightM) =>
      weightKg != null ? weightKg! / (heightM * heightM) : null;

  String _category(double? b) {
    if (b == null) return '--';
    if (b < 18.5) return '저체중';
    if (b < 23.0) return '정상';
    if (b < 25.0) return '과체중';
    return '비만';
  }

  Color _categoryColor(double? b) {
    if (b == null) return AppTheme.colorTextDim;
    if (b < 18.5) return AppTheme.colorCatSleep;
    if (b < 23.0) return AppTheme.colorMint;
    if (b < 25.0) return AppTheme.colorCatDiet;
    return AppTheme.colorCoral;
  }

  double _barFraction(double? b) {
    if (b == null) return 0;
    return ((b - 15.0) / 20.0).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heightM = ref.watch(heightMProvider);
    final bmi = _bmi(heightM);
    final bmiStr = bmi != null ? bmi.toStringAsFixed(1) : '--';
    final catColor = _categoryColor(bmi);

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BMI',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    '키 ${(heightM * 100).toStringAsFixed(0)}cm 기준',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    bmiStr,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: catColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _category(bmi),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: catColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final dotLeft = (constraints.maxWidth * _barFraction(bmi))
                  .clamp(6.0, constraints.maxWidth - 6.0) - 8;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.colorCatSleep,
                          AppTheme.colorMint,
                          AppTheme.colorCatDiet,
                          AppTheme.colorCoral,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: dotLeft,
                    top: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: catColor, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: catColor.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('저체중\n18.5',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 9,
                      color: cs.onSurfaceVariant)),
              Text('정상\n23.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 9,
                      color: cs.onSurfaceVariant)),
              Text('과체중\n25.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 9,
                      color: cs.onSurfaceVariant)),
              Text('비만',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 9,
                      color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
