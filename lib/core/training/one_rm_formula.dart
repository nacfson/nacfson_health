import 'dart:math' as math;

/// 1RM 추정 공식 — Supabase `one_rm_formulas.formula_type` + `coefficients` 로
/// 표현 가능한 4가지 형태를 지원한다. 알려진 공식 매핑:
///   - epley       : Epley(k=1/30), O'Conner(k=0.025)
///   - linear      : Brzycki(a=1.0278, b=0.0278), Lander(a=1.013, b=0.0267123)
///   - exponential : Mayhew(상체), Wathen(하체)
///   - polynomial  : Lombardi(p=0.10)
sealed class OneRMFormulaSpec {
  const OneRMFormulaSpec();

  /// 잘못된 입력은 0 또는 weight 를 반환한다 (UI 가 "—" 처리).
  /// 계수 누락/NaN/Infinity 가 발생할 수 있으므로 호출부는 결과 검증 권장.
  double calculate(double weight, int reps);

  /// `formula_type` + `coefficients` 로 spec 을 생성한다.
  /// 알 수 없는 type 또는 필수 키 누락 시 `null` 반환.
  static OneRMFormulaSpec? parse(String type, Map<String, dynamic> coefficients) {
    try {
      switch (type) {
        case 'epley':
          final k = (coefficients['k'] as num?)?.toDouble();
          if (k == null) return null;
          return EpleySpec(k: k);
        case 'linear':
          final a = (coefficients['a'] as num?)?.toDouble();
          final b = (coefficients['b'] as num?)?.toDouble();
          if (a == null || b == null) return null;
          return LinearSpec(a: a, b: b);
        case 'exponential':
          final a = (coefficients['a'] as num?)?.toDouble();
          final b = (coefficients['b'] as num?)?.toDouble();
          final c = (coefficients['c'] as num?)?.toDouble();
          final k = (coefficients['k'] as num?)?.toDouble();
          if (a == null || b == null || c == null || k == null) return null;
          return ExponentialSpec(a: a, b: b, c: c, k: k);
        case 'polynomial':
          final p = (coefficients['p'] as num?)?.toDouble();
          if (p == null) return null;
          return PolynomialSpec(p: p);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

/// W × (1 + k × R)
class EpleySpec extends OneRMFormulaSpec {
  final double k;
  const EpleySpec({required this.k});

  @override
  double calculate(double weight, int reps) {
    if (reps <= 0) return 0;
    if (reps == 1) return weight;
    final result = weight * (1 + k * reps);
    return result.isFinite ? result : weight;
  }
}

/// W / (a − b × R)
class LinearSpec extends OneRMFormulaSpec {
  final double a;
  final double b;
  const LinearSpec({required this.a, required this.b});

  @override
  double calculate(double weight, int reps) {
    if (reps <= 0) return 0;
    if (reps == 1) return weight;
    final denom = a - b * reps;
    if (denom <= 0) return weight;
    final result = weight / denom;
    return result.isFinite ? result : weight;
  }
}

/// (a × W) / (b + c × exp(k × R))
class ExponentialSpec extends OneRMFormulaSpec {
  final double a;
  final double b;
  final double c;
  final double k;
  const ExponentialSpec({
    required this.a,
    required this.b,
    required this.c,
    required this.k,
  });

  @override
  double calculate(double weight, int reps) {
    if (reps <= 0) return 0;
    if (reps == 1) return weight;
    final denom = b + c * math.exp(k * reps);
    if (denom <= 0) return weight;
    final result = (a * weight) / denom;
    return result.isFinite ? result : weight;
  }
}

/// W × R^p
class PolynomialSpec extends OneRMFormulaSpec {
  final double p;
  const PolynomialSpec({required this.p});

  @override
  double calculate(double weight, int reps) {
    if (reps <= 0) return 0;
    if (reps == 1) return weight;
    final result = weight * math.pow(reps, p);
    return result.isFinite ? result.toDouble() : weight;
  }
}

/// 등록된 공식이 있을 때만 e1RM 을 계산. 미등록이면 `null` 반환 (UI 가 칩을 숨김).
double? calculateE1RMWithFormula(OneRMFormulaSpec? spec, double weight, int reps) {
  if (spec == null) return null;
  if (reps <= 0 || weight <= 0) return null;
  final result = spec.calculate(weight, reps);
  if (!result.isFinite || result <= 0) return null;
  return result;
}
