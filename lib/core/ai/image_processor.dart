import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 사진 음식 분석용 이미지 전처리 유틸.
///
/// 원본(4~12MB) → 긴 변 [maxDim]px JPEG(q=[quality])로 리사이즈합니다.
/// decode/copyResize/encodeJpg는 CPU-bound 이므로 `compute()`로
/// 별도 isolate에서 실행해 UI 프레임 드랍을 방지합니다.
class ImageProcessor {
  Future<Uint8List> resizeAndEncode(
    XFile file, {
    int maxDim = 1024,
    int quality = 85,
  }) async {
    final rawBytes = await file.readAsBytes();
    return compute(
      _resizeAndEncodeInIsolate,
      _ResizeParams(raw: rawBytes, maxDim: maxDim, quality: quality),
    );
  }

  /// JPEG 바이트 → SHA256 16진수 문자열.
  ///
  /// 150KB 수준 해시는 <5ms라 UI isolate에서 처리해도 무해.
  String sha256Hex(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }
}

class _ResizeParams {
  final Uint8List raw;
  final int maxDim;
  final int quality;

  const _ResizeParams({
    required this.raw,
    required this.maxDim,
    required this.quality,
  });
}

/// Isolate에서 실행되는 순수 함수 (top-level).
///
/// [_ResizeParams]만 받으므로 외부 캡처 없음 → compute()로 전달 가능.
Uint8List _resizeAndEncodeInIsolate(_ResizeParams p) {
  final decoded = img.decodeImage(p.raw);
  if (decoded == null) {
    throw const FormatException('이미지를 디코딩할 수 없습니다');
  }
  final longer = math.max(decoded.width, decoded.height);
  final img.Image resized = longer > p.maxDim
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? p.maxDim : null,
          height: decoded.height > decoded.width ? p.maxDim : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: p.quality));
}
