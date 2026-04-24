import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../../exercise/domain/body_part_rest_defaults.dart';
import '../../domain/entities/exercise_template.dart';
import '../providers/exercise_template_provider.dart';

const _exerciseTypes = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];

class ExerciseTemplateCard extends ConsumerStatefulWidget {
  const ExerciseTemplateCard({super.key});

  @override
  ConsumerState<ExerciseTemplateCard> createState() =>
      _ExerciseTemplateCardState();
}

class _ExerciseTemplateCardState extends ConsumerState<ExerciseTemplateCard> {
  late final TextEditingController _templateNameCtrl;
  late final TextEditingController _searchCtrl;
  String _searchQuery = '';
  String? _selectedFilterType; // null = 전체
  String? _selectedExerciseTypeForAdd;

  @override
  void initState() {
    super.initState();
    _templateNameCtrl = TextEditingController();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _templateNameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTemplate() async {
    final name = _templateNameCtrl.text.trim();
    if (name.isEmpty) {
      ErrorOverlay.show(title: '입력 오류', message: '운동 이름을 입력해주세요.');
      return;
    }
    final type = _selectedExerciseTypeForAdd ?? _selectedFilterType;
    if (type == null) {
      ErrorOverlay.show(title: '입력 오류', message: '운동 유형을 선택해주세요.');
      return;
    }

    final templates = ref.read(exerciseTemplatesProvider);
    if (templates.any((t) => t.name == name)) {
      ErrorOverlay.show(title: '중복 오류', message: '이미 있는 템플릿입니다.');
      return;
    }

    try {
      await ref
          .read(exerciseTemplatesProvider.notifier)
          .addTemplate(name, type);
      _templateNameCtrl.clear();
    } catch (e) {
      debugPrint('ExerciseTemplateCard._addTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(title: '저장 실패', message: '템플릿 추가 중 오류가 발생했습니다: $e');
      }
    }
  }

  Future<void> _deleteTemplate(String uuid) async {
    try {
      await ref.read(exerciseTemplatesProvider.notifier).deleteTemplate(uuid);
    } catch (e) {
      debugPrint('ExerciseTemplateCard._deleteTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(title: '삭제 실패', message: '템플릿 삭제 중 오류가 발생했습니다: $e');
      }
    }
  }

  Future<void> _editRestOverride(ExerciseTemplate template) async {
    final result = await showModalBottomSheet<_RestEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // BottomNavShell glassmorphic 탭바 위로 시트를 올린다.
      useRootNavigator: true,
      builder: (_) => _RestOverrideSheet(template: template),
    );
    if (result == null) return;
    try {
      await ref
          .read(exerciseTemplatesProvider.notifier)
          .updateRestOverride(template.uuid, result.overrideSeconds);
    } catch (e) {
      debugPrint('ExerciseTemplateCard._editRestOverride error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(title: '저장 실패', message: '휴식 시간 변경 중 오류가 발생했습니다: $e');
      }
    }
  }

  bool _matchesSearch(ExerciseTemplate t) {
    if (_searchQuery.isEmpty) return true;
    return t.name.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final templates = ref.watch(exerciseTemplatesProvider);

    // 부위 필터 + 검색어 적용
    final filtered = templates.where((t) {
      if (_selectedFilterType != null &&
          t.exerciseType != _selectedFilterType) {
        return false;
      }
      return _matchesSearch(t);
    }).toList();

    // 전체 필터일 때만 부위별로 그룹 헤더 표시
    final grouped = <String, List<ExerciseTemplate>>{};
    if (_selectedFilterType == null) {
      for (final type in _exerciseTypes) {
        final items = filtered.where((t) => t.exerciseType == type).toList();
        if (items.isNotEmpty) grouped[type] = items;
      }
    }

    final addType = _selectedExerciseTypeForAdd ?? _selectedFilterType;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: cs.primary),
                const SizedBox(width: 8),
                Text('운동 템플릿', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '자주 사용하는 운동을 미리 등록하세요. 칩을 탭하면 휴식 시간을 조정할 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '이름으로 검색',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _exerciseTypes.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isAll = _selectedFilterType == null;
                    return ChoiceChip(
                      label: const Text('전체'),
                      selected: isAll,
                      onSelected: (v) {
                        if (v) setState(() => _selectedFilterType = null);
                      },
                    );
                  }
                  final type = _exerciseTypes[index - 1];
                  final selected = _selectedFilterType == type;
                  return ChoiceChip(
                    label: Text('$type · ${_restBadgeForType(type)}'),
                    selected: selected,
                    onSelected: (v) {
                      setState(() =>
                          _selectedFilterType = v ? type : null);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  templates.isEmpty
                      ? '등록된 운동 템플릿이 없습니다. 아래에서 추가하세요.'
                      : '검색 결과가 없습니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else if (_selectedFilterType == null)
              for (final entry in grouped.entries) ...[
                Text(
                  '[${entry.key}]  ${_restBadgeForType(entry.key)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in entry.value)
                      InputChip(
                        label: Text(_chipLabel(t)),
                        onPressed: () => _editRestOverride(t),
                        onDeleted: () => _deleteTemplate(t.uuid),
                        deleteIcon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ]
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in filtered)
                    InputChip(
                      label: Text(_chipLabel(t)),
                      onPressed: () => _editRestOverride(t),
                      onDeleted: () => _deleteTemplate(t.uuid),
                      deleteIcon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              '운동 유형 선택',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final type in _exerciseTypes)
                  ChoiceChip(
                    label: Text(type),
                    selected: addType == type,
                    onSelected: (v) {
                      setState(() {
                        _selectedExerciseTypeForAdd = v ? type : null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _templateNameCtrl,
                    decoration: InputDecoration(
                      hintText: '운동 이름 입력',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _addTemplate(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addTemplate,
                  icon: const Icon(Icons.add),
                  tooltip: '템플릿 추가',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 칩 라벨 — 템플릿 이름 뒤에 실제 적용되는 휴식 시간 표시.
  /// 유산소는 타이머를 사용하지 않으므로 "-" 로 표시.
  String _chipLabel(ExerciseTemplate t) {
    final sec = resolveRestSeconds(t);
    if (sec == null) return '${t.name} · 휴식 없음';
    final tag = t.restSecondsOverride == null ? '기본' : '커스텀';
    return '${t.name} · ${_fmtRest(sec)} ($tag)';
  }

  String _restBadgeForType(String type) {
    final sec = defaultRestForBodyPart(type);
    return sec == null ? '휴식 없음' : '기본 ${_fmtRest(sec)}';
  }

  String _fmtRest(int seconds) {
    if (seconds < 60) return '$seconds초';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '$m분' : '$m분 $s초';
  }
}

class _RestEditResult {
  final int? overrideSeconds; // null = 부위 기본값으로 복귀
  const _RestEditResult(this.overrideSeconds);
}

/// 템플릿별 휴식 시간 조정 BottomSheet.
///
/// - 슬라이더(60~300초, 15초 단위) + 직접 입력 필드
/// - "부위 기본값으로 되돌리기" 버튼으로 override 제거
/// - 유산소 부위는 기본값이 없으므로 override 가 있어야만 타이머 사용
class _RestOverrideSheet extends StatefulWidget {
  final ExerciseTemplate template;
  const _RestOverrideSheet({required this.template});

  @override
  State<_RestOverrideSheet> createState() => _RestOverrideSheetState();
}

class _RestOverrideSheetState extends State<_RestOverrideSheet> {
  late int _currentSeconds; // 슬라이더 값 — 항상 유효 범위 내
  late final TextEditingController _textCtrl;
  late final int? _bodyPartDefault;

  @override
  void initState() {
    super.initState();
    _bodyPartDefault = defaultRestForBodyPart(widget.template.exerciseType);
    final initial = widget.template.restSecondsOverride ??
        _bodyPartDefault ??
        kFallbackRestSeconds;
    _currentSeconds = initial.clamp(kMinRestSeconds, kMaxRestSeconds);
    _textCtrl = TextEditingController(text: _currentSeconds.toString());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _setSeconds(int seconds, {bool syncText = true}) {
    final clamped = seconds.clamp(kMinRestSeconds, kMaxRestSeconds);
    setState(() => _currentSeconds = clamped);
    if (syncText) _textCtrl.text = clamped.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAerobic = widget.template.exerciseType == '유산소';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.template.name,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            isAerobic
                ? '유산소는 기본적으로 휴식 타이머를 사용하지 않습니다. 커스텀 값을 넣으면 활성화됩니다.'
                : '부위 기본값: $_bodyPartDefault초. 슬라이더로 이 종목에만 적용되는 휴식 시간을 설정하세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: kMinRestSeconds.toDouble(),
                  max: kMaxRestSeconds.toDouble(),
                  divisions:
                      (kMaxRestSeconds - kMinRestSeconds) ~/ 15, // 15초 단위
                  value: _currentSeconds.toDouble(),
                  label: _fmt(_currentSeconds),
                  onChanged: (v) => _setSeconds(v.round()),
                ),
              ),
              // 숫자 3자리(예: 120) 가 잘리지 않도록 72 → 96 으로 확장하고,
              // 단위 "초" 는 suffixText 대신 외부 Text 위젯으로 분리.
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _textCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(isDense: true),
                  onSubmitted: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null) _setSeconds(parsed);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text('초', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$kMinRestSeconds~$kMaxRestSeconds초 범위에서 선택하세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.template.restSecondsOverride != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(const _RestEditResult(null));
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('부위 기본값'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () {
                  // 텍스트 필드에 반영되지 않은 숫자 반영.
                  final parsed = int.tryParse(_textCtrl.text);
                  final finalSec =
                      (parsed ?? _currentSeconds).clamp(kMinRestSeconds, kMaxRestSeconds);
                  // 입력값이 부위 기본값과 같으면 override 제거(불필요한 저장 방지).
                  final override =
                      (finalSec == _bodyPartDefault) ? null : finalSec;
                  Navigator.of(context).pop(_RestEditResult(override));
                },
                child: const Text('저장'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(int s) {
    if (s < 60) return '$s초';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '$m분' : '$m분 $r초';
  }
}
