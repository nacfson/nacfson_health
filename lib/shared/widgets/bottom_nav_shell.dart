import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';
import '../../core/providers/sheet_state_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/router/app_router.dart';
import '../providers/selected_date_provider.dart';

final fabActionProvider = StateProvider<VoidCallback?>((ref) => null);

class BottomNavShell extends ConsumerWidget {
  final Widget child;
  const BottomNavShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/exercise')) return 0;
    if (location.startsWith('/diet'))     return 1;
    if (location.startsWith('/weight'))   return 2;
    if (location.startsWith('/summary'))  return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  bool _showFab(int tabIndex, bool isToday, SheetType? activeSheet) =>
      isToday && (tabIndex == 0 || tabIndex == 1) && activeSheet == null;

  void _onItemTapped(int index, BuildContext context) {
    shellNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (index == _calculateSelectedIndex(context)) return;
    switch (index) {
      case 0: context.go('/exercise');
      case 1: context.go('/diet');
      case 2: context.go('/weight');
      case 3: context.go('/summary');
      case 4: context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _calculateSelectedIndex(context);
    final isToday       = ref.watch(isSelectedDateTodayProvider);
    final fabAction     = ref.watch(fabActionProvider);
    final activeSheet   = ref.watch(activeSheetProvider);
    final showFab       = _showFab(selectedIndex, isToday, activeSheet);

    return Scaffold(
      extendBody: true,
      body: child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: showFab ? _MintFab(onTap: fabAction) : null,
      bottomNavigationBar: _GlassmorphicNavBar(
        selectedIndex: selectedIndex,
        onTap: (i) => _onItemTapped(i, context),
        showFab: showFab,
      ),
    );
  }
}

class _MintFab extends StatelessWidget {
  final VoidCallback? onTap;
  const _MintFab({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.colorMint, AppTheme.colorMintDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.colorMint.withOpacity(0.40),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

class _GlassmorphicNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool showFab;

  const _GlassmorphicNavBar({
    required this.selectedIndex,
    required this.onTap,
    required this.showFab,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(icon: Icons.fitness_center_outlined, activeIcon: Icons.fitness_center, label: '운동'),
      _NavItem(icon: Icons.restaurant_outlined,     activeIcon: Icons.restaurant,     label: '식단'),
      _NavItem(icon: Icons.monitor_weight_outlined, activeIcon: Icons.monitor_weight, label: '체중'),
      _NavItem(icon: Icons.insights_outlined,       activeIcon: Icons.insights,       label: '요약'),
      _NavItem(icon: Icons.settings_outlined,       activeIcon: Icons.settings,       label: '설정'),
    ];

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgOpacity = isDark ? 0.62 : 0.55;
    final height = 72 + MediaQuery.viewPaddingOf(context).bottom;
    final useNativeGlass = NativeLiquidGlassUtils.supportsLiquidGlass;

    final stackChildren = <Widget>[
      // iOS 26 native glass 경로에서는 tint 레이어 생략 (순수 무색 유리 유지)
      if (!useNativeGlass)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: cs.surface.withOpacity(bgOpacity)),
          ),
        ),
      // iOS 26 UIGlassEffect 는 edge lensing/specular 를 자체 처리.
      // Flutter 쪽 innerGlow / hairline / specular 는 fallback 경로에서만 그린다.
      if (!useNativeGlass) ...[
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.glassInnerGlow(context), Colors.transparent],
                  stops: const [0.0, 0.55],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 0.5,
            color: cs.outlineVariant.withOpacity(isDark ? 0.5 : 0.7),
          ),
        ),
        const _SpecularHighlight(),
      ],
      SafeArea(
        top: false,
        child: Stack(
          children: [
            _SelectionPill(
              selectedIndex: selectedIndex,
              itemCount: items.length,
            ),
            Row(
              children: List.generate(items.length, (i) {
                return Expanded(
                  child: _NavButton(
                    item: items[i],
                    isSelected: i == selectedIndex,
                    onTap: () => onTap(i),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    ];

    final stack = Stack(children: stackChildren);

    if (useNativeGlass) {
      // iOS 26+ : 실제 UIGlassEffect 백드롭.
      // backgroundColor = 너무 하얗/검정이 아닌 중간 톤 + UIGlassEffect adaptive-contrast 안정화.
      return SizedBox(
        height: height,
        child: LiquidGlassContainer(
          config: LiquidGlassConfig(
            effect: LiquidGlassEffect.clear,
            shape: LiquidGlassEffectShape.rect,
            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
          child: stack,
        ),
      );
    }

    // iOS ≤ 25 / Android / Web : 기존 Flutter BackdropFilter 폴백.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: SizedBox(height: height, child: stack),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final unselectedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isSelected ? item.activeIcon : item.icon,
              key: ValueKey(isSelected),
              color: isSelected ? selectedColor : unselectedColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? selectedColor : unselectedColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecularHighlight extends StatelessWidget {
  const _SpecularHighlight();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 1.5,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.glassSpecular(context), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final int selectedIndex;
  final int itemCount;
  const _SelectionPill({required this.selectedIndex, required this.itemCount});

  @override
  Widget build(BuildContext context) {
    final alignX = itemCount <= 1
        ? 0.0
        : (selectedIndex / (itemCount - 1)) * 2 - 1;

    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: AnimatedAlign(
            alignment: Alignment(alignX, 0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 1 / itemCount,
              heightFactor: 1.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.glassPillFill(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppTheme.glassPillBorder(context),
                      width: 0.5,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppTheme.glassPillInner(context), Colors.transparent],
                      stops: const [0.0, 0.6],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
