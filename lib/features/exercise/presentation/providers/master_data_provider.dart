import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/training/one_rm_formula.dart';
import '../../data/repositories/sqlite_master_data_repository.dart';
import '../../domain/entities/exercise_category.dart';
import '../../domain/entities/exercise_definition.dart';
import '../../domain/entities/exercise_translation.dart';
import '../../domain/entities/one_rm_formula.dart';
import '../../domain/repositories/master_data_repository.dart';

final masterDataRepositoryProvider = Provider<MasterDataRepository>((ref) {
  return SqliteMasterDataRepository();
});

/// 현재 앱 locale (`'ko'` / `'en'`). v12 는 ko/en 만 지원, 그 외는 'en' fallback.
final currentLocaleProvider = Provider<String>((ref) {
  // 빌드타임에는 BuildContext 가 없으므로 ref.watch 로 강제 갱신은 못 한다.
  // UI 측에서 Localizations.localeOf(context) 를 명시 override 가능.
  final defaultLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final lang = defaultLocale.languageCode;
  return lang == 'ko' ? 'ko' : 'en';
});

/// 1RM 코치/운동 입력 화면 진입 시 한 번 read 되어 TTL 체크.
final masterDataBundleProvider =
    FutureProvider.autoDispose<MasterDataBundle>((ref) async {
  final repo = ref.read(masterDataRepositoryProvider);
  final locale = ref.watch(currentLocaleProvider);

  // TTL 체크 + 필요 시 Supabase fetch. 오프라인이면 캐시 사용.
  try {
    await repo.ensureFresh();
  } catch (_) {
    // 오프라인: 기존 캐시 사용
  }

  final results = await Future.wait([
    repo.getCategories(),
    repo.getCategoryTranslations(locale),
    repo.getDefinitions(),
    repo.getTranslations(locale),
    repo.getFormulas(),
    repo.lastFetchedAt(),
  ]);

  return MasterDataBundle(
    locale: locale,
    categories: results[0] as List<ExerciseCategory>,
    categoryTranslations: results[1] as List<ExerciseCategoryTranslation>,
    definitions: results[2] as List<ExerciseDefinition>,
    translations: results[3] as List<ExerciseTranslation>,
    formulas: results[4] as List<OneRMFormula>,
    lastFetchedAt: results[5] as DateTime?,
  );
}, name: 'masterDataBundleProvider');

/// `exercise_key` → `OneRMFormulaSpec` 매핑 (계산 가능한 spec 만).
final oneRMFormulaSpecMapProvider =
    FutureProvider.autoDispose<Map<String, OneRMFormulaSpec>>((ref) async {
  final bundle = await ref.watch(masterDataBundleProvider.future);
  final result = <String, OneRMFormulaSpec>{};
  for (final f in bundle.formulas) {
    final spec = f.toSpec();
    if (spec != null) result[f.exerciseKey] = spec;
  }
  return result;
});

/// `exercise_key` → 표시명 (현재 locale 기준).
final exerciseDisplayNameProvider =
    FutureProvider.autoDispose<String Function(String exerciseKey)>(
        (ref) async {
  final bundle = await ref.watch(masterDataBundleProvider.future);
  final translationMap = <String, String>{
    for (final t in bundle.translations) t.exerciseKey: t.displayName
  };
  final defaultMap = <String, String>{
    for (final d in bundle.definitions) d.exerciseKey: d.defaultName
  };
  return (String exerciseKey) =>
      translationMap[exerciseKey] ??
      defaultMap[exerciseKey] ??
      exerciseKey;
});

class MasterDataBundle {
  final String locale;
  final List<ExerciseCategory> categories;
  final List<ExerciseCategoryTranslation> categoryTranslations;
  final List<ExerciseDefinition> definitions;
  final List<ExerciseTranslation> translations;
  final List<OneRMFormula> formulas;
  final DateTime? lastFetchedAt;

  const MasterDataBundle({
    required this.locale,
    required this.categories,
    required this.categoryTranslations,
    required this.definitions,
    required this.translations,
    required this.formulas,
    required this.lastFetchedAt,
  });

  /// 등록된 종목 수. 빈 데이터 (첫 로드 실패) 인지 판정 용도.
  bool get isEmpty => definitions.isEmpty;
}
