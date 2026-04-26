/// 종목별 PR (Personal Record) 요약.
///
/// e1RM (예상 1RM, Epley) 추세 + 최근 강도 통계.
/// null 슬롯/필드는 "데이터 없음" 의미 — 0 으로 두면 신규 종목에서 오도성 변화량 배지가 뜬다.
class PrSummary {
  final String exerciseName;

  /// 종목 부위 (가슴/등/하체/...). 가장 최근 기록의 값.
  /// null = 해당 종목 기록이 전혀 없음.
  final String? exerciseType;

  /// 이번 주 max e1RM. null = 이번 주 work/drop 세트 없음.
  final double? currentE1RM;

  /// `weeklyHistory` 의 첫 슬롯 (가장 오래된 주 = 4주 전 기준). null = 해당 주 데이터 없음.
  final double? fourWeeksAgoE1RM;

  /// 5주치 주차별 max e1RM. 인덱스 0 = 가장 오래된 주, last = 이번 주.
  /// null = 해당 주에 work/drop 세트 없음.
  final List<double?> weeklyHistory;

  /// 최근 7일 work 세트 개수.
  final int recentWorkSetCount;

  /// 최근 7일 RPE 평균. null = RPE 데이터 없음.
  final double? recentRpeAvg;

  /// 최근 14일 failure 세트 개수.
  final int recentFailureCount;

  final DateTime lastUpdated;

  const PrSummary({
    required this.exerciseName,
    required this.exerciseType,
    required this.currentE1RM,
    required this.fourWeeksAgoE1RM,
    required this.weeklyHistory,
    required this.recentWorkSetCount,
    required this.recentRpeAvg,
    required this.recentFailureCount,
    required this.lastUpdated,
  });

  /// 4주 전 대비 변화량(kg). 어느 한쪽이라도 null 이면 null.
  double? get deltaKg {
    final cur = currentE1RM;
    final past = fourWeeksAgoE1RM;
    if (cur == null || past == null) return null;
    return cur - past;
  }
}
