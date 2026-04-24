import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SheetType { exercise, diet }

final activeSheetProvider = StateProvider<SheetType?>((ref) => null);

/// 카드 내부에서 인라인 입력 위젯이 렌더 중인 카드 식별자 집합.
/// 비어 있지 않으면 하단 FAB 를 숨겨 카드 하단의 입력/수정 행이 FAB 에 가려지지 않게 한다.
/// 트리거 기준은 "위젯이 화면에 있는가" 이며, 키보드/포커스 상태와는 무관.
final activeInlineEditProvider = StateProvider<Set<String>>((ref) => <String>{});

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
