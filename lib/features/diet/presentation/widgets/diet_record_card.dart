import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/diet_record.dart';

class DietRecordCard extends StatelessWidget {
  final DietRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const DietRecordCard({
    super.key,
    required this.record,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mealColor = _mealTypeColor(record.mealType, theme.brightness);
    final timeStr = _formatTime(record.timestamp);

    return Dismissible(
      key: ValueKey(record.uuid),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(colorScheme: colorScheme),
      confirmDismiss: (_) => _showDeleteConfirm(context, record.foodName),
      onDismissed: (_) => onDelete?.call(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 Row
                Row(
                  children: [
                    _MealIcon(mealType: record.mealType, color: mealColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.foodName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _TypeChip(
                            label: record.mealType,
                            backgroundColor: mealColor,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StarRating(satisfaction: record.satisfaction),
                        Text(
                          timeStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 칼로리
                Text(
                  '${record.totalCalories} kcal',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.catDiet(context),
                  ),
                ),
                const SizedBox(height: 6),
                // 매크로 게이지 바
                _MacroGaugeRow(record: record),
                // 메모 (있을 때만)
                if (record.memo != null && record.memo!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    record.memo!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _mealTypeColor(String mealType, [Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;
  return switch (mealType) {
    '아침' => isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint,
    '점심' => isDark ? AppTheme.colorLunchTintDark : AppTheme.colorLunchTint,
    '저녁' => isDark ? AppTheme.colorCoralTintDark : AppTheme.colorCoralTint,
    '간식' => isDark ? AppTheme.colorSnackTintDark : AppTheme.colorSnackTint,
    _ => isDark ? AppTheme.colorSurfaceAltDark : AppTheme.colorBg,
  };
}

IconData mealTypeIcon(String mealType) {
  return switch (mealType) {
    '아침' => Icons.wb_sunny_outlined,
    '점심' => Icons.lunch_dining,
    '저녁' => Icons.dinner_dining,
    '간식' => Icons.cookie_outlined,
    _ => Icons.restaurant,
  };
}

String _formatTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

Future<bool?> _showDeleteConfirm(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('"$name"을(를) 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
}

class _MealIcon extends StatelessWidget {
  final String mealType;
  final Color color;
  const _MealIcon({required this.mealType, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(mealTypeIcon(mealType), size: 20),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  const _TypeChip({required this.label, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _StarRating extends StatelessWidget {
  final int satisfaction;
  const _StarRating({required this.satisfaction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < satisfaction ? Icons.star : Icons.star_border,
          size: 12,
          color: Colors.amber,
        );
      }),
    );
  }
}

class _MacroGaugeRow extends StatelessWidget {
  final DietRecord record;
  const _MacroGaugeRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = record.totalCalories.toDouble();

    return Column(
      children: [
        _GaugeRow(
          label: '탄',
          value: total > 0 ? (record.carbs * 4) / total : 0,
          amount: '${record.carbs.toStringAsFixed(0)}g',
          color: theme.brightness == Brightness.dark
              ? AppTheme.colorCatDietDark
              : AppTheme.colorCatDiet,
          backgroundColor: theme.brightness == Brightness.dark
              ? AppTheme.colorSnackTintDark
              : AppTheme.colorSnackTint,
          theme: theme,
        ),
        const SizedBox(height: 4),
        _GaugeRow(
          label: '단',
          value: total > 0 ? (record.protein * 4) / total : 0,
          amount: '${record.protein.toStringAsFixed(0)}g',
          color: theme.brightness == Brightness.dark
              ? AppTheme.colorMintDark
              : AppTheme.colorMint,
          backgroundColor: theme.brightness == Brightness.dark
              ? AppTheme.colorMintTintDark
              : AppTheme.colorMintTint,
          theme: theme,
        ),
        const SizedBox(height: 4),
        _GaugeRow(
          label: '지',
          value: total > 0 ? (record.fat * 9) / total : 0,
          amount: '${record.fat.toStringAsFixed(0)}g',
          color: theme.brightness == Brightness.dark
              ? AppTheme.colorCoralDark
              : AppTheme.colorCoral,
          backgroundColor: theme.brightness == Brightness.dark
              ? AppTheme.colorCoralTintDark
              : AppTheme.colorCoralTint,
          theme: theme,
        ),
      ],
    );
  }
}

class _GaugeRow extends StatelessWidget {
  final String label;
  final double value;
  final String amount;
  final Color color;
  final Color backgroundColor;
  final ThemeData theme;

  const _GaugeRow({
    required this.label,
    required this.value,
    required this.amount,
    required this.color,
    required this.backgroundColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label, style: theme.textTheme.labelSmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: backgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            amount,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  final ColorScheme colorScheme;
  const _DeleteBackground({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: colorScheme.onErrorContainer, size: 28),
          Text(
            '삭제',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
