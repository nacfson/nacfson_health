import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/selected_date_provider.dart';

/// 날짜 탐색 바 위젯 (좌우 이동 + 달력 선택 + "오늘" 버튼)
///
/// 운동/식단/요약 화면의 AppBar 하단 또는 body 상단에 배치하여
/// 사용자가 과거 날짜의 데이터를 탐색할 수 있게 합니다.
class DateNavigationBar extends ConsumerWidget {
  const DateNavigationBar({super.key});

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String _formatDate(DateTime date) {
    return '${date.month}월 ${date.day}일 (${_weekdays[date.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday = ref.watch(isSelectedDateTodayProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          // 이전 날짜 버튼
          IconButton(
            onPressed: () {
              ref.read(selectedDateProvider.notifier).state =
                  selectedDate.subtract(const Duration(days: 1));
            },
            icon: const Icon(Icons.chevron_left, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: '이전 날짜',
          ),

          // 날짜 표시 (탭하면 DatePicker 열기)
          Expanded(
            child: GestureDetector(
              onTap: () => _showDatePicker(context, ref, selectedDate),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _formatDate(selectedDate),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),

          // 다음 날짜 버튼 (오늘 이후로는 이동 불가)
          IconButton(
            onPressed: isToday
                ? null
                : () {
                    ref.read(selectedDateProvider.notifier).state =
                        selectedDate.add(const Duration(days: 1));
                  },
            icon: const Icon(Icons.chevron_right, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: '다음 날짜',
          ),

          // "오늘" 버튼 (오늘이 아닐 때만 표시)
          if (!isToday)
            Builder(
              builder: (ctx) {
                final mintColor = Theme.of(ctx).brightness == Brightness.dark
                    ? AppTheme.colorMintDark
                    : AppTheme.colorMintDeep;
                return TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    ref.read(selectedDateProvider.notifier).state =
                        DateTime(now.year, now.month, now.day);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: mintColor,
                  ),
                  child: Text(
                    '오늘',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      color: mintColor,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showDatePicker(
      BuildContext context, WidgetRef ref, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: '날짜를 선택하세요',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
    }
  }
}
