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
  static const _seedFlagKey = 'exercise_templates_default_seeded_v1';

  final ExerciseTemplateRepository _repository;
  final SharedPreferences _prefs;

  ExerciseTemplateNotifier(this._repository, this._prefs) : super([]) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    state = await _repository.getAll();
    await _maybeSeedDefaults();
  }

  Future<void> _maybeSeedDefaults() async {
    if (_prefs.getBool(_seedFlagKey) ?? false) return;
    final inserted = await _repository.seedDefaults(kDefaultExerciseTemplates);
    await _prefs.setBool(_seedFlagKey, true);
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
}
