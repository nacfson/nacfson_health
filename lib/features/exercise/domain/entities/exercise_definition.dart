/// admin-curated 마스터 운동 정의. Supabase `public.exercise_definitions` 미러.
class ExerciseDefinition {
  final String exerciseKey;
  final String categoryKey;
  final bool isCompound;
  final String defaultName;
  final DateTime updatedAt;

  const ExerciseDefinition({
    required this.exerciseKey,
    required this.categoryKey,
    required this.isCompound,
    required this.defaultName,
    required this.updatedAt,
  });

  Map<String, dynamic> toSqliteRow() => {
        'exercise_key': exerciseKey,
        'category_key': categoryKey,
        'is_compound': isCompound ? 1 : 0,
        'default_name': defaultName,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ExerciseDefinition.fromSqliteRow(Map<String, Object?> row) =>
      ExerciseDefinition(
        exerciseKey: row['exercise_key'] as String,
        categoryKey: row['category_key'] as String,
        isCompound: (row['is_compound'] as int) == 1,
        defaultName: row['default_name'] as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  factory ExerciseDefinition.fromSupabaseRow(Map<String, dynamic> row) =>
      ExerciseDefinition(
        exerciseKey: row['exercise_key'] as String,
        categoryKey: row['category_key'] as String,
        isCompound: (row['is_compound'] as bool?) ?? false,
        defaultName: row['default_name'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      );
}
