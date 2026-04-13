import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/exercise_template_repository.dart';
import '../../data/repositories/sqlite_exercise_template_repository.dart';
import '../../domain/entities/exercise_template.dart';

final exerciseTemplateRepositoryProvider =
    Provider<ExerciseTemplateRepository>((ref) {
  return SqliteExerciseTemplateRepository();
});

final exerciseTemplatesProvider =
    StateNotifierProvider<ExerciseTemplateNotifier, List<ExerciseTemplate>>(
        (ref) {
  return ExerciseTemplateNotifier(
      ref.watch(exerciseTemplateRepositoryProvider));
});

class ExerciseTemplateNotifier
    extends StateNotifier<List<ExerciseTemplate>> {
  final ExerciseTemplateRepository _repository;

  ExerciseTemplateNotifier(this._repository) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _repository.getAll();
  }

  /// 동기화 완료 후 DB에서 최신 상태를 다시 로드합니다.
  Future<void> refresh() => _load();

  Future<void> addTemplate(String name) async {
    await _repository.add(ExerciseTemplate(
      uuid: '',
      name: name,
      updatedAt: DateTime.now(),
    ));
    state = await _repository.getAll();
  }

  Future<void> deleteTemplate(String uuid) async {
    await _repository.delete(uuid);
    state = await _repository.getAll();
  }
}
