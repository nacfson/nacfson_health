import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/sync/sync_preferences.dart';
import 'core/sync/sync_state.dart';
import 'features/settings/data/repositories/sqlite_exercise_template_repository.dart';
import 'features/settings/domain/entities/exercise_template.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final prefs = await SharedPreferences.getInstance();
  final syncPrefs = SyncPreferences(prefs);

  // SharedPreferences 템플릿 → SQLite 1회 마이그레이션 (Web 환경 제외)
  if (!kIsWeb) {
    final legacyTemplates = syncPrefs.exerciseTemplates;
    if (legacyTemplates.isNotEmpty) {
      final templateRepo = SqliteExerciseTemplateRepository();
      for (final name in legacyTemplates) {
        await templateRepo.add(ExerciseTemplate(
          uuid: '',
          name: name,
          updatedAt: DateTime.now(),
        ));
      }
      await syncPrefs.clearExerciseTemplates();
    }
  }

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
    final isSignedIn = ref.read(isSignedInProvider);
    if (isSignedIn) {
      ref.read(syncStateProvider.notifier).performSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NacfsonHealthApp();
  }
}
