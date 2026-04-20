import 'routine_item.dart';

/// 특정 일자의 계획된 운동 목록. 로컬 전용 — 서버 동기화하지 않음.
/// `date`는 `YYYY-MM-DD` 문자열(KST 자정 기준)로 직렬화된다.
class DailyRoutine {
  final int? id;
  final DateTime date; // 자정으로 정규화된 로컬 날짜
  final List<RoutineItem> items;
  final DateTime updatedAt;

  const DailyRoutine({
    this.id,
    required this.date,
    required this.items,
    required this.updatedAt,
  });

  DailyRoutine copyWith({
    int? id,
    DateTime? date,
    List<RoutineItem>? items,
    DateTime? updatedAt,
  }) {
    return DailyRoutine(
      id: id ?? this.id,
      date: date ?? this.date,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String formatDate(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }

  static DateTime parseDate(String text) {
    final parts = text.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
