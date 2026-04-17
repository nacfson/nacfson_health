import 'package:flutter/material.dart';
import '../widgets/weight_input_card.dart';
import '../widgets/weight_chart_card.dart';

class WeightScreen extends StatelessWidget {
  const WeightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('체중 관리')),
      body: const SingleChildScrollView(
        child: Column(
          children: [
            WeightInputCard(),
            WeightChartCard(),
          ],
        ),
      ),
    );
  }
}
