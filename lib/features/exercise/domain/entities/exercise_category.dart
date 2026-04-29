/// 운동 카테고리 마스터. Supabase `public.exercise_categories` 미러.
class ExerciseCategory {
  final String categoryKey;
  final int displayOrder;
  final DateTime updatedAt;

  const ExerciseCategory({
    required this.categoryKey,
    required this.displayOrder,
    required this.updatedAt,
  });

  Map<String, dynamic> toSqliteRow() => {
        'category_key': categoryKey,
        'display_order': displayOrder,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ExerciseCategory.fromSqliteRow(Map<String, Object?> row) =>
      ExerciseCategory(
        categoryKey: row['category_key'] as String,
        displayOrder: row['display_order'] as int,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  factory ExerciseCategory.fromSupabaseRow(Map<String, dynamic> row) =>
      ExerciseCategory(
        categoryKey: row['category_key'] as String,
        displayOrder: (row['display_order'] as int?) ?? 0,
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      );
}

/// 카테고리 locale별 표시명. Supabase `public.exercise_category_translations` 미러.
class ExerciseCategoryTranslation {
  final String categoryKey;
  final String locale;
  final String displayName;
  final DateTime updatedAt;

  const ExerciseCategoryTranslation({
    required this.categoryKey,
    required this.locale,
    required this.displayName,
    required this.updatedAt,
  });

  Map<String, dynamic> toSqliteRow() => {
        'category_key': categoryKey,
        'locale': locale,
        'display_name': displayName,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ExerciseCategoryTranslation.fromSqliteRow(Map<String, Object?> row) =>
      ExerciseCategoryTranslation(
        categoryKey: row['category_key'] as String,
        locale: row['locale'] as String,
        displayName: row['display_name'] as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  factory ExerciseCategoryTranslation.fromSupabaseRow(
          Map<String, dynamic> row) =>
      ExerciseCategoryTranslation(
        categoryKey: row['category_key'] as String,
        locale: row['locale'] as String,
        displayName: row['display_name'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      );
}
