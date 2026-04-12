import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';

enum OverlayType { error, info }

class ErrorOverlay {
  static OverlayEntry? _currentEntry;

  static void show({
    required String title,
    required String message,
    OverlayType type = OverlayType.error,
  }) {
    // 기존 entry 제거
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ErrorCard(
        title: title,
        message: message,
        type: type,
        onDismissed: () {
          entry.remove();
          _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ErrorCard extends StatefulWidget {
  const _ErrorCard({
    required this.title,
    required this.message,
    required this.type,
    required this.onDismissed,
  });

  final String title;
  final String message;
  final OverlayType type;
  final VoidCallback onDismissed;

  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    // 총 3.3초: 페이드인 0.3s + 유지 2.0s + 페이드아웃 1.0s
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3300),
      vsync: this,
    );

    _opacity = TweenSequence<double>([
      // 0s ~ 0.3s: 페이드인
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: 0.3,
      ),
      // 0.3s ~ 2.3s: 유지
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 2.0,
      ),
      // 2.3s ~ 3.3s: 페이드아웃
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0),
        weight: 1.0,
      ),
    ]).animate(_controller);

    _controller.forward().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (bgColor, fgColor) = switch (widget.type) {
      OverlayType.error => (
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      OverlayType.info => (
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        ),
    };

    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ConstrainedBox(
            // 최대 크기 제한으로 오버플로우 방지 (Decorator 패턴 활용)
            constraints: const BoxConstraints(
              maxWidth: 300,
              maxHeight: 200,
            ),
            child: Material(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: fgColor,
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Flexible로 감싸 남은 공간 내에서만 렌더링
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          widget.message,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: fgColor,
                              ),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
