import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/sync/google_auth_service.dart';
import '../../../../core/sync/sync_preferences.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../utils/date_time_utils.dart';

class SpreadsheetStatusCard extends ConsumerWidget {
  const SpreadsheetStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spreadsheetId = ref.watch(spreadsheetIdProvider);
    final lastSyncTime = ref.watch(lastSyncTimeProvider);
    final isSyncing = ref.watch(isSyncingProvider);
    final authService = ref.read(googleAuthServiceProvider);
    final prefs = ref.read(syncPreferencesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  spreadsheetId != null ? Icons.table_chart : Icons.table_chart_outlined,
                  color: spreadsheetId != null ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '스프레드시트',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (spreadsheetId != null) ...[
              Text(
                'ID: ${abbreviateSpreadsheetId(spreadsheetId)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 4),
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
                  onPressed: isSyncing
                      ? null
                      : () => _triggerSync(context, ref),
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
              Text(
                '스프레드시트에 연결되어 있지 않습니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _createSpreadsheet(context, ref, authService, prefs),
                  icon: const Icon(Icons.add),
                  label: const Text('스프레드시트 자동 생성'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createSpreadsheet(
    BuildContext context,
    WidgetRef ref,
    GoogleAuthService authService,
    SyncPreferences prefs,
  ) async {
    try {
      final spreadsheetId = await authService.createSpreadsheet('Nacfson Health');
      await prefs.setSpreadsheetId(spreadsheetId);
      ref.invalidate(spreadsheetIdProvider);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '스프레드시트 생성 완료',
          message: '생성되었습니다: ${abbreviateSpreadsheetId(spreadsheetId)}',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '스프레드시트 생성 실패',
          message: '생성에 실패했습니다: $e',
        );
      }
    }
  }

  Future<void> _triggerSync(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncTriggerProvider.future);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '동기화 완료',
          message: '데이터가 성공적으로 동기화되었습니다.',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '동기화 실패',
          message: '동기화에 실패했습니다: $e',
        );
      }
    }
  }
}
