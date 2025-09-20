import 'package:flutter/material.dart';

class AnalyticsPlaceholder extends StatelessWidget {
  const AnalyticsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Аналитика появится в следующих спринтах. Мы готовим графики, распределение категорий и прогнозы.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
