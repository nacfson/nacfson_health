/// 루틴을 구성하는 개별 운동 항목 (계획 전용, 기록 아님).
class RoutineItem {
  final String exerciseType;
  final String exerciseName;

  const RoutineItem({
    required this.exerciseType,
    required this.exerciseName,
  });

  Map<String, dynamic> toJson() => {
        'type': exerciseType,
        'name': exerciseName,
      };

  factory RoutineItem.fromJson(Map<String, dynamic> json) => RoutineItem(
        exerciseType: (json['type'] as String?) ?? '',
        exerciseName: (json['name'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is RoutineItem &&
      other.exerciseType == exerciseType &&
      other.exerciseName == exerciseName;

  @override
  int get hashCode => Object.hash(exerciseType, exerciseName);
}
