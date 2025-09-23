import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/ref_postframe.dart';
import '../payouts/payout_edit_sheet.dart';
import 'categories_manage_screen.dart';
import 'necessity_settings_screen.dart';
import 'reasons_settings_screen.dart';
import '../home/daily_limit_sheet.dart';

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

    final suggestedType = ref.watch(payoutSuggestedTypeProvider);
    final generalPayoutLabel =
        'Добавить выплату (по периоду: ${payoutTypeLabel(suggestedType)})';

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
                      if (modes.isEmpty) {
                        return;
                      }

                      final selectedMode = modes.first;
                      if (selectedMode == themeModeNotifier.state) {
                        return;
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        themeModeNotifier.state = selectedMode;
                      });
                    },
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
                    'Выплаты',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(generalPayoutLabel),
                        subtitle: const Text(
                          'Тип выбирается автоматически по текущему полупериоду.',
                        ),
                        onTap: () => _showPayoutSheet(context),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.trending_up_outlined),
                        title: const Text('Добавить аванс'),
                        subtitle: const Text('Тип фиксирован как аванс.'),
                        onTap: () =>
                            _showPayoutSheet(context, forcedType: PayoutType.advance),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_money_outlined),
                        title: const Text('Добавить зарплату'),
                        subtitle: const Text('Тип фиксирован как зарплата.'),
                        onTap: () =>
                            _showPayoutSheet(context, forcedType: PayoutType.salary),
                      ),
                    ],
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
                        builder: (_) => const CategoriesManageScreen(),
                      ),
                    );
                  },
                  onLongPress: () => _restoreDefaultCategories(context),
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('Критичность/Необходимость'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NecessitySettingsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('Причины расходов'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReasonsSettingsScreen(),
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

  Future<void> _showPayoutSheet(
    BuildContext context, {
    PayoutType? forcedType,
  }) async {
    final tickBefore = ref.read(dbTickProvider);
    await showPayoutEditSheet(
      context,
      forcedType: forcedType,
    );

    if (!mounted) {
      return;
    }

    final tickAfter = ref.read(dbTickProvider);
    if (tickAfter == tickBefore) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Выплата добавлена')),
    );
    final dailyLimitValue = ref
        .read(dailyLimitProvider)
        .maybeWhen(data: (value) => value ?? 0, orElse: () => 0);
    if (dailyLimitValue == 0) {
      ref.postFrame(() {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Назначьте дневной лимит'),
            action: SnackBarAction(
              label: 'Задать',
              onPressed: () {
                showEditDailyLimitSheet(context, ref).then((saved) {
                  if (!mounted || !saved) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Лимит сохранён')),
                  );
                });
              },
            ),
          ),
        );
      });
    }
  }

  Future<void> _restoreDefaultCategories(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Восстановить базовые категории?'),
              content: const Text(
                'Недостающие предустановленные категории будут добавлены. '
                'Ваши собственные категории останутся без изменений.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Восстановить'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final repository = ref.read(categoriesRepositoryProvider);

    try {
      await repository.restoreDefaults();
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Базовые категории восстановлены')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось восстановить: $error')),
      );
    }
  }
}
