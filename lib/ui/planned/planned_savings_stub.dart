import 'package:flutter/material.dart';

class PlannedSavingsStub extends StatelessWidget {
  const PlannedSavingsStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Планы по сбережениям')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Копилки и цели по сбережениям появятся позже. Здесь можно будет отслеживать прогресс.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
