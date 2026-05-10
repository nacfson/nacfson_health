/// Atwater 계수 (탄 4 / 단 4 / 지 9 kcal/g) 로 매크로에서 kcal 산출.
/// v12-5 부터 식단 입력 폼에서 사용자가 kcal 을 직접 입력하지 않고 이 함수로 자동 계산한다.
///
/// 비유한값(NaN/Infinity)·음수는 0 으로 안전 변환한다 — 호출부 validator·
/// inputFormatter 가 1차 차단하지만, 외부 키보드/복붙·미래 호출자 보호를 위해
/// 함수 자체에서도 가드한다.
int kcalFromMacros(double carbs, double protein, double fat) {
  if (!carbs.isFinite || !protein.isFinite || !fat.isFinite) return 0;
  if (carbs < 0 || protein < 0 || fat < 0) return 0;
  return (carbs * 4 + protein * 4 + fat * 9).round();
}
