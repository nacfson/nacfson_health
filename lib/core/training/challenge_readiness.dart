/// 1RM 도전 가능 여부 판단 (신호등).
///
/// 입력: 종목별 PR 추세 + 최근 7/14일 강도 통계
/// 출력: ReadinessLevel + 헤드라인 + 사유 한 줄
library;

enum ReadinessLevel { green, amber, red, gray }

class ReadinessAssessment {
  final ReadinessLevel level;
  final String headline;
  final String reason;

  const ReadinessAssessment(this.level, this.headline, this.reason);
}

class ReadinessInput {
  /// 주차별 max e1RM. null = 해당 주에 work/drop 세트 없음.
  /// 인덱스 0 = 가장 오래된 주, 마지막 = 이번 주.
  final List<double?> weeklyHistory;

  /// 최근 7일 work 세트 개수.
  final int recentWorkSetCount;

  /// 최근 7일 RPE 평균. null = RPE 데이터 없음.
  final double? recentRpeAvg;

  /// 최근 14일 failure 세트 개수.
  final int recentFailureCount;

  const ReadinessInput({
    required this.weeklyHistory,
    required this.recentWorkSetCount,
    required this.recentRpeAvg,
    required this.recentFailureCount,
  });
}

ReadinessAssessment assessReadiness(ReadinessInput input) {
  final weekly = input.weeklyHistory;
  final nonNull = weekly.where((e) => e != null).length;
  final cur = weekly.isNotEmpty ? weekly.last : null;

  // 1) 데이터 부족 — 비교 기준 자체가 없음
  if (cur == null || nonNull < 2) {
    return const ReadinessAssessment(
      ReadinessLevel.gray,
      '데이터 부족',
      '같은 종목으로 2~3세션 더 쌓고 다시 확인해 보세요',
    );
  }

  // 2주 전 슬롯 (마지막에서 3번째). 길이가 짧으면 가장 오래된 슬롯 사용.
  final twoIdx = weekly.length - 3;
  final twoWeeksAgo = twoIdx >= 0 ? weekly[twoIdx] : weekly.first;

  final trendUp = (twoWeeksAgo != null) && cur > twoWeeksAgo + 1.0;
  final trendDown = (twoWeeksAgo != null) && cur < twoWeeksAgo - 1.0;

  final rpe = input.recentRpeAvg;
  final rpeHigh = rpe != null && rpe > 9.0;
  final rpeMid = rpe != null && rpe > 8.5;

  final tooManyFails = input.recentFailureCount >= 2;
  final lowVolume = input.recentWorkSetCount < 2;

  // 2) 적색 — 회복 우선
  if (trendDown || rpeHigh || tooManyFails) {
    return const ReadinessAssessment(
      ReadinessLevel.red,
      '회복 우선',
      '최근 강도가 높거나 추세가 꺾였어요. 1~2주 회복 후 도전 권장',
    );
  }

  // 3) 황색 — 1주 더 쌓고
  if (!trendUp || lowVolume || rpeMid) {
    return const ReadinessAssessment(
      ReadinessLevel.amber,
      '1주 더 쌓고',
      '추세가 평탄해요. 본세트 2~3회 더 누적 후 도전 권장',
    );
  }

  // 4) 녹색 — 도전 적절
  return const ReadinessAssessment(
    ReadinessLevel.green,
    'PR 도전 적절',
    '추세 상승 + 최근 강도 안정. 가벼운 1RM 시도 가능',
  );
}
