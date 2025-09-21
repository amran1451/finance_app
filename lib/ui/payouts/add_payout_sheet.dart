import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../utils/formatting.dart';

Future<bool> showAddPayoutSheet(
  BuildContext context,
  WidgetRef ref, {
  required PayoutType type,
}) async {
  final accountsRepo = ref.read(accountsRepoProvider);
  final payoutsRepo = ref.read(payoutsRepoProvider);
  final accounts = await accountsRepo.getAll();

  if (!context.mounted) {
    return false;
  }

  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сначала добавьте счёт.')),
    );
    return false;
  }

  final selectableAccounts =
      accounts.where((account) => account.id != null).toList();
  if (selectableAccounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет доступных счетов для выплаты.')),
    );
    return false;
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

              final rawAmount =
                  amountController.text.trim().replaceAll(',', '.');
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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

  amountController.dispose();

  if (!context.mounted) {
    return saved;
  }

  if (saved) {
    ref.invalidate(currentPayoutProvider);
    ref.invalidate(currentPeriodProvider);
    ref.invalidate(periodBudgetMinorProvider);
    ref.invalidate(plannedPoolMinorProvider);
  }

  return saved;
}
