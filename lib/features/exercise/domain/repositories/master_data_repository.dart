import '../entities/exercise_category.dart';
import '../entities/exercise_definition.dart';
import '../entities/exercise_translation.dart';
import '../entities/one_rm_formula.dart';

/// admin-curated master 운동 데이터 + 1RM 공식 저장소.
///
/// 일반 sync 사이클(`sync_state.dart`)과 분리된 **TTL 24h pull-only** 캐시.
/// 1RM 코치 / 운동 입력 화면 진입 시 ensureFresh() 호출.
abstract class MasterDataRepository {
  /// 마지막 fetch 가 24h 이전이면 Supabase 에서 5 테이블 병렬 fetch 후 SQLite replace.
  /// 오프라인이면 기존 캐시 그대로 사용 (last_fetched_at 갱신 안 함).
  /// `forceRefresh=true` 면 TTL 무시하고 강제 fetch.
  Future<void> ensureFresh({bool forceRefresh = false});

  Future<List<ExerciseCategory>> getCategories();
  Future<List<ExerciseCategoryTranslation>> getCategoryTranslations(String locale);
  Future<List<ExerciseDefinition>> getDefinitions();
  Future<List<ExerciseTranslation>> getTranslations(String locale);
  Future<List<OneRMFormula>> getFormulas();

  /// 마지막 성공 fetch 시각. 한 번도 fetch 한 적 없으면 null.
  Future<DateTime?> lastFetchedAt();
}
