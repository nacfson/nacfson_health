import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/ai/food_vision_provider.dart';
import '../../../../core/ai/image_processor.dart';
import '../../domain/entities/food_analysis_result.dart';
import 'analysis_result_sheet.dart';

typedef OnAnalysisAccepted = void Function(
  FoodAnalysisResult result,
  Uint8List thumbnailBytes,
);

/// DietForm 최상단에 노출되는 "사진으로 자동 입력" 카드.
///
/// 카메라/갤러리 선택 → 리사이즈 → 캐시/한도 체크 → Gemini 호출 → 결과 모달 →
/// 사용자가 수용 시 [onAccepted] 콜백으로 부모(DietForm)에 결과 전달.
/// 편집 모드에서는 부모가 이 위젯을 아예 렌더하지 않음.
class PhotoAnalysisCard extends ConsumerStatefulWidget {
  final OnAnalysisAccepted onAccepted;
  final Uint8List? existingThumbnail;
  final FoodAnalysisResult? existingResult;
  final VoidCallback? onClear;

  const PhotoAnalysisCard({
    super.key,
    required this.onAccepted,
    this.existingThumbnail,
    this.existingResult,
    this.onClear,
  });

  @override
  ConsumerState<PhotoAnalysisCard> createState() => _PhotoAnalysisCardState();
}

enum _AnalysisStage { idle, processing, analyzing }

class _PhotoAnalysisCardState extends ConsumerState<PhotoAnalysisCard> {
  final _picker = ImagePicker();
  final _imageProcessor = ImageProcessor();
  _AnalysisStage _stage = _AnalysisStage.idle;

  Future<void> _pickAndAnalyze(ImageSource source) async {
    if (_stage != _AnalysisStage.idle) return;

    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
    } catch (e) {
      _showSnackBar('사진을 가져올 수 없습니다. 권한을 확인해주세요.');
      return;
    }
    if (file == null) return;

    setState(() => _stage = _AnalysisStage.processing);
    Uint8List jpegBytes;
    String cacheKey;
    try {
      jpegBytes = await _imageProcessor.resizeAndEncode(file);
      cacheKey = _imageProcessor.sha256Hex(jpegBytes);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('이미지를 처리할 수 없습니다');
      setState(() => _stage = _AnalysisStage.idle);
      return;
    }
    if (!mounted) return;

    setState(() => _stage = _AnalysisStage.analyzing);
    try {
      final result = await ref.read(
        foodVisionAnalysisProvider(
          FoodVisionRequest(key: cacheKey, bytes: jpegBytes),
        ).future,
      );
      if (!mounted) return;

      if (!result.isFood) {
        await _showNotFoodDialog();
        setState(() => _stage = _AnalysisStage.idle);
        return;
      }

      final accepted = await showAnalysisResultSheet(
        context: context,
        result: result,
        thumbnailBytes: jpegBytes,
      );
      if (!mounted) return;

      if (accepted != null) {
        widget.onAccepted(accepted, jpegBytes);
      }
      setState(() => _stage = _AnalysisStage.idle);
    } on StateError catch (e) {
      if (!mounted) return;
      if (e.message == 'DAILY_LIMIT_REACHED') {
        await _showLimitDialog();
      } else if (e.message == 'GEMINI_API_KEY_MISSING') {
        _showSnackBar('Gemini API 키(.env)를 설정해주세요');
      } else {
        _showSnackBar('분석에 실패했습니다. 직접 입력해주세요');
      }
      setState(() => _stage = _AnalysisStage.idle);
    } on FormatException {
      if (!mounted) return;
      _showSnackBar('분석 결과를 읽을 수 없어요. 직접 입력해주세요');
      setState(() => _stage = _AnalysisStage.idle);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('네트워크 오류가 발생했습니다. 다시 시도해주세요');
      setState(() => _stage = _AnalysisStage.idle);
    }
  }

  Future<void> _showNotFoodDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('음식 인식 실패'),
        content: const Text('음식을 인식하지 못했어요.\n더 가까이서, 음식이 잘 보이는 각도로 다시 촬영해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLimitDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오늘 사진 분석을 모두 사용했어요'),
        content: Text(
            'AI 분석은 하루 $kFoodVisionDailyLimit회 제공돼요.\n내일 다시 이용하거나 직접 입력해서 기록해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndAnalyze(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndAnalyze(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final countMap = ref.watch(foodVisionCallCountProvider);
    final dateKey = foodVisionDateKey(DateTime.now());
    final used = countMap[dateKey] ?? 0;
    final remaining = (kFoodVisionDailyLimit - used).clamp(0, kFoodVisionDailyLimit);

    if (widget.existingResult != null && widget.existingThumbnail != null) {
      return _AppliedBanner(
        thumbnail: widget.existingThumbnail!,
        result: widget.existingResult!,
        onReanalyze: _stage == _AnalysisStage.idle && remaining > 0
            ? _showSourcePicker
            : null,
        onClear: widget.onClear,
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _stage == _AnalysisStage.idle
          ? _buildIdle(cs, remaining)
          : _buildBusy(cs),
    );
  }

  Widget _buildIdle(ColorScheme cs, int remaining) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_camera, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            const Text(
              '사진으로 자동 입력',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            Text(
              '오늘 $remaining/$kFoodVisionDailyLimit 남음',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '음식 사진을 찍으면 AI가 영양성분을 자동 분석합니다.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('카메라'),
                onPressed: remaining > 0
                    ? () => _pickAndAnalyze(ImageSource.camera)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('갤러리'),
                onPressed: remaining > 0
                    ? () => _pickAndAnalyze(ImageSource.gallery)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBusy(ColorScheme cs) {
    final message = _stage == _AnalysisStage.processing
        ? '이미지 준비 중...'
        : '음식을 인식하고 있어요 (3~5초)';
    return Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

class _AppliedBanner extends StatelessWidget {
  final Uint8List thumbnail;
  final FoodAnalysisResult result;
  final VoidCallback? onReanalyze;
  final VoidCallback? onClear;

  const _AppliedBanner({
    required this.thumbnail,
    required this.result,
    required this.onReanalyze,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              thumbnail,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result.foodName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${result.estimatedGrams}g · ${result.calories}kcal',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onReanalyze != null)
            TextButton(
              onPressed: onReanalyze,
              child: const Text('다시 분석'),
            ),
          if (onClear != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '사진 제거',
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
