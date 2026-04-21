import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show SyncStatus;

class DietRecord {
  final int? id; // LOCAL ONLY - 시트 연동 시 사용 금지
  final String uuid; // 글로벌 PK (UUID v4), 빈 문자열이면 Repository에서 자동 생성
  final DateTime timestamp;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String mealType;
  final String foodName;
  final int totalCalories;
  final double carbs;
  final double protein;
  final double fat;
  final int satisfaction;
  final String? memo;

  const DietRecord({
    this.id,
    this.uuid = '', // 빈 문자열이면 Repository에서 UUID v4 자동 생성
    required this.timestamp,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
    required this.mealType,
    required this.foodName,
    required this.totalCalories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.satisfaction,
    this.memo,
  });

  DietRecord copyWith({
    int? id,
    String? uuid,
    DateTime? timestamp,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? mealType,
    String? foodName,
    int? totalCalories,
    double? carbs,
    double? protein,
    double? fat,
    int? satisfaction,
    String? memo,
  }) {
    return DietRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      mealType: mealType ?? this.mealType,
      foodName: foodName ?? this.foodName,
      totalCalories: totalCalories ?? this.totalCalories,
      carbs: carbs ?? this.carbs,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      satisfaction: satisfaction ?? this.satisfaction,
      memo: memo ?? this.memo,
    );
  }
}
