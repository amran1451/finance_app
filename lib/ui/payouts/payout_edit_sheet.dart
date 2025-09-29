import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart' as db;
import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';

Future<void> showPayoutEditSheet(
  BuildContext context, {
  PayoutType? forcedType,
  Payout? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PayoutEditSheet(
      initial: initial,
      forcedType: forcedType,
    ),
  );
}

Future<void> showPayoutForSelectedPeriod(
  BuildContext context, {
  PayoutType? forcedType,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final read = container.read;
  final (start, endEx) = read(periodBoundsProvider);
  final existing = await read(payoutsRepoProvider).findInRange(start, endEx);
  await showPayoutEditSheet(
    context,
    forcedType: forcedType,
    initial: existing,
  );
}

class _PayoutEditSheet extends ConsumerStatefulWidget {
  const _PayoutEditSheet({
    this.initial,
    this.forcedType,
    super.key,
  });

  final Payout? initial;
  final PayoutType? forcedType;

  @override
  ConsumerState<_PayoutEditSheet> createState() => _PayoutEditSheetState();
}

class _PayoutEditSheetState extends ConsumerState<_PayoutEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  PayoutType? _type;
  late DateTime _date;
  int? _accountId;
  bool _accountInitialized = false;
  bool _isProcessing = false;
  late final DateTime _periodStart;
  late final DateTime _periodEndExclusive;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final (start, endEx) = ref.read(periodBoundsProvider);
    _periodStart = start;
    _periodEndExclusive = endEx;
    _type = initial?.type ?? widget.forcedType;
    _date = initial?.date ?? _periodStart;
    _accountId = initial?.accountId;
    _accountInitialized = _accountId != null;
    final amountText = initial == null ? '' : _formatAmountMinor(initial.amountMinor);
    _amountController = TextEditingController(text: amountText);
  }

  PayoutType _resolveType() {
    final cached = _type;
    if (cached != null) {
      return cached;
    }
    final initial = widget.initial;
    if (initial != null) {
      final value = initial.type;
      _type = value;
      return value;
    }
    final forced = widget.forcedType;
    if (forced != null) {
      _type = forced;
      return forced;
    }
    final suggested = ref.read(payoutSuggestedTypeProvider);
    _type = suggested;
    return suggested;
  }

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
        .where((account) {
          final id = account.id;
          if (id == null) {
            return false;
          }
          if (account.isArchived && id != _accountId) {
            return false;
          }
          return true;
        })
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
          _accountId = defaultAccount.id;
          _accountInitialized = true;
        });
      });
    }

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditMode = widget.initial?.id != null;
    final type = _resolveType();
    final titlePrefix = isEditMode ? 'Редактировать выплату' : 'Добавить выплату';
    final title = '$titlePrefix (${payoutTypeLabel(type)})';

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
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SegmentedButton<PayoutType>(
              segments: const [
                ButtonSegment(
                  value: PayoutType.advance,
                  label: Text('Аванс'),
                ),
                ButtonSegment(
                  value: PayoutType.salary,
                  label: Text('Зарплата'),
                ),
              ],
              selected: <PayoutType>{type},
              onSelectionChanged: widget.forcedType != null
                  ? null
                  : (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      setState(() => _type = selection.first);
                    },
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
                  initialDate: _clampToPeriod(_date),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _date = DateTime(picked.year, picked.month, picked.day);
                  });
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
                  child: isEditMode
                      ? TextButton(
                          onPressed:
                              _isProcessing ? null : () => _deletePayout(context),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          child: const Text('Удалить'),
                        )
                      : OutlinedButton(
                          onPressed: _isProcessing
                              ? null
                              : () {
                                  if (!mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                },
                          child: const Text('Отмена'),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isProcessing || availableAccounts.isEmpty
                        ? null
                        : () => _savePayout(context),
                    child: _isProcessing
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
            if (isEditMode) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isProcessing
                    ? null
                    : () {
                        if (!mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                child: const Text('Отмена'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _savePayout(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      return;
    }
    final text = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.parse(text);
    final amountMinor = (amount * 100).round();
    setState(() => _isProcessing = true);

    try {
      final payoutsRepo = ref.read(payoutsRepoProvider);
      final normalizedDate = DateTime(_date.year, _date.month, _date.day);
      final initial = widget.initial;
      final type = _resolveType();
      final selected = ref.read(selectedPeriodRefProvider);
      final result = await payoutsRepo.upsertWithClampToSelectedPeriod(
        existing: initial,
        selectedPeriod: selected,
        pickedDate: normalizedDate,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
      );
      final limitManager = ref.read(budgetLimitManagerProvider);
      final adjustedLimit = await limitManager.adjustDailyLimitIfNeeded(
        payout: result.payout,
        period: result.period,
      );
      ref.read(selectedPeriodRefProvider.notifier).state = result.period;
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      if (adjustedLimit != null) {
        final formatted = formatCurrencyMinorToRubles(adjustedLimit);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Лимит скорректирован до $formatted')),
        );
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    }
  }

  Future<void> _deletePayout(BuildContext context) async {
    final id = widget.initial?.id;
    if (id == null) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final payoutsRepo = ref.read(payoutsRepoProvider);
      await payoutsRepo.delete(id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    }
  }

  String _formatAmountMinor(int amountMinor) {
    final major = amountMinor / 100;
    final formatted = major.toStringAsFixed(2);
    if (formatted.endsWith('.00')) {
      return formatted.substring(0, formatted.length - 3);
    }
    if (formatted.endsWith('0')) {
      return formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  DateTime _clampToPeriod(DateTime date) {
    if (date.isBefore(_periodStart)) {
      return _periodStart;
    }
    final last = _periodEndExclusive.subtract(const Duration(days: 1));
    if (date.isAfter(last)) {
      return last;
    }
    return date;
  }
}
