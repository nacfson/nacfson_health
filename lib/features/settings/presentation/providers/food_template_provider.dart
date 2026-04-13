import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/food_template_repository.dart';
import '../../data/repositories/sqlite_food_template_repository.dart';
import '../../domain/entities/food_template.dart';

final foodTemplateRepositoryProvider =
    Provider<FoodTemplateRepository>((ref) {
  return SqliteFoodTemplateRepository();
});

final foodTemplatesProvider =
    StateNotifierProvider<FoodTemplateNotifier, List<FoodTemplate>>((ref) {
  return FoodTemplateNotifier(ref.watch(foodTemplateRepositoryProvider));
});

class FoodTemplateNotifier extends StateNotifier<List<FoodTemplate>> {
  final FoodTemplateRepository _repository;

  FoodTemplateNotifier(this._repository) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _repository.getAll();
  }

  /// 동기화 완료 후 DB에서 최신 상태를 다시 로드합니다.
  Future<void> refresh() => _load();

  Future<void> addTemplate(FoodTemplate template) async {
    await _repository.add(template);
    state = await _repository.getAll();
  }

  Future<void> deleteTemplate(String uuid) async {
    await _repository.delete(uuid);
    state = await _repository.getAll();
  }
}
