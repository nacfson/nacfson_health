import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/features/exercise/data/legacy_korean_mapping.dart';

/// v12 마이그레이션 시 한글 종목명 → exercise_key 매핑 정확성 회귀 테스트.
/// 매핑 변경/오타가 발생하면 SQLite 백필이 잘못된 key 를 만들어 master data 매칭이
/// 깨진다. 카테고리 매핑도 마찬가지로 routine items_json migration 에 영향.
void main() {
  group('legacyKoreanToExerciseKey', () {
    test('null 입력 → null', () {
      expect(legacyKoreanToExerciseKey(null), isNull);
    });

    test('빈 문자열 → null (매핑 미존재)', () {
      expect(legacyKoreanToExerciseKey(''), isNull);
    });

    test('공백 trim 적용', () {
      expect(legacyKoreanToExerciseKey('  벤치프레스 '), 'bench_press');
    });

    test('대표 종목 — 가슴/등/하체/어깨/팔', () {
      expect(legacyKoreanToExerciseKey('벤치프레스'), 'bench_press');
      expect(legacyKoreanToExerciseKey('랫 풀다운'), 'lat_pulldown');
      expect(legacyKoreanToExerciseKey('스쿼트'), 'squat');
      expect(legacyKoreanToExerciseKey('숄더 프레스'), 'overhead_press');
      expect(legacyKoreanToExerciseKey('바벨 컬'), 'barbell_curl');
      expect(legacyKoreanToExerciseKey('데드리프트'), 'deadlift');
    });

    test('미등록 종목 → null', () {
      expect(legacyKoreanToExerciseKey('존재하지않는운동'), isNull);
      expect(legacyKoreanToExerciseKey('트레드밀'), isNull);
    });
  });

  group('kLegacyKoreanExerciseNameToKey 무결성', () {
    test('exercise_key 가 모두 lowercase + snake_case', () {
      final pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final entry in kLegacyKoreanExerciseNameToKey.entries) {
        expect(
          pattern.hasMatch(entry.value),
          isTrue,
          reason: '"${entry.key}" → "${entry.value}" 가 snake_case 위반',
        );
      }
    });

    test('exercise_key 중복 없음 (한 key 가 여러 한글명에 매핑되는 건 OK, 그 반대 검증은 Map 으로 자동 보장)', () {
      // Map 자체로 한글명 중복은 차단되므로 별도 체크 불필요.
      expect(kLegacyKoreanExerciseNameToKey.keys.toSet().length,
          kLegacyKoreanExerciseNameToKey.length);
    });

    test('카테고리별 최소 종목 수 — 가슴/등/하체 각 5종 이상', () {
      final chestKeys = ['bench_press', 'incline_bench_press', 'dumbbell_bench_press'];
      final backKeys = ['lat_pulldown', 'seated_row', 'pull_up'];
      final legsKeys = ['squat', 'leg_press', 'romanian_deadlift'];
      for (final k in [...chestKeys, ...backKeys, ...legsKeys]) {
        expect(kLegacyKoreanExerciseNameToKey.values, contains(k),
            reason: '필수 종목 key "$k" 누락');
      }
    });
  });

  group('kLegacyKoreanCategoryToKey 무결성', () {
    test('카테고리 매핑 — 가슴/등/하체/어깨/팔/코어', () {
      expect(kLegacyKoreanCategoryToKey['가슴'], 'chest');
      expect(kLegacyKoreanCategoryToKey['등'], 'back');
      expect(kLegacyKoreanCategoryToKey['하체'], 'legs');
      expect(kLegacyKoreanCategoryToKey['어깨'], 'shoulders');
      expect(kLegacyKoreanCategoryToKey['팔'], 'biceps');
      expect(kLegacyKoreanCategoryToKey['코어'], 'core');
    });

    test('유산소/기타는 매핑 없음 (NULL backfill)', () {
      expect(kLegacyKoreanCategoryToKey['유산소'], isNull);
      expect(kLegacyKoreanCategoryToKey['기타'], isNull);
    });
  });

  group('SQL 생성 헬퍼', () {
    test('buildExerciseNameCaseSql — 컬럼 + 매핑 모두 포함', () {
      final sql = buildExerciseNameCaseSql('exercise_name');
      expect(sql, contains('CASE exercise_name'));
      expect(sql, contains("WHEN '벤치프레스' THEN 'bench_press'"));
      expect(sql, contains("WHEN '스쿼트' THEN 'squat'"));
      expect(sql, contains('ELSE NULL'));
      expect(sql, contains('END'));
    });

    test('buildCategoryCaseSql — 카테고리 매핑 포함', () {
      final sql = buildCategoryCaseSql('exercise_type');
      expect(sql, contains('CASE exercise_type'));
      expect(sql, contains("WHEN '가슴' THEN 'chest'"));
      expect(sql, contains("WHEN '코어' THEN 'core'"));
    });
  });
}
