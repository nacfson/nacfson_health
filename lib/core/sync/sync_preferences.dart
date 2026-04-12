import 'package:shared_preferences/shared_preferences.dart';

class SyncPreferences {
  static const _keySpreadsheetId = 'spreadsheet_id';
  static const _keyLastSyncTimestamp = 'last_sync_timestamp';

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
}
