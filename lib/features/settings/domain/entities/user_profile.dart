import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show SyncStatus;

class UserProfile {
  final int? id;
  final String uuid;
  final String gender;
  final String ageGroup;
  final double height;
  final String goal;
  final int targetCalories;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const UserProfile({
    this.id,
    this.uuid = '',
    required this.gender,
    required this.ageGroup,
    required this.height,
    required this.goal,
    required this.targetCalories,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
  });

  UserProfile copyWith({
    int? id,
    String? uuid,
    String? gender,
    String? ageGroup,
    double? height,
    String? goal,
    int? targetCalories,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return UserProfile(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      gender: gender ?? this.gender,
      ageGroup: ageGroup ?? this.ageGroup,
      height: height ?? this.height,
      goal: goal ?? this.goal,
      targetCalories: targetCalories ?? this.targetCalories,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
