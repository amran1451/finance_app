import 'package:flutter/material.dart';

class AccountEditStub extends StatelessWidget {
  const AccountEditStub({super.key, this.accountName});

  final String? accountName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(accountName ?? 'Редактирование счёта')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Редактирование счёта "${accountName ?? 'Без названия'}" появится позже. Здесь будут настройки лимитов и интеграций.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
