import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/nutrition/atwater_calculator.dart';
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
  ConsumerState<DietForm> createState() => DietFormState();
}

class DietFormState extends ConsumerState<DietForm> {
  /// 외부 (RecordFormSheet onConfirmClose) 에서 dirty 여부를 조회하기 위한 진입점.
  /// 신규 추가: 음식명·탄단지·메모 중 하나라도 입력 → dirty.
  /// 수정: 초기 값과 달라졌으면 dirty.
  bool get isDirty {
    final r = widget.initialRecord;
    if (r == null) {
      return _foodNameController.text.trim().isNotEmpty ||
          _carbsController.text.trim().isNotEmpty ||
          _proteinController.text.trim().isNotEmpty ||
          _fatController.text.trim().isNotEmpty ||
          _memoController.text.trim().isNotEmpty;
    }
    String fmt(double v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toString();
    return _mealTypeController.text != r.mealType ||
        _foodNameController.text.trim() != r.foodName ||
        _carbsController.text.trim() != fmt(r.carbs) ||
        _proteinController.text.trim() != fmt(r.protein) ||
        _fatController.text.trim() != fmt(r.fat) ||
        _memoController.text != (r.memo ?? '') ||
        _satisfaction != r.satisfaction ||
        _timestamp != r.timestamp;
  }

  final _formKey = GlobalKey<FormState>();
  final _mealTypeController = TextEditingController();
  final _foodNameController = TextEditingController();
  final _carbsController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _memoController = TextEditingController();

  final _mealTypes = ['아침', '점심', '저녁', '간식'];
  int _satisfaction = 3;
  late DateTime _timestamp;
  bool _isLoading = false;
  // 최근 기록 칩 탭 시 DropdownButtonFormField 를 강제로 다시 빌드해
  // initialValue 가 새 mealType 으로 반영되도록 버전 카운터를 둔다.
  int _mealDropdownVersion = 0;
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
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// 현재 매크로 컨트롤러 값으로부터 Atwater 계수로 kcal 산출.
  /// 매크로가 비어 있거나 파싱 실패 시 0 으로 취급.
  int get _derivedCalories {
    double parse(TextEditingController c) =>
        double.tryParse(c.text.trim()) ?? 0;
    return kcalFromMacros(
      parse(_carbsController),
      parse(_proteinController),
      parse(_fatController),
    );
  }

  String? _macroValidator(String? v) {
    final raw = v?.trim() ?? '';
    if (raw.isEmpty) return null;
    final n = double.tryParse(raw);
    if (n == null || !n.isFinite) return '숫자만 입력 가능합니다 (입력: $raw)';
    if (n < 0) return '음수는 입력할 수 없습니다 (입력: $n)';
    return null;
  }

  static final _macroInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

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
      final carbs = double.tryParse(_carbsController.text.trim()) ?? 0;
      final protein = double.tryParse(_proteinController.text.trim()) ?? 0;
      final fat = double.tryParse(_fatController.text.trim()) ?? 0;
      final derivedKcal = kcalFromMacros(carbs, protein, fat);
      if (_isEditMode) {
        final updated = widget.initialRecord!.copyWith(
          updatedAt: now,
          syncStatus: SyncStatus.modified,
          mealType: _mealTypeController.text,
          foodName: foodName,
          totalCalories: derivedKcal,
          carbs: carbs,
          protein: protein,
          fat: fat,
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
          totalCalories: derivedKcal,
          carbs: carbs,
          protein: protein,
          fat: fat,
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

  void _applyRecord(DietRecord r) {
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
    setState(() {
      _mealTypeController.text = r.mealType;
      _mealDropdownVersion++;
      _foodNameController.text = r.foodName;
      _carbsController.text = fmt(r.carbs);
      _proteinController.text = fmt(r.protein);
      _fatController.text = fmt(r.fat);
      _memoController.text = r.memo ?? '';
      _timestamp = DateTime.now();
    });
  }

  static final _aiTagPattern = RegExp(r'\s*\[AI 분석 \d+g\]');

  void _applyAnalysis(FoodAnalysisResult r, Uint8List thumbnail) {
    String fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    final memoTag = '[AI 분석 ${r.estimatedGrams}g]';
    setState(() {
      _analyzedResult = r;
      _analyzedThumbnail = thumbnail;
      _foodNameController.text = r.foodName;
      // r.calories 는 무시 — kcal 은 매크로에서 Atwater 로 자동 산출.
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
      _carbsController.clear();
      _proteinController.clear();
      _fatController.clear();
      _memoController.text = _memoController.text.replaceAll(_aiTagPattern, '').trim();
    });
  }

  Future<void> _openTemplatePicker() async {
    final picked = await showTemplatePickerSheet<FoodTemplate>(
      context: context,
      title: '음식 템플릿 선택',
      templatesListenable: foodTemplatesProvider,
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
        // picked.calories 는 무시 — kcal 은 매크로에서 Atwater 로 자동 산출.
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
          if (!_isEditMode) _RecentMealsRow(onPick: _applyRecord),
          DropdownButtonFormField<String>(
            key: ValueKey('meal-$_mealDropdownVersion'),
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
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _carbsController,
                  decoration: const InputDecoration(labelText: '탄수화물 g'),
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
                  controller: _proteinController,
                  decoration: const InputDecoration(labelText: '단백질 g'),
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
                  controller: _fatController,
                  decoration: const InputDecoration(labelText: '지방 g'),
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
          _KcalPreview(kcal: _derivedCalories),
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

/// 매크로 입력값으로부터 Atwater 계수로 산출한 kcal 을 라이브로 표시.
/// v12-5: 사용자가 kcal 을 직접 입력하지 않고, 탄단지 입력에서 자동 계산.
class _KcalPreview extends StatelessWidget {
  final int kcal;
  const _KcalPreview({required this.kcal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '자동 계산된 칼로리 $kcal 킬로칼로리',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.calculate_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '자동 계산 (탄·단×4 + 지×9)',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$kcal kcal',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentMealsRow extends ConsumerWidget {
  final void Function(DietRecord) onPick;
  const _RecentMealsRow({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentUniqueDietRecordsProvider);
    if (recents.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '최근 식사에서 다시 추가',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recents.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = recents[i];
                return ActionChip(
                  label: Text(r.foodName),
                  onPressed: () => onPick(r),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
