import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/food_template.dart';
import 'food_template_repository.dart';

class SqliteFoodTemplateRepository implements FoodTemplateRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<FoodTemplate>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'food_templates',
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
      orderBy: 'updated_at ASC',
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> add(FoodTemplate template) async {
    final db = await _dbHelper.database;
    final record = template.copyWith(
      uuid: template.uuid.isEmpty ? _uuid.v4() : template.uuid,
      syncStatus: TemplateSyncStatus.created,
    );
    await db.insert(
      'food_templates',
      _toMap(record),
      conflictAlgorithm: ConflictAlgorithm.ignore, // name UNIQUE 충돌 시 무시
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'food_templates',
      {
        'sync_status': TemplateSyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<FoodTemplate>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'food_templates',
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.synced.value],
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      'food_templates',
      {'sync_status': TemplateSyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteTemplates(List<FoodTemplate> remote) async {
    // 수정 연산 없음 — 로컬에 없는 것만 insert, 이미 있으면 skip
    for (final t in remote) {
      final existing = await _findByUuid(t.uuid);
      if (existing == null) {
        final db = await _dbHelper.database;
        await db.insert(
          'food_templates',
          _toMap(t.copyWith(syncStatus: TemplateSyncStatus.synced)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // 이미 있으면 무시 (수정 연산 없음)
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'food_templates',
      where: 'sync_status = ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'food_templates',
      {'sync_status': TemplateSyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<FoodTemplate?> _findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'food_templates',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Map<String, dynamic> _toMap(FoodTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'calories': t.calories,
        'carbs': t.carbs,
        'protein': t.protein,
        'fat': t.fat,
        'updated_at': t.updatedAt.millisecondsSinceEpoch,
        'sync_status': t.syncStatus.value,
      };

  FoodTemplate _fromMap(Map<String, dynamic> map) => FoodTemplate(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        calories: map['calories'] as int,
        carbs: (map['carbs'] as num).toDouble(),
        protein: (map['protein'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        syncStatus: TemplateSyncStatus.fromInt(map['sync_status'] as int),
      );
}
