import 'dart:convert';

import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  static const _appGroupId = 'group.com.nacfson.nacfsonHealth';
  static const _iOSWidgetName = 'NacfsonHealthWidget';
  static const _dataKey = 'nutrition_widget_data';

  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

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
    await HomeWidget.saveWidgetData(_dataKey, json);
    await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
  }
}
