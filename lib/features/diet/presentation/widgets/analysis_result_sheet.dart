import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/entities/food_analysis_result.dart';

/// Gemini Vision 분석 결과를 사용자에게 확인·편집 받는 BottomSheet.
///
/// 사용자가 중량을 조정하면 영양성분이 비례 자동 환산됩니다.
/// "이대로 채우기" 선택 시 조정된 [FoodAnalysisResult]를 반환합니다.
Future<FoodAnalysisResult?> showAnalysisResultSheet({
  required BuildContext context,
  required FoodAnalysisResult result,
  required Uint8List thumbnailBytes,
}) {
  return showModalBottomSheet<FoodAnalysisResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
    // BottomNavShell 의 glassmorphic 하단 탭 바가 시트를 가리지 않는다.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnalysisResultSheet(
      original: result,
      thumbnailBytes: thumbnailBytes,
    ),
  );
}

class _AnalysisResultSheet extends StatefulWidget {
  final FoodAnalysisResult original;
  final Uint8List thumbnailBytes;

  const _AnalysisResultSheet({
    required this.original,
    required this.thumbnailBytes,
  });

  @override
  State<_AnalysisResultSheet> createState() => _AnalysisResultSheetState();
}

class _AnalysisResultSheetState extends State<_AnalysisResultSheet> {
  late FoodAnalysisResult _current;
  late final TextEditingController _gramsCtrl;

  @override
  void initState() {
    super.initState();
    _current = widget.original;
    _gramsCtrl = TextEditingController(text: _current.estimatedGrams.toString());
  }

  @override
  void dispose() {
    _gramsCtrl.dispose();
    super.dispose();
  }

  void _applyGrams(int grams) {
    if (grams <= 0) return;
    setState(() {
      _current = widget.original.scaleTo(grams);
    });
  }

  void _adjust(int delta) {
    final next = (_current.estimatedGrams + delta).clamp(1, 9999);
    _gramsCtrl.text = next.toString();
    _applyGrams(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lowConfidence = _current.confidence < 0.5;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '분석 결과',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        color: cs.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close,
                            size: 20, color: cs.onSurfaceVariant),
                      ),
                      onPressed: () => Navigator.pop(context, null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        widget.thumbnailBytes,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _current.foodName.isEmpty
                                ? '(인식된 음식명 없음)'
                                : _current.foodName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '신뢰도 ${(_current.confidence * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              color: lowConfidence
                                  ? Colors.orange
                                  : cs.onSurfaceVariant,
                              fontWeight: lowConfidence
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (_current.notes != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _current.notes!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_current.isMultiItem) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '여러 음식이 보여 합산했어요 (${_current.items.length}개)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _gramsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '추정 중량(g)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (v) {
                          final n = int.tryParse(v);
                          if (n != null) _applyGrams(n);
                        },
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n > 0) _applyGrams(n);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.remove),
                      onPressed: () => _adjust(-50),
                    ),
                    IconButton.outlined(
                      icon: const Icon(Icons.add),
                      onPressed: () => _adjust(50),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _MacroRow(label: '칼로리', value: '${_current.calories} kcal'),
                _MacroRow(
                    label: '탄수화물',
                    value: '${_current.carbs.toStringAsFixed(1)} g'),
                _MacroRow(
                    label: '단백질',
                    value: '${_current.protein.toStringAsFixed(1)} g'),
                _MacroRow(
                    label: '지방', value: '${_current.fat.toStringAsFixed(1)} g'),
                const SizedBox(height: 8),
                Text(
                  '💡 중량 변경 시 영양성분이 자동 환산됩니다',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('다시 촬영'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _current),
                        child: const Text('이대로 채우기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final String value;

  const _MacroRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
