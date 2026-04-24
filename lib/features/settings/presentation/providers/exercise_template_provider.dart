import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/default_exercise_templates.dart';
import '../../data/repositories/exercise_template_repository.dart';
import '../../data/repositories/sqlite_exercise_template_repository.dart';
import '../../domain/entities/exercise_template.dart';

/// 템플릿 시드 플래그 읽기/쓰기에 사용. main.dart에서 override 필수.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences는 main.dart에서 오버라이드해야 합니다');
});

final exerciseTemplateRepositoryProvider =
    Provider<ExerciseTemplateRepository>((ref) {
  return SqliteExerciseTemplateRepository();
});

final exerciseTemplatesProvider =
    StateNotifierProvider<ExerciseTemplateNotifier, List<ExerciseTemplate>>(
        (ref) {
  return ExerciseTemplateNotifier(
    ref.watch(exerciseTemplateRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

class ExerciseTemplateNotifier
    extends StateNotifier<List<ExerciseTemplate>> {
  /// main.dart 의 사전 시드 루틴과 공유하는 SharedPreferences 키.
  static const seedFlagKey = 'exercise_templates_default_seeded_v2';

  final ExerciseTemplateRepository _repository;
  final SharedPreferences _prefs;

  ExerciseTemplateNotifier(this._repository, this._prefs) : super([]) {
    _bootstrap();
  }

  /// main.dart 에서 SQLite `getAll()` 결과를 사전 로드한 뒤 주입하는 생성자.
  /// `_bootstrap()` 을 호출하지 않으므로 첫 프레임부터 최신 상태를 가진다.
  ExerciseTemplateNotifier.withInitial(
    this._repository,
    this._prefs,
    List<ExerciseTemplate> initial,
  ) : super(initial);

  Future<void> _bootstrap() async {
    state = await _repository.getAll();
    await _maybeSeedDefaults();
  }

  Future<void> _maybeSeedDefaults() async {
    if (_prefs.getBool(seedFlagKey) ?? false) return;
    final inserted = await _repository.seedDefaults(kDefaultExerciseTemplates);
    await _prefs.setBool(seedFlagKey, true);
    if (inserted > 0) {
      state = await _repository.getAll();
    }
  }

  /// 동기화 완료 후 DB에서 최신 상태를 다시 로드합니다.
  Future<void> refresh() async {
    state = await _repository.getAll();
  }

  Future<void> addTemplate(String name, String exerciseType) async {
    await _repository.add(ExerciseTemplate(
      uuid: '',
      name: name,
      exerciseType: exerciseType,
      updatedAt: DateTime.now(),
    ));
    state = await _repository.getAll();
  }

  Future<void> deleteTemplate(String uuid) async {
    await _repository.delete(uuid);
    state = await _repository.getAll();
  }

  /// 종목별 휴식 시간 오버라이드 업데이트. [seconds] 가 null 이면 부위 기본값으로 복귀.
  Future<void> updateRestOverride(String uuid, int? seconds) async {
    await _repository.updateRestOverride(uuid, seconds);
    state = await _repository.getAll();
  }
}
