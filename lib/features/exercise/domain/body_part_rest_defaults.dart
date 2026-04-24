import '../../settings/domain/entities/exercise_template.dart';

/// 근비대 목표 기준 부위별 권장 휴식 시간(초).
///
/// 리서치 기반 고정 상수 — 사용자가 앱 설정으로 바꿀 수 없다. 종목마다 다르게
/// 주고 싶으면 `ExerciseTemplate.restSecondsOverride` 로 덮어쓴다.
///
/// - 유산소는 `null` — 휴식 타이머 자체를 시작하지 않는다.
/// - 매핑에 없는 부위(비어있거나 알 수 없음)는 "기타"의 값(90초)을 돌려준다.
const Map<String, int?> kBodyPartDefaultRestSeconds = {
  '하체': 180,
  '등': 150,
  '가슴': 120,
  '어깨': 90,
  '팔': 60,
  '코어': 60,
  '유산소': null,
  '기타': 90,
};

/// 입력 범위(클램프) — 사용자 커스텀 오버라이드 시에도 이 범위를 벗어나지 않는다.
const int kMinRestSeconds = 60;
const int kMaxRestSeconds = 300;

/// "기타" 폴백 값. 모든 부위 매핑이 유효하지 않을 때 마지막 안전망.
const int kFallbackRestSeconds = 90;

/// 부위 문자열 → 기본 휴식 초.
///
/// 반환 `null` 은 "휴식 타이머 미사용" 시그널(유산소).
int? defaultRestForBodyPart(String bodyPart) {
  if (kBodyPartDefaultRestSeconds.containsKey(bodyPart)) {
    return kBodyPartDefaultRestSeconds[bodyPart];
  }
  return kFallbackRestSeconds;
}

/// 템플릿의 실제 적용 휴식 시간을 계산한다.
///
/// 우선순위: `restSecondsOverride` > 부위 기본값 > "기타" 폴백.
/// 유산소 부위이고 override 도 없으면 `null` — 호출 측은 타이머 시작을 건너뛴다.
int? resolveRestSeconds(ExerciseTemplate template) {
  final override = template.restSecondsOverride;
  if (override != null) return override;
  return defaultRestForBodyPart(template.exerciseType);
}
