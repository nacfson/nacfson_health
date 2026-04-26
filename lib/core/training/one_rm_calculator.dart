/// 1RM 추정 + 입력 신뢰도 + % 환산 무게 산출.
///
/// 공식: Epley
///   e1RM = weight × (1 + reps / 30)   (reps == 1 인 경우 weight 그대로)
library;

double calculateE1RM(double weight, int reps) {
  if (reps <= 0) return 0;
  if (reps == 1) return weight;
  return weight * (1 + reps / 30);
}

/// 입력 reps 에 따른 추정 신뢰도(%).
/// reps 가 적을수록 1RM 추정 정확도가 높다 (NSCA 가이드 기준).
int inputConfidencePercent(int reps) {
  if (reps <= 5) return 96;
  if (reps <= 8) return 92;
  if (reps <= 12) return 85;
  return 72;
}

/// 신뢰도 등급 안내 문구 (HTML 190~193 행 톤).
String confidenceBand(int reps) {
  if (reps <= 5) return '5회 이하 — 추정 정확도 높음';
  if (reps <= 8) return '6~8회 — 표준 추정 구간';
  if (reps <= 12) return '9~12회 — 약간의 오차 있음';
  return '12회 초과 — 추정 정확도 낮음';
}

/// % of 1RM 환산표용. 결과는 2.5kg 단위로 반올림.
double weightForPercentage(double e1RM, int percent) {
  final raw = e1RM * percent / 100;
  return (raw / 2.5).round() * 2.5;
}
