import 'package:flutter/material.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('요약/통계')),
      body: const Center(child: Text('요약/통계 화면 (뼈대)')),
    );
  }
}
