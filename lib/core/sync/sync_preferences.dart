import 'package:shared_preferences/shared_preferences.dart';

class SyncPreferences {
  static const _keySpreadsheetId = 'spreadsheet_id';
  static const _keyLastSyncTimestamp = 'last_sync_timestamp';
  static const _keyTargetCalories = 'target_calories';
  static const _keyTargetCarbs = 'target_carbs';
  static const _keyTargetProtein = 'target_protein';
  static const _keyTargetFat = 'target_fat';
  static const _keyUserGender = 'user_gender';
  static const _keyUserAgeGroup = 'user_age_group'; // deprecated, 마이그레이션 대상
  static const _keyUserAge = 'user_age';
  static const _keyActivityLevel = 'activity_level';
  static const _keyTrainingIntensity = 'training_intensity';
  static const _keyFitnessGoal = 'fitness_goal';
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

  // ── 사용자 프로필 (온보딩 입력) ───────────────────────────────────────────────

  /// 'male' | 'female'
  String get userGenderRaw => _prefs.getString(_keyUserGender) ?? 'male';

  Future<void> setUserGenderRaw(String v) async =>
      _prefs.setString(_keyUserGender, v);

  /// 만 나이 (int). 미저장 시 기본 30.
  int get userAge => _prefs.getInt(_keyUserAge) ?? 30;

  Future<void> setUserAge(int v) async => _prefs.setInt(_keyUserAge, v);

  /// 활동 수준 prefsKey — 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active'
  String get activityLevelRaw =>
      _prefs.getString(_keyActivityLevel) ?? 'moderate';

  Future<void> setActivityLevelRaw(String v) async =>
      _prefs.setString(_keyActivityLevel, v);

  /// 운동 강도 prefsKey — 'low' | 'moderate' | 'high' | 'very_high'
  String get trainingIntensityRaw =>
      _prefs.getString(_keyTrainingIntensity) ?? 'moderate';

  Future<void> setTrainingIntensityRaw(String v) async =>
      _prefs.setString(_keyTrainingIntensity, v);

  /// 'diet' | 'lean_cut' | 'lean_gain' | 'bulk_up' (구버전: 'lean_mass')
  String get fitnessGoalRaw => _prefs.getString(_keyFitnessGoal) ?? 'lean_gain';

  Future<void> setFitnessGoalRaw(String v) async =>
      _prefs.setString(_keyFitnessGoal, v);

  // ── 레거시 프로필 마이그레이션 ────────────────────────────────────────────────

  /// 구버전 키 → 신규 키 1회 이관. 앱 진입 시 한 번 호출한다.
  /// - `user_age_group` (20s/30s/40s/50s+) → `user_age` (25/35/45/55)
  /// - `fitness_goal == 'lean_mass'` → `'lean_gain'` 으로 재작성
  Future<void> migrateLegacyProfile() async {
    // age_group → age
    final legacyAgeGroup = _prefs.getString(_keyUserAgeGroup);
    if (legacyAgeGroup != null && !_prefs.containsKey(_keyUserAge)) {
      const midpoints = {
        '20s': 25,
        '30s': 35,
        '40s': 45,
        '50s+': 55,
      };
      final age = midpoints[legacyAgeGroup] ?? 30;
      await _prefs.setInt(_keyUserAge, age);
    }
    if (legacyAgeGroup != null) {
      await _prefs.remove(_keyUserAgeGroup);
    }

    // fitness_goal: 'lean_mass' → 'lean_gain'
    if (_prefs.getString(_keyFitnessGoal) == 'lean_mass') {
      await _prefs.setString(_keyFitnessGoal, 'lean_gain');
    }
  }

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
