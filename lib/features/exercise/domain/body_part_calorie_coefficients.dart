/// 부위별 운동 칼로리 추정 계수.
///
/// 볼륨 기반 칼로리 추정식 `kcal = 볼륨(kg) × kKcalPerKgVolume × 부위계수` 의
/// 부위계수 부분이다. 큰 근육군(하체/등/가슴) 일수록 산소섭취량이 높다는
/// Robergs(2007) 등의 관찰을 바탕으로 한 휴리스틱 — 학술 표는 존재하지 않으므로
/// 절대값보다는 상대 비율로 해석할 것.
///
/// - 유산소 = 0.0: 볼륨 공식이 부적합. 활동 칼로리(워치 active energy)에 위임.
/// - 키는 `body_part_rest_defaults.dart` 의 부위 enum 과 동일하게 유지.
const Map<String, double> kBodyPartCalorieCoefficient = {
  '하체': 1.00,
  '등': 0.85,
  '가슴': 0.85,
  '어깨': 0.60,
  '팔': 0.60,
  '코어': 0.50,
  '유산소': 0.00,
  '기타': 0.70,
};

/// "기타" 폴백 — 매핑에 없는 부위 문자열에 적용.
const double kFallbackCalorieCoefficient = 0.70;

/// 1kg 볼륨당 환산 칼로리 (Scott 2011 상한 + 업계 관행 절충).
/// UI 노출 후 사용자 피드백으로 캘리브레이션할 것.
const double kKcalPerKgVolume = 0.01;

/// 부위 문자열 → 칼로리 계수.
double calorieCoefficientFor(String bodyPart) {
  return kBodyPartCalorieCoefficient[bodyPart] ?? kFallbackCalorieCoefficient;
}
