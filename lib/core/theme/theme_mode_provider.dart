import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_preferences.dart';
import '../sync/sync_state.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SyncPreferences _prefs;

  ThemeModeNotifier(this._prefs) : super(_decode(_prefs.themeModeRaw));

  Future<void> setMode(ThemeMode mode) async {
    await _prefs.setThemeModeRaw(_encode(mode));
    state = mode;
  }

  static ThemeMode _decode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.read(syncPreferencesProvider));
});
