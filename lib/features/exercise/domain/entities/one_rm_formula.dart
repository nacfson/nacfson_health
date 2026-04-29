import 'dart:convert';

import '../../../../core/training/one_rm_formula.dart';

/// admin-curated 1RM 공식. Supabase `public.one_rm_formulas` 미러.
class OneRMFormula {
  final String exerciseKey;
  final String formulaType;
  final Map<String, dynamic> coefficients;
  final String? source;
  final int? optimalRepMax;
  final Map<String, String>? noticeTranslations;
  final DateTime updatedAt;

  const OneRMFormula({
    required this.exerciseKey,
    required this.formulaType,
    required this.coefficients,
    required this.source,
    required this.optimalRepMax,
    required this.noticeTranslations,
    required this.updatedAt,
  });

  /// Locale별 안내 문구. 없으면 null.
  String? noticeFor(String locale) => noticeTranslations?[locale];

  /// 계산 가능한 spec 으로 변환. 잘못된 type/coefficients 면 null.
  OneRMFormulaSpec? toSpec() =>
      OneRMFormulaSpec.parse(formulaType, coefficients);

  Map<String, dynamic> toSqliteRow() => {
        'exercise_key': exerciseKey,
        'formula_type': formulaType,
        'coefficients': jsonEncode(coefficients),
        'source': source,
        'optimal_rep_max': optimalRepMax,
        'notice_translations':
            noticeTranslations == null ? null : jsonEncode(noticeTranslations),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory OneRMFormula.fromSqliteRow(Map<String, Object?> row) {
    final coefficientsJson = row['coefficients'] as String;
    final noticeJson = row['notice_translations'] as String?;
    return OneRMFormula(
      exerciseKey: row['exercise_key'] as String,
      formulaType: row['formula_type'] as String,
      coefficients: (jsonDecode(coefficientsJson) as Map).cast<String, dynamic>(),
      source: row['source'] as String?,
      optimalRepMax: row['optimal_rep_max'] as int?,
      noticeTranslations: noticeJson == null
          ? null
          : (jsonDecode(noticeJson) as Map).cast<String, String>(),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  factory OneRMFormula.fromSupabaseRow(Map<String, dynamic> row) {
    final notice = row['notice_translations'];
    Map<String, String>? noticeMap;
    if (notice is Map) {
      noticeMap = notice.map((k, v) => MapEntry(k as String, v as String));
    }
    return OneRMFormula(
      exerciseKey: row['exercise_key'] as String,
      formulaType: row['formula_type'] as String,
      coefficients: (row['coefficients'] as Map).cast<String, dynamic>(),
      source: row['source'] as String?,
      optimalRepMax: row['optimal_rep_max'] as int?,
      noticeTranslations: noticeMap,
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }
}
