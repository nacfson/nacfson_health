import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../../exercise/domain/body_part_rest_defaults.dart';
import '../../../exercise/presentation/widgets/exercise_picker_field.dart';
import '../../domain/entities/exercise_template.dart';
import '../providers/exercise_template_provider.dart';

enum _TemplateTab { search, add }

/// 검색 / 추가 탭 분리 (SegmentedButton):
///   - 검색 탭: 검색창에 입력해야만 매칭 칩 노출. 매칭 0 이면 "추가 탭으로 이동" 링크.
///   - 추가 탭: 이름 입력 + 부위 ChoiceChip. 이미 보유한 이름이면 인라인 헬퍼 + 추가 버튼 disabled.
///   - 두 탭 모두 펼침/드롭다운 없이 항상 본문이 노출됨.
class ExerciseTemplateCard extends ConsumerStatefulWidget {
  const ExerciseTemplateCard({super.key});

  @override
  ConsumerState<ExerciseTemplateCard> createState() =>
      _ExerciseTemplateCardState();
}

class _ExerciseTemplateCardState extends ConsumerState<ExerciseTemplateCard> {
  _TemplateTab _tab = _TemplateTab.search;

  // 검색 탭 state
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  bool _searchFocused = false;

  // 추가 탭 state — picker 의 초기 검색어 (검색 탭에서 prefill 시 사용)
  String? _addInitialQuery;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _switchTab(_TemplateTab tab, {String? prefillName}) {
    setState(() {
      _tab = tab;
      if (prefillName != null) {
        _addInitialQuery = prefillName;
      }
    });
  }

  Future<void> _addFromPicker(ExercisePickResult picked) async {
    final templates = ref.read(exerciseTemplatesProvider);
    if (templates.any((t) => t.name == picked.displayName)) {
      ErrorOverlay.show(
        title: '중복',
        message: '"${picked.displayName}" 은(는) 이미 등록된 템플릿입니다.',
      );
      return;
    }
    try {
      await ref
          .read(exerciseTemplatesProvider.notifier)
          .addTemplate(picked.displayName, picked.legacyExerciseType);
      if (mounted) {
        setState(() => _addInitialQuery = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${picked.displayName}" 템플릿이 추가되었습니다'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('ExerciseTemplateCard._addFromPicker error: $e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final templates = ref.watch(exerciseTemplatesProvider);

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
              '검색 탭에서 등록된 운동을 찾고, 추가 탭에서 새 템플릿을 등록합니다.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_TemplateTab>(
                segments: const [
                  ButtonSegment(
                    value: _TemplateTab.search,
                    label: Text('검색'),
                    icon: Icon(Icons.search, size: 18),
                  ),
                  ButtonSegment(
                    value: _TemplateTab.add,
                    label: Text('추가'),
                    icon: Icon(Icons.add, size: 18),
                  ),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _switchTab(v.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_tab == _TemplateTab.search)
              _buildSearchTab(theme, templates)
            else
              _buildAddTab(theme, templates),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(ThemeData theme, List<ExerciseTemplate> templates) {
    final cs = theme.colorScheme;
    final hasQuery = _searchQuery.isNotEmpty;
    // 비어있으면 전체 노출, 검색어가 있으면 prefix(startsWith) 매칭만 노출.
    final visible = hasQuery
        ? templates
            .where((t) =>
                t.name.toLowerCase().startsWith(_searchQuery.toLowerCase()))
            .toList()
        : templates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: '운동 이름으로 시작 검색',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: hasQuery
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '검색어 지우기',
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
        // 검색창 포커스 시에만 TextField 아래로 결과 영역 노출 (드롭다운).
        // 결과는 maxHeight 안에서 스크롤(드래그) 가능.
        if (_searchFocused) ...[
          const SizedBox(height: 8),
          if (visible.isNotEmpty)
            Container(
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
                    for (final t in visible)
                      InputChip(
                        label: Text(_chipLabel(t)),
                        onPressed: () => _editRestOverride(t),
                        onDeleted: () => _deleteTemplate(t.uuid),
                        deleteIcon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
              ),
            )
          else if (hasQuery)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '검색 결과가 없습니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _switchTab(_TemplateTab.add,
                          prefillName: _searchQuery),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text("'$_searchQuery' 추가 탭으로 이동"),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Text(
                '등록된 운동 템플릿이 없습니다. 추가 탭에서 등록하세요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAddTab(ThemeData theme, List<ExerciseTemplate> templates) {
    final cs = theme.colorScheme;
    final disabledKeys = <String>{
      // 이미 보유한 템플릿은 displayName 기준이므로 picker disabledKeys 에 직접
      // exerciseKey 매핑이 어렵다. 대신 _addFromPicker 단계에서 displayName 중복 체크.
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '등록된 운동만 템플릿으로 추가할 수 있습니다. 부위는 자동으로 분류됩니다.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ExercisePickerField(
          key: ValueKey(_addInitialQuery ?? ''),
          initialQuery: _addInitialQuery,
          disabledKeys: disabledKeys,
          hintText: '운동 이름을 입력하세요 (예: 벤치프레스)',
          onPicked: _addFromPicker,
        ),
        if (templates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '현재 ${templates.length}개의 템플릿이 등록되어 있습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 칩 라벨 — 템플릿 이름 뒤에 실제 적용되는 휴식 시간 표시.
  /// 유산소는 타이머를 사용하지 않으므로 "휴식 없음" 으로 표시.
  String _chipLabel(ExerciseTemplate t) {
    final sec = resolveRestSeconds(t);
    if (sec == null) return '${t.name} · 휴식 없음';
    final tag = t.restSecondsOverride == null ? '기본' : '커스텀';
    return '${t.name} · ${_fmtRest(sec)} ($tag)';
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
