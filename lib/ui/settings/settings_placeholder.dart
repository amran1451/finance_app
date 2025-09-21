import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../utils/formatting.dart';
import 'categories_manage_screen.dart';
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.tonal(
                        onPressed: () =>
                            _showAddPayoutSheet(context, PayoutType.advance),
                        child: const Text('Добавить аванс'),
                      ),
                      FilledButton.tonal(
                        onPressed: () =>
                            _showAddPayoutSheet(context, PayoutType.salary),
                        child: const Text('Добавить зарплату'),
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

  Future<void> _showAddPayoutSheet(
    BuildContext context,
    PayoutType type,
  ) async {
    final accountsRepo = ref.read(accountsRepoProvider);
    final payoutsRepo = ref.read(payoutsRepoProvider);
    final accounts = await accountsRepo.getAll();

    if (!mounted) {
      return;
    }

    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала добавьте счёт.')),
      );
      return;
    }

    final selectableAccounts =
        accounts.where((account) => account.id != null).toList();
    if (selectableAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных счетов для выплаты.')),
      );
      return;
    }

    final defaultAccount = selectableAccounts.firstWhere(
      (account) => account.name.toLowerCase() == 'карта',
      orElse: () => selectableAccounts.first,
    );
    var selectedAccountId = defaultAccount.id;
    DateTime selectedDate = DateTime.now();
    final amountController = TextEditingController();
    String? errorText;
    var isSaving = false;
    var saved = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> pickDate() async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  initialDate: selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => selectedDate = picked);
                }
              }

              Future<void> save() async {
                if (isSaving) {
                  return;
                }
                setState(() {
                  errorText = null;
                  isSaving = true;
                });

                final rawAmount = amountController.text.trim().replaceAll(',', '.');
                final parsed = double.tryParse(rawAmount);
                if (parsed == null || parsed <= 0) {
                  setState(() {
                    errorText = 'Введите сумму больше нуля';
                    isSaving = false;
                  });
                  return;
                }

                final accountId = selectedAccountId;
                if (accountId == null) {
                  setState(() {
                    errorText = 'Выберите счёт';
                    isSaving = false;
                  });
                  return;
                }

                final amountMinor = (parsed * 100).round();
                try {
                  await payoutsRepo.add(
                    type,
                    DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    ),
                    amountMinor,
                    accountId: accountId,
                  );
                } catch (error) {
                  setState(() {
                    errorText = 'Ошибка: $error';
                    isSaving = false;
                  });
                  return;
                }

                ref.invalidate(currentPayoutProvider);
                ref.invalidate(periodBudgetMinorProvider);
                ref.invalidate(plannedPoolMinorProvider);
                saved = true;
                Navigator.of(sheetContext).pop();
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    type == PayoutType.advance
                        ? 'Добавить аванс'
                        : 'Добавить зарплату',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Дата'),
                    subtitle: Text(formatDate(selectedDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: pickDate,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Сумма',
                      prefixText: '₽ ',
                      errorText: errorText,
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setState(() => errorText = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedAccountId,
                    decoration: const InputDecoration(labelText: 'Счёт'),
                    items: [
                      for (final account in selectableAccounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      selectedAccountId = value;
                    }),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () {
                                amountController.clear();
                                setState(() => errorText = null);
                              },
                        child: const Text('Очистить сумму'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: isSaving ? null : save,
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выплата добавлена')),
      );
    }
  }
}
