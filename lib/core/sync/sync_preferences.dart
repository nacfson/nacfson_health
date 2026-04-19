import 'package:shared_preferences/shared_preferences.dart';

class SyncPreferences {
  static const _keySpreadsheetId = 'spreadsheet_id';
  static const _keyLastSyncTimestamp = 'last_sync_timestamp';
  static const _keyTargetCalories = 'target_calories';
  static const _keyTargetCarbs = 'target_carbs';
  static const _keyTargetProtein = 'target_protein';
  static const _keyTargetFat = 'target_fat';
  static const _keyThemeMode = 'theme_mode';

  final SharedPreferences _prefs;

  SyncPreferences(this._prefs);

  String? get spreadsheetId => _prefs.getString(_keySpreadsheetId);

  Future<void> setSpreadsheetId(String id) async {
    await _prefs.setString(_keySpreadsheetId, id);
  }

  Future<void> clearSpreadsheetId() async {
    await _prefs.remove(_keySpreadsheetId);
  }

  int? get lastSyncTimestamp => _prefs.getInt(_keyLastSyncTimestamp);

  DateTime? get lastSyncTime => lastSyncTimestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp!)
      : null;

  Future<void> updateLastSyncTimestamp() async {
    await _prefs.setInt(
      _keyLastSyncTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> clearLastSyncTimestamp() async {
    await _prefs.remove(_keyLastSyncTimestamp);
  }

  // ── 영양 목표값 ──────────────────────────────────────────────────────────────

  int get targetCalories => _prefs.getInt(_keyTargetCalories) ?? 1800;
  double get targetCarbs => _prefs.getDouble(_keyTargetCarbs) ?? 250.0;
  double get targetProtein => _prefs.getDouble(_keyTargetProtein) ?? 150.0;
  double get targetFat => _prefs.getDouble(_keyTargetFat) ?? 60.0;

  Future<void> setTargetCalories(int v) async =>
      _prefs.setInt(_keyTargetCalories, v);
  Future<void> setTargetCarbs(double v) async =>
      _prefs.setDouble(_keyTargetCarbs, v);
  Future<void> setTargetProtein(double v) async =>
      _prefs.setDouble(_keyTargetProtein, v);
  Future<void> setTargetFat(double v) async =>
      _prefs.setDouble(_keyTargetFat, v);

  // ── 테마 모드 ────────────────────────────────────────────────────────────────

  /// "system" | "light" | "dark" (기본: "system")
  String get themeModeRaw => _prefs.getString(_keyThemeMode) ?? 'system';

  Future<void> setThemeModeRaw(String mode) async =>
      _prefs.setString(_keyThemeMode, mode);

  // ── 운동 템플릿 ───────────────────────────────────────────────────────────────

  static const _keyExerciseTemplates = 'exercise_templates';

  List<String> get exerciseTemplates =>
      _prefs.getStringList(_keyExerciseTemplates) ?? [];

  Future<void> setExerciseTemplates(List<String> templates) async =>
      _prefs.setStringList(_keyExerciseTemplates, templates);

  /// SharedPreferences → SQLite 마이그레이션 완료 후 레거시 키를 제거합니다.
  Future<void> clearExerciseTemplates() async =>
      _prefs.remove(_keyExerciseTemplates);

  // ── 휴식 타이머 ──────────────────────────────────────────────────────────────

  static const _keyDefaultRestSeconds = 'default_rest_seconds';

  int get defaultRestSeconds => _prefs.getInt(_keyDefaultRestSeconds) ?? 90;

  Future<void> setDefaultRestSeconds(int seconds) async =>
      _prefs.setInt(_keyDefaultRestSeconds, seconds);
}
