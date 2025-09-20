import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import 'categories_settings_stub.dart';
import 'necessity_settings_stub.dart';

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
    final themeMode = ref.watch(themeModeProvider);
    final themeModeNotifier = ref.read(themeModeProvider.notifier);

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
                      DropdownMenuItem(value: r'$', child: Text(r'Доллар США ($)')),
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
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Тема',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Системная'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Светлая'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Тёмная'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (modes) {
                      if (modes.isNotEmpty) {
                        themeModeNotifier.state = modes.first;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Настройки категорий'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CategoriesSettingsStub(),
                      ),
                    );
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('Критичность/Необходимость'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NecessitySettingsStub(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
