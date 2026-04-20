import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/daily_routine.dart';
import '../../domain/entities/routine_item.dart';

/// 오늘(또는 임의 일자) 운동 루틴 계획. 로컬 전용 — 서버에 동기화하지 않음.
abstract class DailyRoutineRepository {
  Future<DailyRoutine?> getByDate(DateTime date);
  Future<void> upsert(DailyRoutine routine);
  Future<void> deleteByDate(DateTime date);
}

class SqliteDailyRoutineRepository implements DailyRoutineRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  @override
  Future<DailyRoutine?> getByDate(DateTime date) async {
    final db = await _dbHelper.database;
    final key = DailyRoutine.formatDate(date);
    final result = await db.query(
      'daily_routine',
      where: 'date = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  @override
  Future<void> upsert(DailyRoutine routine) async {
    final db = await _dbHelper.database;
    await db.insert(
      'daily_routine',
      _toMap(routine),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    final db = await _dbHelper.database;
    final key = DailyRoutine.formatDate(date);
    await db.delete('daily_routine', where: 'date = ?', whereArgs: [key]);
  }

  Map<String, dynamic> _toMap(DailyRoutine r) => {
        'date': DailyRoutine.formatDate(r.date),
        'items_json': jsonEncode(r.items.map((i) => i.toJson()).toList()),
        'updated_at': r.updatedAt.millisecondsSinceEpoch,
      };

  DailyRoutine _fromMap(Map<String, dynamic> map) {
    final decoded = jsonDecode(map['items_json'] as String) as List;
    final items = decoded
        .map((e) => RoutineItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return DailyRoutine(
      id: map['id'] as int?,
      date: DailyRoutine.parseDate(map['date'] as String),
      items: items,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
