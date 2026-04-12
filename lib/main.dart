import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/sync/sync_preferences.dart';
import 'core/sync/sync_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences 초기화
  final prefs = await SharedPreferences.getInstance();
  final syncPrefs = SyncPreferences(prefs);

  runApp(
    ProviderScope(
      overrides: [
        syncPreferencesProvider.overrideWithValue(syncPrefs),
      ],
      child: const NacfsonHealthAppWithSync(),
    ),
  );
}

class NacfsonHealthAppWithSync extends ConsumerStatefulWidget {
  const NacfsonHealthAppWithSync({super.key});

  @override
  ConsumerState<NacfsonHealthAppWithSync> createState() =>
      _NacfsonHealthAppWithSyncState();
}

class _NacfsonHealthAppWithSyncState
    extends ConsumerState<NacfsonHealthAppWithSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerSync();
    }
  }

  Future<void> _triggerSync() async {
    final spreadsheetId = ref.read(spreadsheetIdProvider);
    final isSignedIn = ref.read(isSignedInProvider);

    if (spreadsheetId != null && isSignedIn) {
      // 앱 복귀 시 동기화 수행
      ref.read(syncStateProvider.notifier).performSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NacfsonHealthApp();
  }
}
