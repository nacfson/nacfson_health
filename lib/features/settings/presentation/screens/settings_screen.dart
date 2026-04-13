import 'package:flutter/material.dart';

import '../widgets/diet_target_card.dart';
import '../widgets/exercise_template_card.dart';
import '../widgets/food_template_card.dart';
import '../widgets/google_sign_in_card.dart';
import '../widgets/spreadsheet_status_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DietTargetCard(),
          const SizedBox(height: 16),
          const ExerciseTemplateCard(),
          const SizedBox(height: 16),
          const FoodTemplateCard(),
          const SizedBox(height: 16),
          const GoogleSignInCard(),
          const SizedBox(height: 16),
          const SpreadsheetStatusCard(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        '연동 안내',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '운동 및 식단 기록을 Google Sheets에 자동 백업합니다.\n'
                    '데이터 손실 방지와 멀티 디바이스 동기화가 가능합니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
