import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/sheet_state_provider.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../../../shared/widgets/bottom_nav_shell.dart';
import '../../../../shared/widgets/date_navigation_bar.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../settings/domain/entities/food_template.dart';
import '../../../settings/presentation/providers/food_template_provider.dart';
import '../../domain/entities/diet_record.dart';
import '../providers/diet_provider.dart';
import '../widgets/diet_form.dart';
import '../widgets/diet_record_card.dart';

class DietScreen extends ConsumerStatefulWidget {
  const DietScreen({super.key});

  @override
  ConsumerState<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends ConsumerState<DietScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fabActionProvider.notifier).state = () => _openAddSheet(context);
    });
  }

  @override
  void dispose() {
    try {
      ref.read(fabActionProvider.notifier).state = null;
    } catch (_) {
      // dispose 시점에 ref 가 이미 무효화된 경우 무시 (정리 작업 실패는 영향 없음)
    }
    super.dispose();
  }

  void _openAddSheet(BuildContext context) {
    openSheet(
      context: context,
      ref: ref,
      type: SheetType.diet,
      title: '식단 기록 추가',
      child: const RecordFormSheet(
        title: '식단 기록 추가',
        child: DietForm(),
      ),
    );
  }

  void _openEditSheet(BuildContext context, DietRecord record) {
    openSheet(
      context: context,
      ref: ref,
      type: SheetType.diet,
      title: '식단 기록 수정',
      child: RecordFormSheet(
        title: '식단 기록 수정',
        child: DietForm(initialRecord: record),
      ),
    );
  }

  Future<void> _saveAsTemplate(DietRecord r) async {
    final name = r.foodName.trim();
    if (name.isEmpty) return;

    final templates = ref.read(foodTemplatesProvider);
    if (templates.any((t) => t.name == name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name"은(는) 이미 템플릿에 있습니다'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final template = FoodTemplate(
      uuid: '',
      name: name,
      calories: r.totalCalories,
      carbs: r.carbs,
      protein: r.protein,
      fat: r.fat,
      updatedAt: now,
    );
    await ref.read(foodTemplatesProvider.notifier).addTemplate(template);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('템플릿에 등록됨 · $name'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '설정',
          onPressed: () => context.push('/settings'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped      = ref.watch(selectedDateDietGroupedProvider);
    final summary      = ref.watch(selectedDateDietSummaryProvider);
    final targets      = ref.watch(nutritionTargetsProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday      = ref.watch(isSelectedDateTodayProvider);
    final isEmpty      = grouped.isEmpty;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('식단 기록')),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: DateNavigationBar()),
          SliverToBoxAdapter(
            child: _DietSummaryCard(
              date: selectedDate,
              summary: summary,
              targets: targets,
              isToday: isToday,
            ),
          ),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.restaurant,
                title: isToday ? '오늘의 식단 기록이 없어요' : '이 날짜의 식단 기록이 없어요',
                subtitle: isToday ? '+ 버튼으로 첫 식사를 기록해보세요' : '다른 날짜를 선택해보세요',
              ),
            )
          else
            for (final entry in grouped.entries) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(mealType: entry.key, count: entry.value.length),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final record = entry.value[i];
                    return DietRecordCard(
                      record: record,
                      onTap: () => _openEditSheet(context, record),
                      onDelete: () => ref
                          .read(dietRecordsProvider.notifier)
                          .deleteRecord(record.uuid),
                      onSaveAsTemplate: () => _saveAsTemplate(record),
                    );
                  },
                  childCount: entry.value.length,
                ),
              ),
            ],
          SliverToBoxAdapter(
            child: SizedBox(height: bottomNavFabInset(context)),
          ),
        ],
      ),
    );
  }
}

// ── 식단 요약 카드 ────────────────────────────────────────────────────────────

class _DietSummaryCard extends StatelessWidget {
  final DateTime date;
  final ({int kcal, double carbs, double protein, double fat}) summary;
  final NutritionTargets targets;
  final bool isToday;
  const _DietSummaryCard({
    required this.date,
    required this.summary,
    required this.targets,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr = '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
    final calorieRatio =
        targets.calories > 0 ? summary.kcal / targets.calories : 0.0;
    final caloriePct = (calorieRatio * 100).round();
    final calorieColor = _progressColor(calorieRatio);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday ? '오늘' : dateStr,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.colorCatDiet,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (isToday)
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '총 칼로리',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      color: AppTheme.colorTextDim,
                    ),
                  ),
                  Text(
                    summary.kcal == 0 ? '—' : '${summary.kcal} kcal',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: calorieColor,
                      letterSpacing: -0.8,
                    ),
                  ),
                  if (targets.calories > 0)
                    Text(
                      '/ ${targets.calories} kcal · $caloriePct%',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        color: AppTheme.colorTextDim,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MacroBarsRow(summary: summary, targets: targets),
        ],
      ),
    );
  }
}

Color _progressColor(double ratio) {
  if (ratio >= 1.05) return AppTheme.colorCoral;
  if (ratio >= 0.90) return AppTheme.colorMint;
  return AppTheme.colorCatDiet;
}

class _MacroBarsRow extends StatelessWidget {
  final ({int kcal, double carbs, double protein, double fat}) summary;
  final NutritionTargets targets;
  const _MacroBarsRow({required this.summary, required this.targets});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MacroBar(
          label: '탄',
          consumed: summary.carbs,
          target: targets.carbs,
          baseColor: AppTheme.colorCatDiet,
        ),
        const SizedBox(width: 8),
        _MacroBar(
          label: '단',
          consumed: summary.protein,
          target: targets.protein,
          baseColor: AppTheme.colorMint,
        ),
        const SizedBox(width: 8),
        _MacroBar(
          label: '지',
          consumed: summary.fat,
          target: targets.fat,
          baseColor: AppTheme.colorCoral,
        ),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double consumed;
  final double target;
  final Color baseColor;
  const _MacroBar({
    required this.label,
    required this.consumed,
    required this.target,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = target > 0 ? consumed / target : 0.0;
    final isOver = ratio >= 1.05;
    final barColor = isOver ? AppTheme.colorCoral : baseColor;
    final amount = target > 0
        ? '${consumed.toStringAsFixed(0)}g / ${target.toStringAsFixed(0)}g'
        : '${consumed.toStringAsFixed(0)}g';

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  color: barColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  color: AppTheme.colorTextDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 섹션 헤더 ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String mealType;
  final int count;
  const _SectionHeader({required this.mealType, required this.count});

  Color _sectionColor(String type, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (type) {
      '아침' => isDark ? AppTheme.colorCatDietDark : AppTheme.colorCatDiet,
      '점심' => isDark ? AppTheme.colorMintDark : AppTheme.colorMint,
      '저녁' => isDark ? AppTheme.colorCatSleepDark : AppTheme.colorCatSleep,
      _     => isDark ? AppTheme.colorCoralDark : AppTheme.colorCoral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _sectionColor(mealType, context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            mealType,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '$count개',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
