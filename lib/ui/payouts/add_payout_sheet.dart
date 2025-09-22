import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart' as db;
import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';

Future<bool> showAddPayoutSheet(
  BuildContext context, {
  required PayoutType type,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PayoutAddSheet(type: type),
  );

  return result ?? false;
}

class _PayoutAddSheet extends ConsumerStatefulWidget {
  const _PayoutAddSheet({
    required this.type,
    super.key,
  });

  final PayoutType type;

  @override
  ConsumerState<_PayoutAddSheet> createState() => _PayoutAddSheetState();
}

class _PayoutAddSheetState extends ConsumerState<_PayoutAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  DateTime _date = DateTime.now();
  int? _accountId;
  bool _accountInitialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsDbProvider);
    final accounts = accountsAsync.value ?? const <db.Account>[];
    final availableAccounts = accounts
        .where((account) => !account.isArchived && account.id != null)
        .toList();

    if (!_accountInitialized && availableAccounts.isNotEmpty) {
      final defaultAccount = availableAccounts.firstWhere(
        (account) => account.name.trim().toLowerCase() == 'карта',
        orElse: () => availableAccounts.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _accountId = defaultAccount.id!;
          _accountInitialized = true;
        });
      });
    }

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.type == PayoutType.advance
                  ? 'Добавить аванс'
                  : 'Добавить зарплату',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(formatDate(_date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Сумма',
              ),
              validator: (value) {
                final text = value?.trim();
                if (text == null || text.isEmpty) {
                  return 'Введите сумму';
                }
                final normalized = text.replaceAll(',', '.');
                final parsed = double.tryParse(normalized);
                if (parsed == null || parsed <= 0) {
                  return 'Введите сумму больше нуля';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (accountsAsync.isLoading && availableAccounts.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (availableAccounts.isEmpty)
              const Text(
                'Нет доступных счетов. Добавьте счёт, чтобы продолжить.',
                style: TextStyle(color: Colors.redAccent),
              )
            else
              DropdownButtonFormField<int>(
                value: _accountId,
                decoration: const InputDecoration(labelText: 'Счёт'),
                items: [
                  for (final account in availableAccounts)
                    DropdownMenuItem(
                      value: account.id!,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) {
                  if (value == null) {
                    return 'Выберите счёт';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (!mounted) {
                        return;
                      }
                      Navigator.of(context).pop(false);
                    },
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving || availableAccounts.isEmpty
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) {
                              return;
                            }
                            final accountId = _accountId;
                            if (accountId == null) {
                              return;
                            }
                            final normalized =
                                _amountController.text.trim().replaceAll(',', '.');
                            final amount = double.parse(normalized);
                            final amountMinor = (amount * 100).round();

                            setState(() => _isSaving = true);
                            try {
                              final payoutsRepo = ref.read(payoutsRepoProvider);
                              await payoutsRepo.add(
                                widget.type,
                                DateTime(_date.year, _date.month, _date.day),
                                amountMinor,
                                accountId: accountId,
                              );
                              bumpDbTick(ref);
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              setState(() => _isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Ошибка: $error')),
                              );
                              return;
                            }

                            if (!mounted) {
                              return;
                            }
                            Navigator.of(context).pop(true);
                          },
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
