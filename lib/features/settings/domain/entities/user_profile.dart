import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show SyncStatus;

class UserProfile {
  final int? id;
  final String uuid;
  final String gender;
  final int age;
  final double height;
  final String goal;
  final String activityLevel;
  final String trainingIntensity;
  final int targetCalories;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const UserProfile({
    this.id,
    this.uuid = '',
    required this.gender,
    required this.age,
    required this.height,
    required this.goal,
    required this.activityLevel,
    required this.trainingIntensity,
    required this.targetCalories,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
  });

  UserProfile copyWith({
    int? id,
    String? uuid,
    String? gender,
    int? age,
    double? height,
    String? goal,
    String? activityLevel,
    String? trainingIntensity,
    int? targetCalories,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return UserProfile(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      height: height ?? this.height,
      goal: goal ?? this.goal,
      activityLevel: activityLevel ?? this.activityLevel,
      trainingIntensity: trainingIntensity ?? this.trainingIntensity,
      targetCalories: targetCalories ?? this.targetCalories,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
