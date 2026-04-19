import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../utils/date_time_utils.dart';

class SpreadsheetStatusCard extends ConsumerWidget {
  const SpreadsheetStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSyncTime = ref.watch(lastSyncTimeProvider);
    final isSyncing = ref.watch(isSyncingProvider);
    final isSignedIn = ref.watch(isSignedInProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSignedIn ? Icons.cloud_done : Icons.cloud_off,
                  color: isSignedIn ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Supabase 동기화',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isSignedIn) ...[
              Text(
                '마지막 동기화: ${formatRelativeTime(lastSyncTime)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isSyncing ? null : () => _triggerSync(context, ref),
                  icon: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(isSyncing ? '동기화 중...' : '지금 동기화'),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  border: Border.all(color: Colors.orange[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Google 계정으로 먼저 로그인해주세요',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.orange[900],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _triggerSync(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(syncStateProvider.notifier).performSync();

      if (result.hasErrors) {
        if (rootNavigatorKey.currentState?.overlay != null) {
          ErrorOverlay.show(
            title: '동기화 오류',
            message: '일부 오류가 발생했습니다: ${result.errorMessage}',
          );
        }
      } else {
        ref.invalidate(lastSyncTimeProvider);
        if (rootNavigatorKey.currentState?.overlay != null) {
          ErrorOverlay.show(
            title: '동기화 완료',
            message: '데이터가 Supabase와 성공적으로 동기화되었습니다.',
            type: OverlayType.info,
          );
        }
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '동기화 실패',
          message: '동기화에 실패했습니다: ${_friendlyErrorMessage(e)}',
        );
      }
    }
  }

  static String _friendlyErrorMessage(Object error) {
    String msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    if (msg.length > 200) {
      msg = '${msg.substring(0, 200)}…';
    }
    return msg;
  }
}
