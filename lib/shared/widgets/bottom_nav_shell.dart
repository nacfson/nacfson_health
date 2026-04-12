import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';

class BottomNavShell extends StatelessWidget {
  final Widget child;
  const BottomNavShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/exercise')) return 0;
    if (location.startsWith('/diet')) return 1;
    if (location.startsWith('/summary')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    // 1. 쉘 위에 떠 있는 모든 모달/시트 한 번에 닫기 (popAll)
    shellNavigatorKey.currentState?.popUntil((route) => route.isFirst);

    // 2. 혹시 Root Navigator 위에 띄운 오버레이가 있다면 그것도 닫기
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);

    // 3. 현재 탭과 같으면 아무것도 안 함
    if (index == _calculateSelectedIndex(context)) return;

    // 4. 라우팅
    switch (index) {
      case 0:
        context.go('/exercise');
      case 1:
        context.go('/diet');
      case 2:
        context.go('/summary');
      case 3:
        context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (index) => _onItemTapped(index, context),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '운동'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: '식단'),
          NavigationDestination(icon: Icon(Icons.insights), label: '요약'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
