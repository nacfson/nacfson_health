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
    builder: (ctx) {
      ref.read(activeSheetProvider.notifier).state = type;
      return child;
    },
  ).then((_) {
    Future.microtask(() {
      ref.read(activeSheetProvider.notifier).state = null;
    });
  });
}
