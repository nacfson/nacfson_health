import 'package:flutter/material.dart';

const _exerciseTypes = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];

class DirectRoutineInput {
  final String name;
  final String type;
  const DirectRoutineInput({required this.name, required this.type});
}

Future<DirectRoutineInput?> showDirectRoutineInputDialog(
  BuildContext context, {
  String? initialType,
}) {
  return showDialog<DirectRoutineInput>(
    context: context,
    builder: (_) => _DirectRoutineInputDialog(initialType: initialType),
  );
}

class _DirectRoutineInputDialog extends StatefulWidget {
  final String? initialType;
  const _DirectRoutineInputDialog({this.initialType});

  @override
  State<_DirectRoutineInputDialog> createState() =>
      _DirectRoutineInputDialogState();
}

class _DirectRoutineInputDialogState extends State<_DirectRoutineInputDialog> {
  final _nameCtrl = TextEditingController();
  String? _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _normalizedName() =>
      _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get _canSubmit => _normalizedName().isNotEmpty && _type != null;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      DirectRoutineInput(name: _normalizedName(), type: _type!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 운동 추가'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '운동 이름',
              hintText: '예: 인클라인 덤벨 프레스',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: '운동 유형',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            initialValue: _type,
            items: _exerciseTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _type = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
