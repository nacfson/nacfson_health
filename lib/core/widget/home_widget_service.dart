import 'dart:convert';

import 'package:home_widget/home_widget.dart';

/// iOS 홈스크린 위젯과 데이터를 주고받는 어댑터.
///
/// App Group `group.com.nacfson.nacfsonHealth` 의 UserDefaults 를 채널로 사용한다.
/// Live Activity(`RestActivityWidget`) 와 같은 그룹을 공유하지만 키가 분리돼 있어 충돌 없음.
///
/// - 영양 위젯(`NutritionWidget`)  -> [_iOSNutritionWidgetName] / [_nutritionKey]
/// - 운동 잔디 위젯(`WorkoutHeatmapWidget`) -> [_iOSHeatmapWidgetName] / [_heatmapKey]
class HomeWidgetService {
  static const _appGroupId = 'group.com.nacfson.nacfsonHealth';

  // ── Nutrition ──────────────────────────────────────────────────────────────
  static const _iOSNutritionWidgetName = 'NacfsonHealthWidget';
  static const _nutritionKey = 'nutrition_widget_data';

  // ── Workout heatmap ────────────────────────────────────────────────────────
  static const _iOSHeatmapWidgetName = 'WorkoutHeatmapWidget';
  static const _heatmapKey = 'heatmap_widget_data';

  /// App Group 등록. 앱 시작 시 한 번 호출.
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// 오늘 영양 정보 위젯 갱신.
  static Future<void> update({
    required int calories,
    required int targetCalories,
    required double carbs,
    required double targetCarbs,
    required double protein,
    required double targetProtein,
    required double fat,
    required double targetFat,
  }) async {
    final json = jsonEncode({
      'calories': calories,
      'targetCalories': targetCalories,
      'carbs': carbs,
      'targetCarbs': targetCarbs,
      'protein': protein,
      'targetProtein': targetProtein,
      'fat': fat,
      'targetFat': targetFat,
    });
    await HomeWidget.saveWidgetData(_nutritionKey, json);
    await HomeWidget.updateWidget(iOSName: _iOSNutritionWidgetName);
  }

  /// 운동 잔디밭 위젯 갱신.
  ///
  /// [volumeByDay] : 자정(midnight) 기준 DateTime → 일별 본세트 볼륨(kg) 합계.
  ///                 `heatmapDataProvider` 결과를 그대로 넘기면 된다.
  /// [gridStart]   : 13주 그리드의 시작 월요일(자정). 기본값은
  ///                 `mondayOfThisWeek - 7*12` = 91일 그리드.
  ///
  /// 분위수(q1/q2/q3) 와 셀 배열을 미리 계산해 Swift 측에서 그대로 색을 매핑한다.
  /// (참고: lib/features/summary/presentation/widgets/workout_heatmap_card.dart 의 _colorFor)
  static Future<void> updateHeatmap({
    required Map<DateTime, double> volumeByDay,
    DateTime? gridStart,
  }) async {
    const totalDays = 7 * 13; // 91
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mondayOfThisWeek = today.subtract(Duration(days: today.weekday - 1));
    final start = gridStart ??
        mondayOfThisWeek.subtract(const Duration(days: 7 * 12));

    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final cells = <Map<String, dynamic>>[];
    final positives = <double>[];
    for (var w = 0; w < 13; w++) {
      for (var dow = 0; dow < 7; dow++) {
        final d = start.add(Duration(days: 7 * w + dow));
        final key = DateTime(d.year, d.month, d.day);
        final v = volumeByDay[key] ?? 0.0;
        cells.add({'d': fmt(d), 'v': v});
        if (v > 0) positives.add(v);
      }
    }
    positives.sort();

    double quantile(double p) {
      if (positives.isEmpty) return 0;
      final idx = (positives.length * p).floor()
          .clamp(0, positives.length - 1);
      return positives[idx];
    }

    final json = jsonEncode({
      'cells': cells,
      'q1': quantile(0.25),
      'q2': quantile(0.50),
      'q3': quantile(0.75),
      'gridStart': fmt(start),
    });
    // Swift 측이 byColumn(13주) → byRow(7요일) 순으로 인덱스를 읽으므로
    // 위 루프를 (week-major) 로 작성한 것과 일치한다.
    assert(cells.length == totalDays);

    await HomeWidget.saveWidgetData(_heatmapKey, json);
    await HomeWidget.updateWidget(iOSName: _iOSHeatmapWidgetName);
  }
}
