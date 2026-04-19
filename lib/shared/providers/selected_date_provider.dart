import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 전역 선택 날짜 상태 (Observer 패턴)
///
/// 운동/식단/요약 탭이 이 Provider를 watch하여 해당 날짜의 데이터를 표시합니다.
/// 날짜 변경 시 모든 하위 Provider가 자동으로 갱신됩니다 (Riverpod의 반응형 체인).
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day); // 자정으로 정규화
});

/// 선택된 날짜가 오늘인지 판별하는 유틸리티 Provider
final isSelectedDateTodayProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedDateProvider);
  final now = DateTime.now();
  return selected.year == now.year &&
      selected.month == now.month &&
      selected.day == now.day;
});
