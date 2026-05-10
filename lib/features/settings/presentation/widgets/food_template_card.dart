import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/nutrition/atwater_calculator.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../domain/entities/food_template.dart';
import '../providers/food_template_provider.dart';

enum _TemplateTab { search, add }

/// 검색 / 추가 탭 분리 (SegmentedButton):
///   - 검색 탭: 검색창에 입력해야만 매칭 ListTile 노출. 매칭 0 이면 "추가 탭으로 이동" 링크.
///   - 추가 탭: 이름 + 매크로 입력. 이미 보유한 이름이면 인라인 헬퍼 + 추가 버튼 disabled.
///   - 두 탭 모두 펼침/드롭다운 없이 항상 본문이 노출됨.
class FoodTemplateCard extends ConsumerStatefulWidget {
  const FoodTemplateCard({super.key});

  @override
  ConsumerState<FoodTemplateCard> createState() => _FoodTemplateCardState();
}

class _FoodTemplateCardState extends ConsumerState<FoodTemplateCard> {
  _TemplateTab _tab = _TemplateTab.search;

  // 검색 탭 state
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  bool _searchFocused = false;

  // 추가 탭 state
  late final TextEditingController _addNameCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  String _addName = '';
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _addNameCtrl = TextEditingController();
    _carbsCtrl = TextEditingController();
    _proteinCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    _addNameCtrl.dispose();
    _carbsCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  /// 현재 매크로 컨트롤러 값으로부터 Atwater 계수로 kcal 산출.
  int get _derivedCalories {
    double parse(TextEditingController c) =>
        double.tryParse(c.text.trim()) ?? 0;
    return kcalFromMacros(
      parse(_carbsCtrl),
      parse(_proteinCtrl),
      parse(_fatCtrl),
    );
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
        _addNameCtrl.text = prefillName;
        _addNameCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: prefillName.length),
        );
        _addName = prefillName;
      }
    });
  }

  static final _macroInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  String? _macroValidator(String? v) {
    final raw = v?.trim() ?? '';
    final n = double.tryParse(raw);
    if (n == null || !n.isFinite || n < 0 || n > 999) return '0-999';
    return null;
  }

  Future<void> _addTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _addName.trim();
    if (name.isEmpty) {
      ErrorOverlay.show(title: '입력 오류', message: '음식 이름을 입력해주세요.');
      return;
    }
    final carbs = double.tryParse(_carbsCtrl.text.trim()) ?? 0;
    final protein = double.tryParse(_proteinCtrl.text.trim()) ?? 0;
    final fat = double.tryParse(_fatCtrl.text.trim()) ?? 0;
    final calories = kcalFromMacros(carbs, protein, fat);

    final templates = ref.read(foodTemplatesProvider);
    if (templates.any((t) => t.name == name)) {
      // 버튼 disabled 가드를 우회한 경우의 안전망.
      ErrorOverlay.show(title: '중복 오류', message: '이미 보유한 템플릿입니다.');
      return;
    }

    try {
      await ref.read(foodTemplatesProvider.notifier).addTemplate(
            FoodTemplate(
              uuid: '',
              name: name,
              calories: calories,
              carbs: carbs,
              protein: protein,
              fat: fat,
              updatedAt: DateTime.now(),
            ),
          );
      _addNameCtrl.clear();
      _carbsCtrl.clear();
      _proteinCtrl.clear();
      _fatCtrl.clear();
      if (mounted) {
        setState(() => _addName = '');
      }
    } catch (e) {
      debugPrint('FoodTemplateCard._addTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '저장 실패',
          message: '음식 템플릿 추가 중 오류가 발생했습니다: $e',
        );
      }
    }
  }

  Future<void> _deleteTemplate(String uuid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"$name"을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(foodTemplatesProvider.notifier).deleteTemplate(uuid);
    } catch (e) {
      debugPrint('FoodTemplateCard._deleteTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '삭제 실패',
          message: '음식 템플릿 삭제 중 오류가 발생했습니다: $e',
        );
      }
    }
  }

  String _formatMacro(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: cs.primary),
                const SizedBox(width: 8),
                Text('음식 템플릿', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '검색 탭에서 등록된 음식을 찾고, 추가 탭에서 새 템플릿을 등록합니다.',
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
              _buildSearchTab(theme)
            else
              _buildAddTab(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final allTemplates = ref.watch(foodTemplatesProvider);
    final hasQuery = _searchQuery.isNotEmpty;
    // 비어있으면 전체 노출, 검색어가 있으면 prefix(startsWith) 매칭만 노출.
    final templates = hasQuery
        ? allTemplates
            .where((t) =>
                t.name.toLowerCase().startsWith(_searchQuery.toLowerCase()))
            .toList()
        : allTemplates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: '음식 이름으로 시작 검색',
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
          if (templates.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: templates.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = templates[i];
                  return ListTile(
                    dense: true,
                    title: Text(t.name),
                    subtitle: Text(
                      '${t.calories}kcal · 탄${_formatMacro(t.carbs)}g 단${_formatMacro(t.protein)}g 지${_formatMacro(t.fat)}g',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.outline),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '삭제',
                      onPressed: () => _deleteTemplate(t.uuid, t.name),
                    ),
                  );
                },
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
                '등록된 음식 템플릿이 없습니다. 추가 탭에서 등록하세요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAddTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final allTemplates = ref.watch(foodTemplatesProvider);
    final trimmedName = _addName.trim();
    final isNameEmpty = trimmedName.isEmpty;
    final isDuplicate =
        !isNameEmpty && allTemplates.any((t) => t.name == trimmedName);
    final canSubmit = !isNameEmpty && !isDuplicate;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _addNameCtrl,
            decoration: InputDecoration(
              hintText: '음식 이름 입력',
              prefixIcon: const Icon(Icons.restaurant, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: isDuplicate ? '이미 보유한 템플릿입니다.' : null,
            ),
            onChanged: (v) => setState(() => _addName = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _carbsCtrl,
                  decoration: InputDecoration(
                    hintText: '탄수화물(g)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _macroInputFormatters,
                  validator: _macroValidator,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _proteinCtrl,
                  decoration: InputDecoration(
                    hintText: '단백질(g)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _macroInputFormatters,
                  validator: _macroValidator,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _fatCtrl,
                  decoration: InputDecoration(
                    hintText: '지방(g)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _macroInputFormatters,
                  validator: _macroValidator,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calculate_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '자동 계산 (탄·단×4 + 지×9): ',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '$_derivedCalories kcal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isNameEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '음식 이름과 매크로(탄·단·지)를 입력하세요. 칼로리는 자동 계산됩니다.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: canSubmit ? _addTemplate : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('추가'),
            ),
          ),
        ],
      ),
    );
  }
}
