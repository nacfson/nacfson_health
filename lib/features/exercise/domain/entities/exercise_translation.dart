import 'dart:convert';

/// 운동 종목의 locale별 표시명. Supabase `public.exercise_translations` 미러.
class ExerciseTranslation {
  final String exerciseKey;
  final String locale;
  final String displayName;
  final List<String> aliases;
  final DateTime updatedAt;

  const ExerciseTranslation({
    required this.exerciseKey,
    required this.locale,
    required this.displayName,
    required this.aliases,
    required this.updatedAt,
  });

  Map<String, dynamic> toSqliteRow() => {
        'exercise_key': exerciseKey,
        'locale': locale,
        'display_name': displayName,
        'aliases': aliases.isEmpty ? null : jsonEncode(aliases),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ExerciseTranslation.fromSqliteRow(Map<String, Object?> row) {
    final aliasesRaw = row['aliases'] as String?;
    final aliases = aliasesRaw == null
        ? <String>[]
        : (jsonDecode(aliasesRaw) as List).cast<String>();
    return ExerciseTranslation(
      exerciseKey: row['exercise_key'] as String,
      locale: row['locale'] as String,
      displayName: row['display_name'] as String,
      aliases: aliases,
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  factory ExerciseTranslation.fromSupabaseRow(Map<String, dynamic> row) {
    final rawAliases = row['aliases'];
    final aliases = rawAliases is List
        ? rawAliases.cast<String>()
        : <String>[];
    return ExerciseTranslation(
      exerciseKey: row['exercise_key'] as String,
      locale: row['locale'] as String,
      displayName: row['display_name'] as String,
      aliases: aliases,
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }
}
