import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ai/health_insight_provider.dart';
import '../../../../core/theme/app_theme.dart';

import '../../../../shared/widgets/date_navigation_bar.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../../activity/presentation/widgets/activity_summary_card.dart';
import '../../../exercise/presentation/widgets/volume_trend_chart.dart';
import '../../../diet/presentation/widgets/calorie_trend_chart.dart';
import '../../domain/entities/daily_summary.dart';
import '../providers/summary_provider.dart';
import '../widgets/coach_chat_sheet.dart';
import '../widgets/recent_pr_card.dart';
import '../widgets/workout_heatmap_card.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider);
    final isToday = ref.watch(isSelectedDateTodayProvider);
    final isInitialLoading =
        ref.watch(dailySummaryInitialLoadingProvider);

    if (isInitialLoading) {
      return Scaffold(
        extendBody: true,
        appBar: AppBar(title: Text(isToday ? '오늘의 요약' : '요약')),
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: Text(isToday ? '오늘의 요약' : '요약')),
      body: CustomScrollView(
        slivers: [
          // 날짜 네비게이션 바
          const SliverToBoxAdapter(child: DateNavigationBar()),
          const SliverToBoxAdapter(child: WorkoutHeatmapCard()),
          SliverToBoxAdapter(child: _DateHeader(date: summary.date)),
          const SliverToBoxAdapter(child: _AiInsightCard()),
          const SliverToBoxAdapter(child: ActivitySummaryCard()),
          if (summary.dietNutrition != null) ...[
            SliverToBoxAdapter(
              child: _CalorieDonutCard(nutrition: summary.dietNutrition!),
            ),
            SliverToBoxAdapter(
              child: _MacroProgressCard(nutrition: summary.dietNutrition!),
            ),
          ] else
            const SliverToBoxAdapter(child: _EmptyDietCard()),
          if (summary.workoutPerformance != null)
            SliverToBoxAdapter(
              child: _WorkoutSummaryCard(
                  performance: summary.workoutPerformance!),
            ),
          const SliverToBoxAdapter(child: RecentPrCard()),
          // ── 추세 차트 섹션 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '추세 분석',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: CalorieTrendChart()),
          const SliverToBoxAdapter(child: VolumeTrendChart()),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 헤더
// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr =
        '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        dateStr,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 칼로리 도넛 카드
// ─────────────────────────────────────────────────────────────────────────────

class _CalorieDonutCard extends StatelessWidget {
  final DietNutrition nutrition;
  const _CalorieDonutCard({required this.nutrition});

  Color _chartColor(BuildContext context, CalorieResult result) {
    return switch (result) {
      CalorieResult.achieved => AppTheme.colorMint,
      CalorieResult.exceeded => AppTheme.colorCoral,
      CalorieResult.under    => AppTheme.colorCatDiet,
    };
  }

  String _resultLabel(CalorieResult result) => switch (result) {
        CalorieResult.achieved => '목표 달성',
        CalorieResult.exceeded => '목표 초과',
        CalorieResult.under => '목표 미달',
      };

  Color _badgeColor(CalorieResult result) => switch (result) {
        CalorieResult.achieved => AppTheme.colorMint,
        CalorieResult.exceeded => AppTheme.colorCoral,
        CalorieResult.under    => AppTheme.colorCatDiet,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final consumed = nutrition.consumedCalories;
    final target = nutrition.targetCalories;
    final ratio = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    final remaining = 1.0 - ratio;
    final activeColor = _chartColor(context, nutrition.calorieResult);

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: AppTheme.colorCatDiet, size: 20),
                const SizedBox(width: 8),
                Text('칼로리', style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _badgeColor(nutrition.calorieResult)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _resultLabel(nutrition.calorieResult),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _badgeColor(nutrition.calorieResult),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: [
                        PieChartSectionData(
                          value: ratio * 100,
                          color: activeColor,
                          radius: 28,
                          showTitle: false,
                        ),
                        if (remaining > 0)
                          PieChartSectionData(
                            value: remaining * 100,
                            color: colorScheme.surfaceContainerHighest,
                            radius: 24,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$consumed',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: activeColor,
                        ),
                      ),
                      Text(
                        '/ $target kcal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${(ratio * 100).toStringAsFixed(0)}% 달성',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: activeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 매크로 프로그레스 카드
// ─────────────────────────────────────────────────────────────────────────────

class _MacroProgressCard extends StatelessWidget {
  final DietNutrition nutrition;
  const _MacroProgressCard({required this.nutrition});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final carbs = nutrition.macroStatus['carbs']!;
    final protein = nutrition.macroStatus['protein']!;
    final fat = nutrition.macroStatus['fat']!;

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline,
                    color: AppTheme.colorMint, size: 20),
                const SizedBox(width: 8),
                Text('매크로 영양소', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _MacroRow(
              label: '탄수화물',
              info: carbs,
              color: AppTheme.colorCatDiet,
            ),
            const SizedBox(height: 12),
            _MacroRow(
              label: '단백질',
              info: protein,
              color: AppTheme.colorMint,
            ),
            const SizedBox(height: 12),
            _MacroRow(
              label: '지방',
              info: fat,
              color: AppTheme.colorCoral,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final MacroInfo info;
  final Color color;
  const _MacroRow({
    required this.label,
    required this.info,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExceeded = info.consumed > info.target;
    final barColor = isExceeded ? theme.colorScheme.error : color;
    final progress = info.target > 0
        ? min(1.0, info.consumed / info.target)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: barColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${info.consumed.toStringAsFixed(0)} / ${info.target.toStringAsFixed(0)}g',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isExceeded) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_upward, size: 12, color: theme.colorScheme.error),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 운동 요약 카드
// ─────────────────────────────────────────────────────────────────────────────

class _WorkoutSummaryCard extends StatelessWidget {
  final WorkoutPerformance performance;
  const _WorkoutSummaryCard({required this.performance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center,
                    color: AppTheme.colorMint, size: 20),
                const SizedBox(width: 8),
                Text('운동', style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: performance.isWorkoutDay
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.colorMintTintDark
                            : AppTheme.colorMintTint)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    performance.isWorkoutDay ? '운동함' : '휴식일',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: performance.isWorkoutDay
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.colorMintDark
                              : AppTheme.colorMintDeep)
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (performance.isWorkoutDay) ...[
              if (performance.targetedMuscles.isNotEmpty) ...[
                Text('운동 부위',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.outline)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: performance.targetedMuscles
                      .map((m) => Chip(
                            label: Text(m),
                            labelStyle: theme.textTheme.labelSmall,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: colorScheme.primaryContainer,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.bar_chart,
                      label: '총 볼륨',
                      value: '${performance.totalVolume.toStringAsFixed(0)} kg',
                      color: AppTheme.colorMint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.speed,
                      label: '평균 RPE',
                      value: performance.averageRpe.toStringAsFixed(1),
                      color: AppTheme.colorCoral,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _EstimatedCalorieTile(kcal: performance.estimatedCalories),
            ] else
              Text(
                '오늘은 휴식을 취했습니다. 내일도 화이팅!',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _EstimatedCalorieTile extends StatelessWidget {
  final double kcal;
  const _EstimatedCalorieTile({required this.kcal});

  void _showInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '볼륨 기반 추정치입니다 (오차 ±40%). 워치 활동 칼로리와는 별도이며 합산되지 않습니다.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department,
              size: 18, color: AppTheme.colorCatDiet),
          const SizedBox(width: 8),
          Text(
            '운동 칼로리',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            tooltip: '운동 칼로리 추정 안내',
            onPressed: () => _showInfo(context),
            icon: Icon(
              Icons.info_outline,
              size: 14,
              color: colorScheme.outline,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          Text(
            '~${kcal.round()} kcal',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.colorCatDiet,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '추정치',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 식단 미입력 안내
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDietCard extends StatelessWidget {
  const _EmptyDietCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.restaurant_outlined,
                size: 40, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              '오늘의 식단 기록이 없습니다',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '식단 탭에서 오늘 먹은 것을 기록해보세요.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── AI 건강 인사이트 카드 ──────────────────────────────────────────────────────

class _AiInsightCard extends ConsumerStatefulWidget {
  const _AiInsightCard();

  @override
  ConsumerState<_AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends ConsumerState<_AiInsightCard> {
  Timer? _debounceTicker;

  @override
  void dispose() {
    _debounceTicker?.cancel();
    super.dispose();
  }

  void _scheduleTickerIfNeeded() {
    if (_debounceTicker != null) return;
    _debounceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final last = ref.read(insightLastRefreshAtProvider);
      if (last == null) {
        _debounceTicker?.cancel();
        _debounceTicker = null;
        return;
      }
      final elapsed = DateTime.now().difference(last).inSeconds;
      if (elapsed >= kInsightRefreshDebounceSeconds) {
        _debounceTicker?.cancel();
        _debounceTicker = null;
        // last 값을 비워 canRefresh 가 true 가 되도록
        ref.read(insightLastRefreshAtProvider.notifier).state = null;
      } else {
        // 카운트다운 표시 갱신
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintTint =
        isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;
    final insightAsync = ref.watch(healthInsightProvider);
    final lastRefresh = ref.watch(insightLastRefreshAtProvider);
    final canRefresh = lastRefresh == null ||
        DateTime.now().difference(lastRefresh).inSeconds >=
            kInsightRefreshDebounceSeconds;

    int remainingSeconds = 0;
    if (!canRefresh) {
      remainingSeconds = kInsightRefreshDebounceSeconds -
          DateTime.now().difference(lastRefresh).inSeconds;
      _scheduleTickerIfNeeded();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: mintTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.colorMint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 건강 인사이트',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      canRefresh
                          ? 'Powered by Gemini'
                          : 'Powered by Gemini · ${remainingSeconds.clamp(0, 59)}초 후 새로고침 가능',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              insightAsync.isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.colorMint,
                      ),
                    )
                  : IconButton(
                      tooltip: canRefresh
                          ? 'AI 인사이트 새로고침'
                          : '잠시 후 다시 시도해주세요',
                      onPressed: () {
                        if (!canRefresh) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '잠시 후 다시 시도해주세요 (1분 디바운스)',
                              ),
                            ),
                          );
                          return;
                        }
                        ref
                            .read(insightLastRefreshAtProvider.notifier)
                            .state = DateTime.now();
                        // 세션 캐시 초기화 → 완전히 새 호출
                        ref
                            .read(insightCacheProvider.notifier)
                            .update((_) => const {});
                        ref.invalidate(healthInsightProvider);
                      },
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: canRefresh
                            ? cs.onSurfaceVariant
                            : cs.outlineVariant,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 44, minHeight: 44),
                      visualDensity: VisualDensity.compact,
                    ),
            ],
          ),
          const SizedBox(height: 14),
          insightAsync.when(
            loading: () => Text(
              'AI가 오늘의 건강 데이터를 분석하고 있습니다...',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            error: (e, _) {
              final msg = e.toString();
              final String text;
              if (msg.contains('AI_UNAVAILABLE') ||
                  msg.contains('GEMINI_API_KEY_MISSING') ||
                  msg.contains('API')) {
                text = 'AI 인사이트는 현재 사용할 수 없습니다.';
              } else {
                text = '인사이트를 불러오지 못했습니다. 새로고침해보세요.';
              }
              return Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        color: cs.error,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              );
            },
            data: (text) => Text(
              text,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: cs.onSurface,
                height: 1.6,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showCoachChatSheet(context),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text(
                '코치에게 더 물어보기',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.colorMint,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
