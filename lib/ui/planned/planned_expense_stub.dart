import 'package:flutter/material.dart';

class PlannedExpenseStub extends StatelessWidget {
  const PlannedExpenseStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Запланированные расходы')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Скоро здесь можно будет управлять будущими расходами и напоминаниями.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
