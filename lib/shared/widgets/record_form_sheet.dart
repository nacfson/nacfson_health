import 'package:flutter/material.dart';

class RecordFormSheet extends StatelessWidget {
  final String title;
  final Widget child;

  /// 시트를 닫기 전 호출되는 가드. `true` 반환 시 닫고, `false` 면 닫지 않는다.
  /// null 이면 즉시 닫힘 (기존 동작). 입력 도중 데이터 손실 방지를 위해 폼이
  /// dirty 상태일 때 confirmation dialog 를 띄우는 용도.
  final Future<bool> Function()? onConfirmClose;

  const RecordFormSheet({
    super.key,
    required this.title,
    required this.child,
    this.onConfirmClose,
  });

  Future<void> _handleClose(BuildContext context) async {
    final guard = onConfirmClose;
    if (guard == null) {
      Navigator.pop(context);
      return;
    }
    final allow = await guard();
    if (allow && context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sheet = DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        color: cs.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
                      ),
                      onPressed: () => _handleClose(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        );
      },
    );

    if (onConfirmClose == null) return sheet;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleClose(context);
      },
      child: sheet,
    );
  }
}
