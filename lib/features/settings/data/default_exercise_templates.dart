/// 앱 최초 실행 시 자동으로 시드되는 기본 운동 템플릿.
///
/// 유명 헬스장에 100% 있는 머신/기본 종목으로 구성.
/// 시드는 결정론적 UUID v5(이름 기반)로 생성되어 다중 기기 간 자연 dedup.
class DefaultExerciseTemplateSeed {
  final String name;
  final String exerciseType;
  const DefaultExerciseTemplateSeed(this.name, this.exerciseType);
}

const kDefaultExerciseTemplates = <DefaultExerciseTemplateSeed>[
  // 가슴
  DefaultExerciseTemplateSeed('벤치프레스', '가슴'),
  DefaultExerciseTemplateSeed('체스트 프레스', '가슴'),
  DefaultExerciseTemplateSeed('펙덱 플라이', '가슴'),
  // 등
  DefaultExerciseTemplateSeed('랫 풀다운', '등'),
  DefaultExerciseTemplateSeed('시티드 로우', '등'),
  // 하체
  DefaultExerciseTemplateSeed('스쿼트', '하체'),
  DefaultExerciseTemplateSeed('레그 프레스', '하체'),
  DefaultExerciseTemplateSeed('레그 익스텐션', '하체'),
  DefaultExerciseTemplateSeed('레그 컬', '하체'),
  // 어깨
  DefaultExerciseTemplateSeed('숄더 프레스', '어깨'),
  DefaultExerciseTemplateSeed('사이드 레터럴 레이즈', '어깨'),
  // 팔
  DefaultExerciseTemplateSeed('바벨 컬', '팔'),
  DefaultExerciseTemplateSeed('트라이셉 푸쉬다운', '팔'),
  // 코어
  DefaultExerciseTemplateSeed('플랭크', '코어'),
  // 유산소
  DefaultExerciseTemplateSeed('트레드밀', '유산소'),
  DefaultExerciseTemplateSeed('사이클', '유산소'),
];
