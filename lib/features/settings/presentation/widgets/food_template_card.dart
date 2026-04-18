import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../domain/entities/food_template.dart';
import '../providers/food_template_provider.dart';

class FoodTemplateCard extends ConsumerStatefulWidget {
  const FoodTemplateCard({super.key});

  @override
  ConsumerState<FoodTemplateCard> createState() => _FoodTemplateCardState();
}

class _FoodTemplateCardState extends ConsumerState<FoodTemplateCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _caloriesCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _searchCtrl;
  final _formKey = GlobalKey<FormState>();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _caloriesCtrl = TextEditingController();
    _carbsCtrl = TextEditingController();
    _proteinCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _caloriesCtrl.dispose();
    _carbsCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final calories = int.tryParse(_caloriesCtrl.text) ?? 0;
    final carbs = double.tryParse(_carbsCtrl.text) ?? 0;
    final protein = double.tryParse(_proteinCtrl.text) ?? 0;
    final fat = double.tryParse(_fatCtrl.text) ?? 0;

    final templates = ref.read(foodTemplatesProvider);
    if (templates.any((t) => t.name == name)) {
      ErrorOverlay.show(
        title: '중복 오류',
        message: '이미 등록된 음식 이름입니다.',
      );
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
      _nameCtrl.clear();
      _caloriesCtrl.clear();
      _carbsCtrl.clear();
      _proteinCtrl.clear();
      _fatCtrl.clear();
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
    final allTemplates = ref.watch(foodTemplatesProvider);
    final templates = allTemplates
        .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('음식 템플릿', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (allTemplates.isNotEmpty)
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '검색...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '자주 먹는 음식을 등록하면 식단 추가 시 자동으로 값이 채워집니다.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (templates.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              ...templates.map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.name),
                  subtitle: Text(
                    '${t.calories}kcal · 탄${_formatMacro(t.carbs)}g 단${_formatMacro(t.protein)}g 지${_formatMacro(t.fat)}g',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '삭제',
                    onPressed: () => _deleteTemplate(t.uuid, t.name),
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: '음식 이름',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '음식 이름을 입력해주세요' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _caloriesCtrl,
                          decoration: InputDecoration(
                            hintText: '칼로리(kcal)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 9999) return '0-9999';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
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
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 999) return '0-999';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
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
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 999) return '0-999';
                            return null;
                          },
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
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 999) return '0-999';
                            return null;
                          },
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
          ],
        ),
      ),
    );
  }
}
