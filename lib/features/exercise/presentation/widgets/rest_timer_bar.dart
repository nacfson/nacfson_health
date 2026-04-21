import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/rest_timer_provider.dart';

/// 휴식 타이머 컴팩트 바.
///
/// `restTimerProvider`를 watch하여 활성 시에만 표시됩니다.
/// `_RootTimerOverlay`에서 AppBar title 오른쪽 빈 공간(상단 우측)에 배치되도록 설계됨.
/// ±15초 조정은 바 인라인 버튼과 알림(`RestNotificationService`) 액션 모두 지원.
class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(restTimerProvider);
    if (!state.isActive) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final tint = isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;
    final useNativeGlass = NativeLiquidGlassUtils.supportsLiquidGlass;

    final remaining = state.remainingSeconds.clamp(0, 9999);
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final progress = state.totalSeconds == 0
        ? 0.0
        : (remaining / state.totalSeconds).clamp(0.0, 1.0);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressIcon(
          progress: progress,
          accent: accent,
          tint: tint,
          isPaused: state.isPaused,
        ),
        const SizedBox(width: 8),
        Text(
          '$minutes:$seconds',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 8),
        _CircleButton(
          icon: Icons.remove,
          tooltip: '15초 빼기',
          onTap: () =>
              ref.read(restTimerProvider.notifier).addSeconds(-15),
        ),
        const SizedBox(width: 2),
        _CircleButton(
          icon: Icons.add,
          tooltip: '15초 더하기',
          onTap: () =>
              ref.read(restTimerProvider.notifier).addSeconds(15),
        ),
        const SizedBox(width: 4),
        _CircleButton(
          icon: state.isPaused
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded,
          tooltip: state.isPaused ? '재개' : '일시정지',
          emphasized: true,
          onTap: () =>
              ref.read(restTimerProvider.notifier).togglePause(),
        ),
        const SizedBox(width: 2),
        _CircleButton(
          icon: Icons.close,
          tooltip: '종료',
          onTap: () => ref.read(restTimerProvider.notifier).stop(),
        ),
      ],
    );

    const contentPadding = EdgeInsets.symmetric(horizontal: 6);

    if (useNativeGlass) {
      // iOS 26+ : 네이티브 UIGlassEffect.
      return Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: 40,
          child: LiquidGlassContainer(
            config: LiquidGlassConfig(
              effect: LiquidGlassEffect.clear,
              shape: LiquidGlassEffectShape.capsule,
              backgroundColor: cs.surface.withValues(alpha: 0.4),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: tint, width: 1.2),
              ),
              padding: contentPadding,
              child: Center(child: row),
            ),
          ),
        ),
      );
    }

    // iOS ≤ 25 / Android / Web : blur 없는 solid pill.
    // BackdropFilter 를 쓰지 않는 이유는 docs/build-debug.md
    // "휴식 타이머 — 상단 빨간 잔상 버그" 참고.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tint, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: contentPadding,
        child: row,
      ),
    );
  }
}

class _ProgressIcon extends StatelessWidget {
  final double progress;
  final Color accent;
  final Color tint;
  final bool isPaused;

  const _ProgressIcon({
    required this.progress,
    required this.accent,
    required this.tint,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              backgroundColor: tint,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          Icon(
            isPaused ? Icons.pause_rounded : Icons.timer_outlined,
            size: 14,
            color: accent,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool emphasized;

  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;

    final bg = emphasized
        ? accent
        : (isDark
            ? AppTheme.colorSurfaceAltDark
            : const Color(0xFFEEF0F2));
    final fg = emphasized ? Colors.white : cs.onSurface;

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 18,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: fg),
        ),
      ),
    );
  }
}
