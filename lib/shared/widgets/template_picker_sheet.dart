import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

/// 운동/식단 템플릿을 선택하는 공통 BottomSheet 피커.
///
/// - 기본 상태에서는 폼에 노출되지 않고, 입력 필드의 suffixIcon을 통해서만 호출됩니다.
/// - [groupKeyOf]가 주어지면 상단에 그룹 ChoiceChip 필터가 표시됩니다 (운동 부위).
/// - [subtitleOf]가 주어지면 아이템 하위 텍스트로 표시됩니다 (식단 영양 요약).
/// - [templatesListenable] 로 Provider 를 넘기면 시트가 열린 동안 외부 상태 변경이
///   `ref.watch` 로 즉시 반영되고, 카드 등장 시 staggered fade-in 이 적용됩니다.
Future<T?> showTemplatePickerSheet<T>({
  required BuildContext context,
  required String title,
  required ProviderListenable<List<T>> templatesListenable,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  String Function(T)? groupKeyOf,
  String? initialGroupKey,
  String emptyHint = '등록된 템플릿이 없습니다.',
  VoidCallback? onEmptyAction,
  String onEmptyActionLabel = '템플릿 관리로 이동',
  VoidCallback? onDirectInput,
  String directInputLabel = '직접 입력',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
    // BottomNavShell 의 glassmorphic 하단 탭 바가 시트를 가리지 않는다.
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => _TemplatePickerSheet<T>(
      title: title,
      templatesListenable: templatesListenable,
      labelOf: labelOf,
      subtitleOf: subtitleOf,
      groupKeyOf: groupKeyOf,
      initialGroupKey: initialGroupKey,
      emptyHint: emptyHint,
      onEmptyAction: onEmptyAction,
      onEmptyActionLabel: onEmptyActionLabel,
      onDirectInput: onDirectInput,
      directInputLabel: directInputLabel,
    ),
  );
}

class _TemplatePickerSheet<T> extends ConsumerStatefulWidget {
  final String title;
  final ProviderListenable<List<T>> templatesListenable;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final String Function(T)? groupKeyOf;
  final String? initialGroupKey;
  final String emptyHint;
  final VoidCallback? onEmptyAction;
  final String onEmptyActionLabel;
  final VoidCallback? onDirectInput;
  final String directInputLabel;

  const _TemplatePickerSheet({
    required this.title,
    required this.templatesListenable,
    required this.labelOf,
    this.subtitleOf,
    this.groupKeyOf,
    this.initialGroupKey,
    required this.emptyHint,
    this.onEmptyAction,
    required this.onEmptyActionLabel,
    this.onDirectInput,
    required this.directInputLabel,
  });

  @override
  ConsumerState<_TemplatePickerSheet<T>> createState() =>
      _TemplatePickerSheetState<T>();
}

class _TemplatePickerSheetState<T>
    extends ConsumerState<_TemplatePickerSheet<T>> {
  final _searchController = TextEditingController();
  String? _selectedGroup;
  String _query = '';
  // 시트가 열린 직후 한 번만 staggered 등장 애니메이션을 재생한다.
  // 검색어 입력/지우기로 인한 재빌드에서는 애니메이션이 다시 튀지 않도록 이 플래그를 false 로 내림.
  bool _animateOnFirstBuild = true;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialGroupKey;
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _groupKeys(List<T> templates) {
    if (widget.groupKeyOf == null) return const [];
    final set = <String>{};
    for (final t in templates) {
      final k = widget.groupKeyOf!(t);
      if (k.isNotEmpty) set.add(k);
    }
    return set.toList()..sort();
  }

  List<T> _filtered(List<T> templates) {
    return templates.where((t) {
      if (widget.groupKeyOf != null && _selectedGroup != null) {
        if (widget.groupKeyOf!(t) != _selectedGroup) return false;
      }
      if (_query.isNotEmpty &&
          !widget.labelOf(t).toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final templates = ref.watch(widget.templatesListenable);
    final groups = _groupKeys(templates);
    final items = _filtered(templates);
    // 카드 등장 애니메이션은 시트가 열린 후 첫 렌더에서만 실행.
    // 검색·필터 조작이나 외부 state 변경으로 인한 재빌드에서는 카드가 다시 튀지 않도록 한다.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shouldAnimate = _animateOnFirstBuild && !reduceMotion;
    if (shouldAnimate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateOnFirstBuild = false;
      });
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (widget.onDirectInput != null)
                      TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(widget.directInputLabel),
                        onPressed: () async {
                          // BottomSheet exit 애니메이션이 끝난 다음에 후속 다이얼로그를 push.
                          // 동기 호출 시 시트 슬라이드다운 + 다이얼로그 페이드인 + 키보드 슬라이드업이
                          // 동시 재생되어 UI 가 겹쳐 보임 (race).
                          final action = widget.onDirectInput;
                          Navigator.pop(context);
                          if (action != null) {
                            await Future.delayed(const Duration(milliseconds: 220));
                            action();
                          }
                        },
                      ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '이름으로 검색',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: groups.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final isAll = _selectedGroup == null;
                          return ChoiceChip(
                            label: const Text('전체'),
                            selected: isAll,
                            onSelected: (v) {
                              if (v) setState(() => _selectedGroup = null);
                            },
                          );
                        }
                        final group = groups[index - 1];
                        final selected = _selectedGroup == group;
                        return ChoiceChip(
                          label: Text(group),
                          selected: selected,
                          onSelected: (v) {
                            setState(() => _selectedGroup = v ? group : null);
                          },
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyState(
                          hint: templates.isEmpty
                              ? widget.emptyHint
                              : '검색 결과가 없습니다.',
                          actionLabel:
                              templates.isEmpty ? widget.onEmptyActionLabel : null,
                          onAction: templates.isEmpty ? widget.onEmptyAction : null,
                        )
                      : _TemplateList<T>(
                          items: items,
                          scrollController: scrollController,
                          labelOf: widget.labelOf,
                          subtitleOf: widget.subtitleOf,
                          animate: shouldAnimate,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TemplateList<T> extends StatelessWidget {
  final List<T> items;
  final ScrollController scrollController;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final bool animate;

  const _TemplateList({
    required this.items,
    required this.scrollController,
    required this.labelOf,
    required this.subtitleOf,
    required this.animate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tileFor(int i) {
      final t = items[i];
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        title: Text(labelOf(t)),
        subtitle: subtitleOf == null
            ? null
            : Text(
                subtitleOf!(t),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
        onTap: () => Navigator.pop(context, t),
      );
    }

    final separator = Divider(
      height: 1,
      color: cs.outlineVariant.withValues(alpha: 0.4),
    );

    if (!animate) {
      return ListView.separated(
        controller: scrollController,
        itemCount: items.length,
        separatorBuilder: (_, _) => separator,
        itemBuilder: (context, i) => tileFor(i),
      );
    }

    return AnimationLimiter(
      child: ListView.separated(
        controller: scrollController,
        itemCount: items.length,
        separatorBuilder: (_, _) => separator,
        itemBuilder: (context, i) => AnimationConfiguration.staggeredList(
          position: i,
          duration: const Duration(milliseconds: 320),
          child: SlideAnimation(
            verticalOffset: 16,
            child: FadeInAnimation(child: tileFor(i)),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({required this.hint, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            hint,
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(context);
                onAction!();
              },
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
