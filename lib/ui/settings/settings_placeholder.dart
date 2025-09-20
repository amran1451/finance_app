import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';

class SettingsPlaceholder extends ConsumerStatefulWidget {
  const SettingsPlaceholder({super.key});

  @override
  ConsumerState<SettingsPlaceholder> createState() => _SettingsPlaceholderState();
}

class _SettingsPlaceholderState extends ConsumerState<SettingsPlaceholder> {
  String _selectedCurrency = '₽';

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(periodsProvider);
    final activePeriod = ref.watch(activePeriodProvider);
    final controller = ref.read(activePeriodProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Период бюджета по умолчанию',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: activePeriod.id,
                    items: [
                      for (final period in periods)
                        DropdownMenuItem(
                          value: period.id,
                          child: Text(period.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        controller.setActive(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'В следующих спринтах можно будет выбрать кастомные даты начала и окончания периода.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Валюта приложения',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedCurrency,
                    items: const [
                      DropdownMenuItem(value: '₽', child: Text('Российский рубль (₽)')),
                      DropdownMenuItem(value: '€', child: Text('Евро (€)')),
                      DropdownMenuItem(value: '$', child: Text('Доллар США ($)')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedCurrency = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Сейчас используется $_selectedCurrency. Позже валюта будет влиять на формат отображения и синхронизацию.',
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
