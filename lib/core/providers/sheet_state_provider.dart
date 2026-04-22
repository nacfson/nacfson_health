import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SheetType { exercise, diet }

final activeSheetProvider = StateProvider<SheetType?>((ref) => null);

void openSheet({
  required BuildContext context,
  required WidgetRef ref,
  required SheetType type,
  required String title,
  required Widget child,
}) {
  final currentSheet = ref.read(activeSheetProvider);

  if (currentSheet == type) {
    Navigator.pop(context);
    ref.read(activeSheetProvider.notifier).state = null;
    return;
  }

  if (currentSheet != null) {
    Navigator.pop(context);
  }

  ref.read(activeSheetProvider.notifier).state = type;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
    // BottomNavShell 의 glassmorphic 하단 탭 바가 시트 입력창을 가리지 않는다.
    useRootNavigator: true,
    useSafeArea: true,
    builder: (ctx) => child,
  ).then((_) {
    // 시트가 닫히면 즉시 FAB 복귀시킴 (microtask 지연 제거)
    ref.read(activeSheetProvider.notifier).state = null;
  });
}
