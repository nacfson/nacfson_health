import 'package:flutter/material.dart';

/// 호출 직전 SnackBar 큐를 비워 중복 스택을 방지한다.
///
/// 같은 화면에서 빠른 연속 액션 (저장 + 삭제 등) 시 이전 메시지가 새 메시지를
/// 덮지 않고 아래에 쌓이는 기본 동작을 차단. 모든 in-app SnackBar 는 이 헬퍼를
/// 통해 노출하여 일관된 floating 스타일을 유지한다.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
}
