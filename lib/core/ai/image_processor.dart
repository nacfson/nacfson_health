import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 사진 음식 분석용 이미지 전처리 유틸.
///
/// 원본(4~12MB) → 긴 변 [maxDim]px JPEG(q=[quality])로 리사이즈합니다.
/// Gemini Vision 토큰 비용을 줄이고 전송 속도를 높이는 것이 목적입니다.
class ImageProcessor {
  Future<Uint8List> resizeAndEncode(
    XFile file, {
    int maxDim = 1024,
    int quality = 85,
  }) async {
    final rawBytes = await file.readAsBytes();
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw const FormatException('이미지를 디코딩할 수 없습니다');
    }

    final longer = math.max(decoded.width, decoded.height);
    final img.Image resized = longer > maxDim
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxDim : null,
            height: decoded.height > decoded.width ? maxDim : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final encoded = img.encodeJpg(resized, quality: quality);
    return Uint8List.fromList(encoded);
  }

  /// JPEG 바이트 → SHA256 16진수 문자열.
  ///
  /// 동일 사진 재분석 판별용 캐시 키로 사용합니다.
  String sha256Hex(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }
}
