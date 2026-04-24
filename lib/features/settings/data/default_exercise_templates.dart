/// 앱 최초 실행 시 자동으로 시드되는 기본 운동 템플릿.
///
/// 유명 헬스장에 대부분 있는 머신/프리웨이트/케이블 종목 중심으로 구성.
/// 시드는 결정론적 UUID v5(이름 기반)로 생성되어 다중 기기 간 자연 dedup.
class DefaultExerciseTemplateSeed {
  final String name;
  final String exerciseType;
  const DefaultExerciseTemplateSeed(this.name, this.exerciseType);
}

const kDefaultExerciseTemplates = <DefaultExerciseTemplateSeed>[
  // 가슴 (8)
  DefaultExerciseTemplateSeed('벤치프레스', '가슴'),
  DefaultExerciseTemplateSeed('인클라인 벤치프레스', '가슴'),
  DefaultExerciseTemplateSeed('디클라인 벤치프레스', '가슴'),
  DefaultExerciseTemplateSeed('덤벨 벤치프레스', '가슴'),
  DefaultExerciseTemplateSeed('인클라인 덤벨 프레스', '가슴'),
  DefaultExerciseTemplateSeed('체스트 프레스', '가슴'),
  DefaultExerciseTemplateSeed('펙덱 플라이', '가슴'),
  DefaultExerciseTemplateSeed('케이블 크로스오버', '가슴'),
  // 등 (9)
  DefaultExerciseTemplateSeed('랫 풀다운', '등'),
  DefaultExerciseTemplateSeed('시티드 로우', '등'),
  DefaultExerciseTemplateSeed('바벨 로우', '등'),
  DefaultExerciseTemplateSeed('덤벨 로우', '등'),
  DefaultExerciseTemplateSeed('티바 로우', '등'),
  DefaultExerciseTemplateSeed('펜들레이 로우', '등'),
  DefaultExerciseTemplateSeed('풀업', '등'),
  DefaultExerciseTemplateSeed('케이블 로우', '등'),
  DefaultExerciseTemplateSeed('페이스 풀', '등'),
  // 하체 (10)
  DefaultExerciseTemplateSeed('스쿼트', '하체'),
  DefaultExerciseTemplateSeed('프론트 스쿼트', '하체'),
  DefaultExerciseTemplateSeed('핵스쿼트', '하체'),
  DefaultExerciseTemplateSeed('레그 프레스', '하체'),
  DefaultExerciseTemplateSeed('레그 익스텐션', '하체'),
  DefaultExerciseTemplateSeed('레그 컬', '하체'),
  DefaultExerciseTemplateSeed('루마니안 데드리프트', '하체'),
  DefaultExerciseTemplateSeed('런지', '하체'),
  DefaultExerciseTemplateSeed('불가리안 스플릿 스쿼트', '하체'),
  DefaultExerciseTemplateSeed('카프 레이즈', '하체'),
  // 어깨 (7)
  DefaultExerciseTemplateSeed('숄더 프레스', '어깨'),
  DefaultExerciseTemplateSeed('덤벨 숄더 프레스', '어깨'),
  DefaultExerciseTemplateSeed('사이드 레터럴 레이즈', '어깨'),
  DefaultExerciseTemplateSeed('프론트 레이즈', '어깨'),
  DefaultExerciseTemplateSeed('리어 델트 플라이', '어깨'),
  DefaultExerciseTemplateSeed('업라이트 로우', '어깨'),
  DefaultExerciseTemplateSeed('슈러그', '어깨'),
  // 팔 (9)
  DefaultExerciseTemplateSeed('바벨 컬', '팔'),
  DefaultExerciseTemplateSeed('덤벨 컬', '팔'),
  DefaultExerciseTemplateSeed('해머 컬', '팔'),
  DefaultExerciseTemplateSeed('프리처 컬', '팔'),
  DefaultExerciseTemplateSeed('케이블 컬', '팔'),
  DefaultExerciseTemplateSeed('트라이셉 푸쉬다운', '팔'),
  DefaultExerciseTemplateSeed('케이블 오버헤드 익스텐션', '팔'),
  DefaultExerciseTemplateSeed('스컬 크러셔', '팔'),
  DefaultExerciseTemplateSeed('딥스', '팔'),
  // 코어 (5)
  DefaultExerciseTemplateSeed('플랭크', '코어'),
  DefaultExerciseTemplateSeed('크런치', '코어'),
  DefaultExerciseTemplateSeed('행잉 레그 레이즈', '코어'),
  DefaultExerciseTemplateSeed('러시안 트위스트', '코어'),
  DefaultExerciseTemplateSeed('앱 롤아웃', '코어'),
  // 유산소 (4)
  DefaultExerciseTemplateSeed('트레드밀', '유산소'),
  DefaultExerciseTemplateSeed('사이클', '유산소'),
  DefaultExerciseTemplateSeed('로잉 머신', '유산소'),
  DefaultExerciseTemplateSeed('일립티컬', '유산소'),
  // 기타 (4)
  DefaultExerciseTemplateSeed('데드리프트', '기타'),
  DefaultExerciseTemplateSeed('파워 클린', '기타'),
  DefaultExerciseTemplateSeed('케틀벨 스윙', '기타'),
  DefaultExerciseTemplateSeed('박스 점프', '기타'),
];
