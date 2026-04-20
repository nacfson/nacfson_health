import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../features/settings/domain/entities/food_template.dart';
import '../../../../features/settings/presentation/providers/food_template_provider.dart';
import '../../../../shared/widgets/template_picker_sheet.dart';
import '../../domain/entities/diet_record.dart';
import '../../domain/entities/food_analysis_result.dart';
import '../providers/diet_provider.dart';
import 'photo_analysis_card.dart';

class DietForm extends ConsumerStatefulWidget {
  final DietRecord? initialRecord;

  const DietForm({super.key, this.initialRecord});

  @override
  ConsumerState<DietForm> createState() => _DietFormState();
}

class _DietFormState extends ConsumerState<DietForm> {
  final _formKey = GlobalKey<FormState>();
  final _mealTypeController = TextEditingController();
  final _foodNameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _carbsController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _memoController = TextEditingController();

  final _mealTypes = ['아침', '점심', '저녁', '간식'];
  int _satisfaction = 3;
  late DateTime _timestamp;
  bool _isLoading = false;
  FoodAnalysisResult? _analyzedResult;
  Uint8List? _analyzedThumbnail;

  bool get _isEditMode => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    // 신규 추가 시 항상 현재 시각으로 초기화 (재오픈해도 오늘 날짜)
    _timestamp = r?.timestamp ?? DateTime.now();
    if (r != null) {
      _mealTypeController.text = r.mealType;
      _foodNameController.text = r.foodName;
      _caloriesController.text = r.totalCalories.toString();
      _carbsController.text = r.carbs % 1 == 0
          ? r.carbs.toInt().toString()
          : r.carbs.toString();
      _proteinController.text = r.protein % 1 == 0
          ? r.protein.toInt().toString()
          : r.protein.toString();
      _fatController.text = r.fat % 1 == 0
          ? r.fat.toInt().toString()
          : r.fat.toString();
      _memoController.text = r.memo ?? '';
      _satisfaction = r.satisfaction;
    }
  }

  @override
  void dispose() {
    _mealTypeController.dispose();
    _foodNameController.dispose();
    _caloriesController.dispose();
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_timestamp),
      );
      if (time != null) {
        setState(() {
          _timestamp = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"${widget.initialRecord!.foodName}"을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
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
    if (confirmed == true && mounted) {
      ref.read(dietRecordsProvider.notifier).deleteRecord(widget.initialRecord!.uuid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('삭제되었습니다'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final foodName = _foodNameController.text.trim();
      final now = DateTime.now();
      if (_isEditMode) {
        final updated = widget.initialRecord!.copyWith(
          updatedAt: now,
          syncStatus: SyncStatus.modified,
          mealType: _mealTypeController.text,
          foodName: foodName,
          totalCalories: int.parse(_caloriesController.text),
          carbs: double.parse(_carbsController.text.isEmpty ? '0' : _carbsController.text),
          protein: double.parse(_proteinController.text.isEmpty ? '0' : _proteinController.text),
          fat: double.parse(_fatController.text.isEmpty ? '0' : _fatController.text),
          satisfaction: _satisfaction,
          timestamp: _timestamp,
          memo: _memoController.text.isEmpty ? null : _memoController.text,
        );
        ref.read(dietRecordsProvider.notifier).updateRecord(updated);
      } else {
        final record = DietRecord(
          timestamp: _timestamp,
          updatedAt: now,
          mealType: _mealTypeController.text,
          foodName: foodName,
          totalCalories: int.parse(_caloriesController.text),
          carbs: double.parse(_carbsController.text.isEmpty ? '0' : _carbsController.text),
          protein: double.parse(_proteinController.text.isEmpty ? '0' : _proteinController.text),
          fat: double.parse(_fatController.text.isEmpty ? '0' : _fatController.text),
          satisfaction: _satisfaction,
          memo: _memoController.text.isEmpty ? null : _memoController.text,
        );
        ref.read(dietRecordsProvider.notifier).addRecord(record);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('저장되었습니다'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static final _aiTagPattern = RegExp(r'\s*\[AI 분석 \d+g\]');

  void _applyAnalysis(FoodAnalysisResult r, Uint8List thumbnail) {
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    final memoTag = '[AI 분석 ${r.estimatedGrams}g]';
    setState(() {
      _analyzedResult = r;
      _analyzedThumbnail = thumbnail;
      _foodNameController.text = r.foodName;
      _caloriesController.text = r.calories.toString();
      _carbsController.text = fmt(r.carbs);
      _proteinController.text = fmt(r.protein);
      _fatController.text = fmt(r.fat);
      final cleanedMemo = _memoController.text.replaceAll(_aiTagPattern, '').trim();
      _memoController.text = cleanedMemo.isEmpty ? memoTag : '$cleanedMemo $memoTag';
    });
  }

  void _clearAnalysis() {
    setState(() {
      _analyzedResult = null;
      _analyzedThumbnail = null;
      _foodNameController.clear();
      _caloriesController.clear();
      _carbsController.clear();
      _proteinController.clear();
      _fatController.clear();
      _memoController.text = _memoController.text.replaceAll(_aiTagPattern, '').trim();
    });
  }

  Future<void> _openTemplatePicker() async {
    final templates = ref.read(foodTemplatesProvider);
    final picked = await showTemplatePickerSheet<FoodTemplate>(
      context: context,
      title: '음식 템플릿 선택',
      templates: templates,
      labelOf: (t) => t.name,
      subtitleOf: (t) {
        String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
        return '${t.calories}kcal · 탄 ${fmt(t.carbs)}g 단 ${fmt(t.protein)}g 지 ${fmt(t.fat)}g';
      },
      emptyHint: '등록된 음식 템플릿이 없습니다.\n설정에서 자주 먹는 음식을 템플릿으로 추가해 보세요.',
      onEmptyAction: () => context.push('/settings'),
    );
    if (picked != null && mounted) {
      String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
      setState(() {
        _foodNameController.text = picked.name;
        _caloriesController.text = picked.calories.toString();
        _carbsController.text = fmt(picked.carbs);
        _proteinController.text = fmt(picked.protein);
        _fatController.text = fmt(picked.fat);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isEditMode)
            PhotoAnalysisCard(
              onAccepted: _applyAnalysis,
              existingResult: _analyzedResult,
              existingThumbnail: _analyzedThumbnail,
              onClear: _clearAnalysis,
            ),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: '식사 유형'),
            initialValue: _mealTypeController.text.isEmpty
                ? null
                : _mealTypeController.text,
            items: _mealTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => _mealTypeController.text = v ?? '',
            validator: (v) => v == null ? '필수' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _foodNameController,
            decoration: InputDecoration(
              labelText: '음식 이름',
              hintText: '직접 입력하거나 템플릿에서 선택',
              suffixIcon: IconButton(
                icon: const Icon(Icons.bookmark_border),
                tooltip: '템플릿에서 선택',
                onPressed: _openTemplatePicker,
              ),
            ),
            validator: (v) => v?.isEmpty ?? true ? '필수' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _caloriesController,
            decoration: const InputDecoration(labelText: '칼로리(kcal)'),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 0 || n > 9999) return '0-9999';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _carbsController,
                  decoration: const InputDecoration(labelText: '탄수화물(g)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = double.tryParse(v);
                    if (n == null) return '숫자 입력';
                    if (n < 0) return '0 이상';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _proteinController,
                  decoration: const InputDecoration(labelText: '단백질(g)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = double.tryParse(v);
                    if (n == null) return '숫자 입력';
                    if (n < 0) return '0 이상';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _fatController,
                  decoration: const InputDecoration(labelText: '지방(g)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = double.tryParse(v);
                    if (n == null) return '숫자 입력';
                    if (n < 0) return '0 이상';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('만족도: '),
              ...List.generate(
                5,
                (i) => IconButton(
                  icon: Icon(i < _satisfaction ? Icons.star : Icons.star_border),
                  color: Colors.amber,
                  onPressed: () => setState(() => _satisfaction = i + 1),
                ),
              ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '시간: ${_timestamp.month}/${_timestamp.day} ${_timestamp.hour}:${_timestamp.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _pickDateTime,
          ),
          TextFormField(
            controller: _memoController,
            decoration: const InputDecoration(labelText: '메모(선택)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditMode ? '수정' : '추가'),
            ),
          ),
          if (_isEditMode) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: _delete,
                child: const Text('삭제'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
