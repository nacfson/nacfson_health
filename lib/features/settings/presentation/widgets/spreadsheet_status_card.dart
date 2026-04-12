import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/sync/google_auth_service.dart';
import '../../../../core/sync/sync_preferences.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../../../exercise/presentation/providers/exercise_provider.dart';
import '../../../diet/presentation/providers/diet_provider.dart';
import '../../utils/date_time_utils.dart';

enum _SpreadsheetAction { recreate, selectById }

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
                  spreadsheetId != null
                      ? Icons.table_chart
                      : Icons.table_chart_outlined,
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          isSyncing ? null : () => _triggerSync(context, ref),
                      icon: isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(isSyncing ? '동기화 중...' : '지금 동기화'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_SpreadsheetAction>(
                    enabled: !isSyncing,
                    onSelected: (action) => _onModifySelected(
                        context, ref, action, authService, prefs),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: _SpreadsheetAction.recreate,
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('재생성'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _SpreadsheetAction.selectById,
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('직접 선택'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('수정'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                '스프레드시트에 연결되어 있지 않습니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _createSpreadsheet(context, ref, authService, prefs),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('생성하기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showSelectByIdDialogInitial(context, ref, prefs),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('직접 연결하기'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 최초 설정 — 생성하기
  // =========================================================================

  Future<void> _createSpreadsheet(
    BuildContext context,
    WidgetRef ref,
    GoogleAuthService authService,
    SyncPreferences prefs,
  ) async {
    try {
      final newId = await authService.createSpreadsheet('Nacfson Health');
      await prefs.setSpreadsheetId(newId);
      ref.invalidate(spreadsheetIdProvider);
      ref.invalidate(syncStateProvider);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '스프레드시트 생성 완료',
          message: '생성되었습니다: ${abbreviateSpreadsheetId(newId)}',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '스프레드시트 생성 실패',
          message: '생성에 실패했습니다: ${_friendlyErrorMessage(e)}',
        );
      }
    }
  }

  // =========================================================================
  // 최초 설정 — 직접 연결하기
  // =========================================================================

  Future<void> _showSelectByIdDialogInitial(
    BuildContext context,
    WidgetRef ref,
    SyncPreferences prefs,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('스프레드시트 직접 연결'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'URL 또는 ID',
              hintText: 'https://docs.google.com/spreadsheets/d/...',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '입력해주세요';
              if (_extractSpreadsheetId(v.trim()) == null) {
                return '올바른 URL 또는 ID가 아닙니다';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('연결하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newId = _extractSpreadsheetId(controller.text.trim())!;
    try {
      await prefs.setSpreadsheetId(newId);
      ref.invalidate(spreadsheetIdProvider);
      ref.invalidate(syncStateProvider);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '연결 완료',
          message: '스프레드시트가 연결되었습니다.',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '연결 실패',
          message: _friendlyErrorMessage(e),
        );
      }
    }
  }

  // =========================================================================
  // 교체 — 수정 ▼ 메뉴 분기
  // =========================================================================

  Future<void> _onModifySelected(
    BuildContext context,
    WidgetRef ref,
    _SpreadsheetAction action,
    GoogleAuthService authService,
    SyncPreferences prefs,
  ) async {
    switch (action) {
      case _SpreadsheetAction.recreate:
        await _showRecreateDialog(context, ref, authService, prefs);
      case _SpreadsheetAction.selectById:
        await _showSelectByIdDialog(context, ref, prefs);
    }
  }

  // =========================================================================
  // 교체 — 재생성 다이얼로그
  // =========================================================================

  Future<void> _showRecreateDialog(
    BuildContext context,
    WidgetRef ref,
    GoogleAuthService authService,
    SyncPreferences prefs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('스프레드시트 재생성'),
        content: const Text(
          '새 스프레드시트를 생성하고 모든 로컬 데이터를 새 시트에 업로드합니다.\n'
          '기존 시트는 삭제되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('재생성'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final newId = await authService.createSpreadsheet('Nacfson Health');
      await _replaceSpreadsheet(ref, newId, prefs);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '재생성 완료',
          message: '새 시트로 교체되었습니다.',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '재생성 실패',
          message: _friendlyErrorMessage(e),
        );
      }
    }
  }

  // =========================================================================
  // 교체 — 직접 선택 다이얼로그
  // =========================================================================

  Future<void> _showSelectByIdDialog(
    BuildContext context,
    WidgetRef ref,
    SyncPreferences prefs,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('스프레드시트 직접 연결'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'URL 또는 ID',
              hintText: 'https://docs.google.com/spreadsheets/d/...',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return '입력해주세요';
              if (_extractSpreadsheetId(v.trim()) == null) {
                return '올바른 URL 또는 ID가 아닙니다';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('연결하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newId = _extractSpreadsheetId(controller.text.trim())!;
    try {
      await _replaceSpreadsheet(ref, newId, prefs);
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '연결 완료',
          message: '스프레드시트가 변경되었습니다.',
          type: OverlayType.info,
        );
      }
    } catch (e) {
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(
          title: '연결 실패',
          message: _friendlyErrorMessage(e),
        );
      }
    }
  }

  // =========================================================================
  // 동기화 트리거
  // =========================================================================

  Future<void> _triggerSync(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(syncStateProvider.notifier).performSync();

      if (result.hasErrors) {
        if (rootNavigatorKey.currentState?.overlay != null) {
          ErrorOverlay.show(
            title: '네트워크 또는 동기화 에러',
            message: '일부 진행 중 문제가 발생했습니다: ${result.errorMessage}',
          );
        }
      } else {
        ref.invalidate(lastSyncTimeProvider);
        if (rootNavigatorKey.currentState?.overlay != null) {
          ErrorOverlay.show(
            title: '동기화 완료',
            message: '데이터가 성공적으로 구글 시트와 동기화되었습니다.',
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

  // =========================================================================
  // 공통 헬퍼
  // =========================================================================

  /// 스프레드시트 교체: syncStatus 초기화 → 새 ID 저장 → provider 갱신 → 동기화
  Future<void> _replaceSpreadsheet(
    WidgetRef ref,
    String newId,
    SyncPreferences prefs,
  ) async {
    // 1. 모든 로컬 레코드를 created 상태로 초기화 (새 시트에 전체 재업로드)
    await ref.read(exerciseRepositoryProvider).resetAllSyncStatus();
    await ref.read(dietRepositoryProvider).resetAllSyncStatus();
    // 2. 마지막 동기화 시간 초기화 (전체 pull 강제)
    await prefs.clearLastSyncTimestamp();
    // 3. 새 ID 저장 후 provider chain 갱신
    await prefs.setSpreadsheetId(newId);
    ref.invalidate(spreadsheetIdProvider);
    ref.invalidate(syncStateProvider); // SyncStateNotifier를 새 sheetsService로 재생성
    // 4. 동기화 실행
    final result = await ref.read(syncStateProvider.notifier).performSync();
    if (!result.hasErrors) {
      ref.invalidate(lastSyncTimeProvider);
    }
  }

  /// URL 또는 직접 ID에서 spreadsheetId 추출
  static String? _extractSpreadsheetId(String input) {
    final urlMatch =
        RegExp(r'spreadsheets/d/([a-zA-Z0-9\-_]+)').firstMatch(input);
    if (urlMatch != null) return urlMatch.group(1);
    if (RegExp(r'^[a-zA-Z0-9\-_]{20,}$').hasMatch(input)) return input;
    return null;
  }

  /// Exception 메시지를 사용자 친화적으로 축약하는 헬퍼
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
