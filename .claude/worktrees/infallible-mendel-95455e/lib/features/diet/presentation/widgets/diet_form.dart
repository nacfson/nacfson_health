import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/settings/domain/entities/food_template.dart';
import '../../../../features/settings/presentation/providers/food_template_provider.dart';
import '../../domain/entities/diet_record.dart';
import '../providers/diet_provider.dart';

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
  DateTime _timestamp = DateTime.now();

  bool get _isEditMode => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
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
      _timestamp = r.timestamp;
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
      Navigator.pop(context);
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
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
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodTemplates = ref.watch(foodTemplatesProvider);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          Autocomplete<FoodTemplate>(
            displayStringForOption: (option) => option.name,
            initialValue: TextEditingValue(text: _foodNameController.text),
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<FoodTemplate>.empty();
              }
              return foodTemplates.where((t) => t.name.contains(textEditingValue.text));
            },
            onSelected: (selection) {
              setState(() {
                _foodNameController.text = selection.name;
                _caloriesController.text = selection.calories.toString();
                _carbsController.text = selection.carbs % 1 == 0
                    ? selection.carbs.toInt().toString()
                    : selection.carbs.toString();
                _proteinController.text = selection.protein % 1 == 0
                    ? selection.protein.toInt().toString()
                    : selection.protein.toString();
                _fatController.text = selection.fat % 1 == 0
                    ? selection.fat.toInt().toString()
                    : selection.fat.toString();
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              // 초기화 시 기존 값을 반영하거나, Autocomplete 내부 컨트롤러와 외부 컨트롤러 동기화
              if (controller.text.isEmpty && _foodNameController.text.isNotEmpty) {
                controller.text = _foodNameController.text;
              }
              controller.addListener(() {
                _foodNameController.text = controller.text;
              });

              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: '음식 이름',
                  hintText: '이름을 입력하여 검색',
                  suffixIcon: Icon(Icons.search),
                ),
                onFieldSubmitted: (value) => onFieldSubmitted(),
                validator: (v) => v?.isEmpty ?? true ? '필수' : null,
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 200,
                      maxWidth: MediaQuery.of(context).size.width - 48, // Padding 고려
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option.name),
                          subtitle: Text('${option.calories}kcal | 탄 ${option.carbs}g 단 ${option.protein}g 지 ${option.fat}g'),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
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
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _proteinController,
                  decoration: const InputDecoration(labelText: '단백질(g)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _fatController,
                  decoration: const InputDecoration(labelText: '지방(g)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
              onPressed: _submit,
              child: Text(_isEditMode ? '수정' : '추가'),
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
