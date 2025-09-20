import 'package:flutter/material.dart';

class PlannedIncomeStub extends StatelessWidget {
  const PlannedIncomeStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Запланированные доходы')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Здесь появится список регулярных доходов и планов. Пока это заглушка.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
