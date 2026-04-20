import 'exercise_record.dart' show SyncStatus;
import 'routine_item.dart';

/// 저장된 루틴 프리셋. 사용자가 "가슴 & 삼두" 같은 이름으로 저장해두고
/// 재사용할 수 있는 운동 목록.
class WorkoutRoutine {
  final int? id; // LOCAL ONLY — 시트/서버 연동 시 사용 금지
  final String uuid; // 글로벌 PK (UUID v4)
  final String name;
  final List<RoutineItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const WorkoutRoutine({
    this.id,
    this.uuid = '',
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
  });

  WorkoutRoutine copyWith({
    int? id,
    String? uuid,
    String? name,
    List<RoutineItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return WorkoutRoutine(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
