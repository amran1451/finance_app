import 'package:flutter/material.dart';

class CategoriesSettingsStub extends StatelessWidget {
  const CategoriesSettingsStub({super.key});

  static const _mockCategories = [
    'Питание',
    'Транспорт',
    'Дом',
    'Развлечения',
    'Здоровье',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки категорий')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Здесь появится управление категориями бюджета. Пока что список статичный.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final category in _mockCategories) ...[
                  ListTile(
                    title: Text(category),
                    leading: const Icon(Icons.label_outline),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                  if (category != _mockCategories.last)
                    const Divider(height: 0),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Добавление категорий появится позже'),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
