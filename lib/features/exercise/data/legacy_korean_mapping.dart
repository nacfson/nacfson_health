/// v11 까지 사용한 한글 종목명 → exercise_key 매핑.
///
/// v12 마이그레이션 시 SQLite의 exercise_records / exercise_templates /
/// workout_routines.items_json / daily_routine.items_json 의 한글명을
/// exercise_key 로 변환하는데 사용.
///
/// `default_exercise_templates.dart` 의 52개 + 자주 쓰이는 별칭 매핑.
const Map<String, String> kLegacyKoreanExerciseNameToKey = {
  // 가슴 (8)
  '벤치프레스': 'bench_press',
  '인클라인 벤치프레스': 'incline_bench_press',
  '디클라인 벤치프레스': 'decline_bench_press',
  '덤벨 벤치프레스': 'dumbbell_bench_press',
  '인클라인 덤벨 프레스': 'incline_dumbbell_press',
  '체스트 프레스': 'machine_chest_press',
  '펙덱 플라이': 'pec_deck_fly',
  '케이블 크로스오버': 'cable_crossover',
  // 등 (9)
  '랫 풀다운': 'lat_pulldown',
  '시티드 로우': 'seated_row',
  '바벨 로우': 'barbell_row',
  '덤벨 로우': 'dumbbell_row',
  '티바 로우': 't_bar_row',
  '펜들레이 로우': 'pendlay_row',
  '풀업': 'pull_up',
  '케이블 로우': 'cable_row',
  '페이스 풀': 'face_pull',
  // 하체 (10)
  '스쿼트': 'squat',
  '프론트 스쿼트': 'front_squat',
  '핵스쿼트': 'hack_squat',
  '레그 프레스': 'leg_press',
  '레그 익스텐션': 'leg_extension',
  '레그 컬': 'leg_curl',
  '루마니안 데드리프트': 'romanian_deadlift',
  '런지': 'lunge',
  '불가리안 스플릿 스쿼트': 'bulgarian_split_squat',
  '카프 레이즈': 'standing_calf_raise',
  // 어깨 (7)
  '숄더 프레스': 'overhead_press',
  '덤벨 숄더 프레스': 'dumbbell_shoulder_press',
  '사이드 레터럴 레이즈': 'lateral_raise',
  '프론트 레이즈': 'front_raise',
  '리어 델트 플라이': 'rear_delt_fly',
  '업라이트 로우': 'upright_row',
  '슈러그': 'shrug',
  // 팔 (9)
  '바벨 컬': 'barbell_curl',
  '덤벨 컬': 'dumbbell_curl',
  '해머 컬': 'hammer_curl',
  '프리처 컬': 'preacher_curl',
  '케이블 컬': 'cable_curl',
  '트라이셉 푸쉬다운': 'triceps_pushdown',
  '케이블 오버헤드 익스텐션': 'overhead_cable_extension',
  '스컬 크러셔': 'skull_crusher',
  '딥스': 'triceps_dip',
  // 코어 (5)
  '플랭크': 'plank',
  '크런치': 'crunch',
  '행잉 레그 레이즈': 'hanging_leg_raise',
  '러시안 트위스트': 'russian_twist',
  '앱 롤아웃': 'ab_rollout',
  // 기타 (4)
  '데드리프트': 'deadlift',
  '파워 클린': 'power_clean',
  '케틀벨 스윙': 'kettlebell_swing',
  '박스 점프': 'box_jump',
  // 유산소 (4) — exercise_key 없음 (1RM 컨텍스트 외)
  // '트레드밀', '사이클', '로잉 머신', '일립티컬' → 매핑 안 함 (NULL)
};

/// v11 까지 사용한 한글 카테고리(exercise_type) → category_key 매핑.
const Map<String, String> kLegacyKoreanCategoryToKey = {
  '가슴': 'chest',
  '등': 'back',
  '하체': 'legs',
  '어깨': 'shoulders',
  '팔': 'biceps', // 정확 매핑 어려움 — 이두/삼두/전완 혼재. 사용자 수동 정정 가능
  '코어': 'core',
  // '유산소': null — 매핑 안 함
  // '기타': null — 종목별 카테고리 별도 매핑됨 (데드리프트→back, 케틀벨→olympic 등)
};

/// 런타임 fallback (Supabase translation 누락 시 한글명 → key 추정).
String? legacyKoreanToExerciseKey(String? koreanName) {
  if (koreanName == null) return null;
  return kLegacyKoreanExerciseNameToKey[koreanName.trim()];
}

/// SQL CASE 문 생성 헬퍼 — 마이그레이션 SQL 작성용.
///
/// 결과 예: "CASE exercise_name WHEN '벤치프레스' THEN 'bench_press' ... END"
String buildExerciseNameCaseSql(String columnName) {
  final whenClauses = kLegacyKoreanExerciseNameToKey.entries
      .map((e) => "WHEN '${e.key}' THEN '${e.value}'")
      .join('\n        ');
  return '''CASE $columnName
        $whenClauses
        ELSE NULL
      END''';
}

String buildCategoryCaseSql(String columnName) {
  final whenClauses = kLegacyKoreanCategoryToKey.entries
      .map((e) => "WHEN '${e.key}' THEN '${e.value}'")
      .join('\n        ');
  return '''CASE $columnName
        $whenClauses
        ELSE NULL
      END''';
}
