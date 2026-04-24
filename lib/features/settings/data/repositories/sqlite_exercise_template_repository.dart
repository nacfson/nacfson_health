import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/base_template_syncable_sqlite_repository.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/exercise_template.dart';
import '../default_exercise_templates.dart';
import 'exercise_template_repository.dart';

class SqliteExerciseTemplateRepository
    extends BaseTemplateSyncableSqliteRepository<ExerciseTemplate>
    implements ExerciseTemplateRepository {
  @override
  String get tableName => 'exercise_templates';

  @override
  ExerciseTemplate copyWithSync(
    ExerciseTemplate entity, {
    String? uuid,
    TemplateSyncStatus? syncStatus,
  }) =>
      // restSecondsOverride 는 copyWith sentinel 을 건드리지 않도록 생략.
      entity.copyWith(uuid: uuid, syncStatus: syncStatus);

  @override
  Future<int> seedDefaults(List<DefaultExerciseTemplateSeed> seeds) async {
    final db = await DatabaseHelper.instance.database;
    const uuidGen = Uuid();
    final now = DateTime.now();
    int inserted = 0;
    for (final s in seeds) {
      // 결정론적 UUID v5: 다중 기기에서도 동일 이름은 동일 UUID
      final uuid = uuidGen.v5(
        Namespace.oid.value,
        'nacfson-default-exercise:${s.name}',
      );
      final count = await db.insert(
        tableName,
        {
          'uuid': uuid,
          'name': s.name,
          'exercise_type': s.exerciseType,
          // rest_seconds_override: NULL 로 두어 부위 기본값이 fallback 되도록 한다.
          'rest_seconds_override': null,
          'updated_at': now.millisecondsSinceEpoch,
          'sync_status': TemplateSyncStatus.created.value,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (count > 0) inserted++;
    }
    return inserted;
  }

  @override
  Future<void> updateRestOverride(String uuid, int? seconds) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      tableName,
      {
        'rest_seconds_override': seconds,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        // upsert 대상으로 마킹 — 다음 sync 에서 Supabase 로 push.
        'sync_status': TemplateSyncStatus.created.value,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Map<String, dynamic> toMap(ExerciseTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'exercise_type': t.exerciseType,
        'rest_seconds_override': t.restSecondsOverride,
        'updated_at': t.updatedAt.millisecondsSinceEpoch,
        'sync_status': t.syncStatus.value,
      };

  @override
  ExerciseTemplate fromMap(Map<String, dynamic> map) => ExerciseTemplate(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        exerciseType: map['exercise_type'] as String? ?? '',
        restSecondsOverride: map['rest_seconds_override'] as int?,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        syncStatus: TemplateSyncStatus.fromInt(map['sync_status'] as int),
      );
}
