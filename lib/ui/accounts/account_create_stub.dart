import 'package:flutter/material.dart';

class AccountCreateStub extends StatelessWidget {
  const AccountCreateStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый счёт')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Здесь будет мастер создания счёта. Добавим выбор иконки, цвета и начального баланса позже.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
