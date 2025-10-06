import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/account.dart' as db;
import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';
import '../../utils/payout_rules.dart';
import '../../utils/period_utils.dart';

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
  late final DateTime _periodMinDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final (start, endEx) = ref.read(periodBoundsProvider);
    final periodInfo = ref.read(currentPeriodProvider).valueOrNull;
    final effectiveStart = DateTime(
      (periodInfo?.anchorStart ?? start).year,
      (periodInfo?.anchorStart ?? start).month,
      (periodInfo?.anchorStart ?? start).day,
    );
    _periodStart = effectiveStart;
    _periodEndExclusive = endEx;
    _periodMinDate = effectiveStart.subtract(
      const Duration(days: kEarlyPayoutGraceDays),
    );
    _type = initial?.type ?? widget.forcedType;
    final normalizedInitial = initial?.date == null
        ? null
        : DateTime(initial!.date.year, initial.date.month, initial.date.day);
    _date = normalizedInitial ?? _periodStart;
    _accountId = initial?.accountId;
    _accountInitialized = _accountId != null;
    final amountText = initial == null ? '' : _formatAmountMinor(initial.amountMinor);
    _amountController = TextEditingController(text: amountText);
  }

  PayoutType _resolveType(PayoutType allowedType) {
    final cached = _type;
    if (cached != null && cached == allowedType) {
      return cached;
    }
    final initial = widget.initial;
    if (initial != null && initial.type == allowedType) {
      _type = initial.type;
      return initial.type;
    }
    final forced = widget.forcedType;
    if (forced != null && forced == allowedType) {
      _type = forced;
      return forced;
    }
    final suggested = ref.read(payoutSuggestedTypeProvider);
    if (suggested == allowedType) {
      _type = suggested;
      return suggested;
    }
    _type = allowedType;
    return allowedType;
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
    final selectedPeriod = ref.watch(selectedPeriodRefProvider);
    final allowedType = allowedPayoutTypeForHalf(selectedPeriod.half);
    final type = _resolveType(allowedType);
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
              segments: [
                ButtonSegment(
                  value: PayoutType.advance,
                  label: Text('Аванс'),
                  enabled: allowedType == PayoutType.advance,
                ),
                ButtonSegment(
                  value: PayoutType.salary,
                  label: Text('Зарплата'),
                  enabled: allowedType == PayoutType.salary,
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
                  initialDate: _clampToPickerRange(_date),
                  firstDate: _periodMinDate,
                  lastDate: _periodEndExclusive.subtract(const Duration(days: 1)),
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
    final normalizedDate = DateTime(_date.year, _date.month, _date.day);
    final earliestAllowed = _periodMinDate;
    final lastAllowed = _periodEndExclusive.subtract(const Duration(days: 1));
    if (normalizedDate.isBefore(earliestAllowed)) {
      final allowedLabel = DateFormat('dd.MM', 'ru_RU').format(earliestAllowed);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Доступно не ранее $allowedLabel')),
      );
      return;
    }
    if (normalizedDate.isAfter(lastAllowed)) {
      final allowedLabel = DateFormat('dd.MM', 'ru_RU').format(lastAllowed);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Доступно не позднее $allowedLabel')),
      );
      return;
    }

    var shiftPeriod = false;
    final telemetry = ref.read(telemetryProvider);
    final selectedPeriod = ref.read(selectedPeriodRefProvider);
    if (normalizedDate.isBefore(_periodStart)) {
      final pickedLabel = DateFormat('dd.MM', 'ru_RU').format(normalizedDate);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Закрыть предыдущий период?'),
          content: Text(
            'Выплата пришла раньше ($pickedLabel). Сдвинуть начало текущего периода на '
            '$pickedLabel и учесть выплату здесь?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Сдвинуть'),
            ),
          ],
        ),
      );
      if (confirm != true) {
        telemetry.log('period_shift_cancelled', properties: {
          'fromStart': _periodStart.toIso8601String(),
          'payoutDate': normalizedDate.toIso8601String(),
          'periodId': selectedPeriod.id,
        });
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
        return;
      }
      shiftPeriod = true;
    }

    setState(() => _isProcessing = true);

    try {
      final payoutsRepo = ref.read(payoutsRepoProvider);
      final initial = widget.initial;
      final selected = selectedPeriod;
      final allowedType = allowedPayoutTypeForHalf(selected.half);
      final type = _resolveType(allowedType);
      final result = await payoutsRepo.upsertWithClampToSelectedPeriod(
        existing: initial,
        selectedPeriod: selected,
        pickedDate: normalizedDate,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        shiftPeriodStart: shiftPeriod,
      );
      if (shiftPeriod) {
        try {
          await _closePreviousPeriodIfNeeded(selected);
          ref.invalidate(periodToCloseProvider);
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'PayoutEditSheet',
              context: ErrorDescription(
                'while closing previous period after shifting start',
              ),
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Не удалось закрыть предыдущий период: $error'),
              ),
            );
          }
        }
      }
      final limitManager = ref.read(budgetLimitManagerProvider);
      final adjustedLimit = await limitManager.adjustDailyLimitIfNeeded(
        payout: result.payout,
        period: result.period,
      );
      await ref.read(metricsProvider.notifier).refresh();
      ref.invalidate(accountsDbProvider);
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      if (shiftPeriod) {
        telemetry.log('period_shift_applied', properties: {
          'fromStart': _periodStart.toIso8601String(),
          'toStart': normalizedDate.toIso8601String(),
          'payoutDate': normalizedDate.toIso8601String(),
          'periodId': selected.id,
        });
        final shiftLabel = DateFormat('dd.MM', 'ru_RU').format(normalizedDate);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Период сдвинут на $shiftLabel • Выплата учтена')),
        );
      } else if (adjustedLimit != null) {
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

  DateTime _clampToPickerRange(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized.isBefore(_periodMinDate)) {
      return _periodMinDate;
    }
    final last = _periodEndExclusive.subtract(const Duration(days: 1));
    if (normalized.isAfter(last)) {
      return last;
    }
    return normalized;
  }

  Future<void> _closePreviousPeriodIfNeeded(PeriodRef current) async {
    final previous = current.prevHalf();
    final status = await ref.read(periodStatusProvider(previous).future);
    if (status.closed) {
      return;
    }
    final bounds = ref.read(periodBoundsForProvider(previous));
    final today = DateUtils.dateOnly(DateTime.now());
    final normalizedEndExclusive = DateUtils.dateOnly(bounds.$2);
    if (today.isBefore(normalizedEndExclusive)) {
      return;
    }

    final read = ref.read;
    final spent = await read(spentForPeriodProvider(previous).future);
    final planned = await read(plannedIncludedAmountForPeriodProvider(previous).future);
    final payout = await read(payoutForPeriodProvider(previous).future);

    await read(periodsRepoProvider).closePeriod(
      previous,
      payoutId: payout?.id,
      dailyLimitMinor: payout?.dailyLimitMinor,
      spentMinor: spent,
      plannedIncludedMinor: planned,
      carryoverMinor: 0,
    );
  }
}
