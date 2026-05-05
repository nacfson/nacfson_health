import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/exercise_definition.dart';
import '../../domain/entities/exercise_translation.dart';
import '../providers/master_data_provider.dart';

/// `exercise_definitions` 기반 운동 종목 선택 결과.
class ExercisePickResult {
  final String exerciseKey;
  final String displayName;
  final String categoryKey;

  /// 기존 한글 부위 (`exercise_records.exercise_type`, `exercise_templates.exerciseType` 컬럼용).
  /// `categoryKey` 를 8개 한글 부위로 축약 매핑한 값.
  final String legacyExerciseType;

  const ExercisePickResult({
    required this.exerciseKey,
    required this.displayName,
    required this.categoryKey,
    required this.legacyExerciseType,
  });
}

/// `category_key` → legacy 8개 한글 부위 매핑.
/// v11 까지의 `exercise_records.exercise_type` 컬럼이 한글 부위명으로 저장돼 있으므로
/// 신규 입력 시에도 동일 분포를 유지하기 위해 다대일 축약을 사용한다.
String legacyTypeForCategory(String categoryKey) {
  switch (categoryKey) {
    case 'chest':
      return '가슴';
    case 'back':
      return '등';
    case 'legs':
    case 'glutes':
    case 'calves':
      return '하체';
    case 'shoulders':
      return '어깨';
    case 'biceps':
    case 'triceps':
    case 'forearms':
      return '팔';
    case 'core':
      return '코어';
    case 'olympic':
      return '기타';
    default:
      return '기타';
  }
}

/// 등록된 운동 종목만 선택할 수 있는 검색·자동완성 필드.
///
/// - 입력어를 displayName / aliases / exercise_key 에서 prefix 또는 contains 매칭.
/// - 매칭 결과를 칩 리스트로 노출. 칩 탭 시 `onPicked` 호출.
/// - master data 가 비어있으면 (오프라인 첫 진입) 안내 + 비활성.
///
/// 부위(legacy exerciseType) 는 picker 가 자동으로 채우므로 호출자는 별도 부위 입력
/// UI 를 둘 필요가 없다.
class ExercisePickerField extends ConsumerStatefulWidget {
  /// 사용자가 종목을 선택했을 때 호출.
  final ValueChanged<ExercisePickResult> onPicked;

  /// 초기 검색어 (예: 검색 탭에서 추가 탭으로 prefill).
  final String? initialQuery;

  /// 이미 사용 중이라 다시 선택할 수 없는 종목 키 (예: 이미 보유한 템플릿).
  /// 칩이 disabled 로 표시되고 helper 메시지가 노출된다.
  final Set<String> disabledKeys;

  /// 비어있는 상태에서 표시할 hint 텍스트.
  final String hintText;

  /// 검색창 자동 포커스 여부.
  final bool autofocus;

  const ExercisePickerField({
    super.key,
    required this.onPicked,
    this.initialQuery,
    this.disabledKeys = const {},
    this.hintText = '운동 이름을 입력하세요 (예: 벤치프레스)',
    this.autofocus = false,
  });

  @override
  ConsumerState<ExercisePickerField> createState() =>
      _ExercisePickerFieldState();
}

class _ExercisePickerFieldState extends ConsumerState<ExercisePickerField> {
  late final TextEditingController _ctrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery ?? '');
    _query = (widget.initialQuery ?? '').trim();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bundleAsync = ref.watch(masterDataBundleProvider);

    return bundleAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '운동 목록을 불러올 수 없습니다.\n네트워크 연결 후 다시 시도해주세요.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
        ),
      ),
      data: (bundle) {
        if (bundle.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '아직 운동 목록이 다운로드되지 않았습니다.\n네트워크에 연결한 뒤 다시 시도해주세요.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          );
        }

        final matches = _matchExercises(bundle);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: widget.autofocus,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '검색어 지우기',
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            _buildResults(theme, matches),
          ],
        );
      },
    );
  }

  Widget _buildResults(ThemeData theme, List<_Match> matches) {
    final cs = theme.colorScheme;
    if (_query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          '운동 이름을 입력하면 등록된 종목 목록이 표시됩니다.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    if (matches.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12),
        child: Text(
          '"$_query" 와 매칭되는 등록된 운동이 없습니다.\n등록된 운동만 추가할 수 있습니다.',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in matches)
              ActionChip(
                avatar: const Icon(Icons.fitness_center, size: 16),
                label: Text(
                  '${m.displayName} · ${legacyTypeForCategory(m.categoryKey)}',
                ),
                onPressed: widget.disabledKeys.contains(m.exerciseKey)
                    ? null
                    : () => widget.onPicked(ExercisePickResult(
                          exerciseKey: m.exerciseKey,
                          displayName: m.displayName,
                          categoryKey: m.categoryKey,
                          legacyExerciseType:
                              legacyTypeForCategory(m.categoryKey),
                        )),
              ),
          ],
        ),
      ),
    );
  }

  List<_Match> _matchExercises(MasterDataBundle bundle) {
    if (_query.isEmpty) return const [];
    final q = _query.toLowerCase();

    final translationsByKey = <String, ExerciseTranslation>{};
    for (final t in bundle.translations) {
      translationsByKey[t.exerciseKey] = t;
    }

    final defByKey = <String, ExerciseDefinition>{};
    for (final d in bundle.definitions) {
      defByKey[d.exerciseKey] = d;
    }

    final scored = <(_Match, int)>[];
    for (final d in bundle.definitions) {
      final t = translationsByKey[d.exerciseKey];
      final displayName = t?.displayName ?? d.defaultName;
      final aliases = t?.aliases ?? const <String>[];

      final candidates = <String>[
        displayName.toLowerCase(),
        d.defaultName.toLowerCase(),
        d.exerciseKey.toLowerCase(),
        ...aliases.map((a) => a.toLowerCase()),
      ];

      int? bestScore;
      for (final c in candidates) {
        if (c.startsWith(q)) {
          bestScore = (bestScore == null || bestScore > 0) ? 0 : bestScore;
        } else if (c.contains(q)) {
          bestScore = bestScore ?? 1;
        }
      }
      if (bestScore != null) {
        scored.add((
          _Match(
            exerciseKey: d.exerciseKey,
            displayName: displayName,
            categoryKey: d.categoryKey,
          ),
          bestScore,
        ));
      }
    }

    scored.sort((a, b) {
      final byScore = a.$2.compareTo(b.$2);
      if (byScore != 0) return byScore;
      return a.$1.displayName.compareTo(b.$1.displayName);
    });

    return scored.take(40).map((e) => e.$1).toList();
  }
}

class _Match {
  final String exerciseKey;
  final String displayName;
  final String categoryKey;
  const _Match({
    required this.exerciseKey,
    required this.displayName,
    required this.categoryKey,
  });
}
