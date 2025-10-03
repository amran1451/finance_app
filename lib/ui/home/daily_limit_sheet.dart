import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/payout.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';

Future<bool> showEditDailyLimitSheet(BuildContext context, WidgetRef ref) async {
  final payout = await ref.read(payoutForSelectedPeriodProvider.future);
  if (payout == null) {
    return false;
  }
  final currentValue = payout.dailyLimitMinor;
  final fromToday = payout.dailyLimitFromToday;
  final saved = await showModalBottomSheet<bool>(
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
        child: _DailyLimitSheet(
          payout: payout,
          initialMinorValue: currentValue > 0 ? currentValue : null,
          initialFromToday: fromToday,
        ),
      );
    },
  );

  return saved ?? false;
}

class _DailyLimitSheet extends ConsumerStatefulWidget {
  const _DailyLimitSheet({
    required this.payout,
    required this.initialMinorValue,
    required this.initialFromToday,
  });

  final Payout payout;
  final int? initialMinorValue;
  final bool initialFromToday;

  @override
  ConsumerState<_DailyLimitSheet> createState() => _DailyLimitSheetState();
}

class _DailyLimitSheetState extends ConsumerState<_DailyLimitSheet> {
  late final TextEditingController _controller;
  String? _errorText;
  var _isSaving = false;
  late bool _fromToday;
  String? _maxHint;
  int? _lastMaxDailyValue;

  @override
  void initState() {
    super.initState();
    final value = widget.initialMinorValue;
    _controller = TextEditingController(
      text: value != null ? formatCurrencyMinorPlain(value) : '',
    );
    _fromToday = widget.initialFromToday;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _parseMinor(String rawValue) {
    final normalized = rawValue
        .replaceAll(RegExp(r'[\s\u00A0]'), '')
        .replaceAll(',', '.')
        .replaceAll('₽', '');
    if (normalized.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      return -1;
    }
    return (parsed * 100).round();
  }

  int? get _currentMaxDailyMinor {
    final periodInfo = ref.read(currentPeriodProvider).valueOrNull;
    if (periodInfo == null) {
      return null;
    }
    final periodRef = ref.read(selectedPeriodRefProvider);
    final remainingAsync = ref.read(remainingBudgetForPeriodProvider(periodRef));
    final remainingBudget = remainingAsync.valueOrNull;
    if (remainingBudget == null) {
      return null;
    }
    if (remainingBudget <= 0) {
      return 0;
    }
    final today = ref.read(todayDateProvider);
    return calculateMaxDailyLimitMinor(
      remainingBudgetMinor: remainingBudget,
      periodStart: periodInfo.start,
      periodEndExclusive: periodInfo.end,
      today: today,
      payoutDate: widget.payout.date,
      fromToday: _fromToday,
    );
  }

  void _enforceMaxIfNeeded({bool showHint = false}) {
    final maxDaily = _currentMaxDailyMinor;
    if (maxDaily == null) {
      return;
    }
    final minorValue = _parseMinor(_controller.text.trim());
    if (minorValue == null) {
      if (_maxHint != null && !showHint) {
        setState(() {
          _maxHint = null;
        });
      }
      return;
    }
    if (minorValue < 0) {
      return;
    }
    if (minorValue > maxDaily) {
      final replacementText = formatCurrencyMinorPlain(maxDaily);
      _controller.value = TextEditingValue(
        text: replacementText,
        selection: TextSelection.collapsed(offset: replacementText.length),
      );
      setState(() {
        _maxHint = 'Максимум: ${formatCurrencyMinorToRubles(maxDaily)}';
      });
    } else if (showHint && maxDaily >= 0) {
      setState(() {
        _maxHint = 'Максимум: ${formatCurrencyMinorToRubles(maxDaily)}';
      });
    } else if (_maxHint != null) {
      setState(() {
        _maxHint = null;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _errorText = null;
      _isSaving = true;
    });

    final raw = _controller.text.trim();
    final parsedMinor = _parseMinor(raw);
    if (parsedMinor == null) {
      setState(() {
        _errorText = 'Введите сумму';
        _isSaving = false;
      });
      return;
    }
    if (parsedMinor < 0) {
      setState(() {
        _errorText = 'Введите число';
        _isSaving = false;
      });
      return;
    }

    var minorValue = parsedMinor;
    if (minorValue <= 0) {
      setState(() {
        _errorText = 'Введите положительную сумму';
        _isSaving = false;
      });
      return;
    }

    final maxDaily = _currentMaxDailyMinor;
    if (maxDaily != null && minorValue > maxDaily) {
      final messenger = ScaffoldMessenger.of(context);
      final replacementText = formatCurrencyMinorPlain(maxDaily);
      _controller.value = TextEditingValue(
        text: replacementText,
        selection: TextSelection.collapsed(offset: replacementText.length),
      );
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Максимум для этого периода — ${formatCurrencyMinorToRubles(maxDaily)}',
            ),
          ),
        );
      minorValue = maxDaily;
      setState(() {
        _maxHint = 'Максимум: ${formatCurrencyMinorToRubles(maxDaily)}';
      });
    }

    try {
      final payout = widget.payout;
      final payoutId = payout.id;
      if (payoutId == null) {
        throw StateError('Не найдена текущая выплата');
      }
      await ref.read(payoutsRepoProvider).setDailyLimit(
            payoutId: payoutId,
            dailyLimitMinor: minorValue,
            fromToday: _fromToday,
          );
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Не удалось сохранить: $error';
        _isSaving = false;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodInfo = ref.watch(currentPeriodProvider).valueOrNull;
    final periodRef = ref.watch(selectedPeriodRefProvider);
    final remainingAsync = ref.watch(remainingBudgetForPeriodProvider(periodRef));
    final today = ref.watch(todayDateProvider);
    final maxDaily = periodInfo != null && remainingAsync.hasValue
        ? calculateMaxDailyLimitMinor(
            remainingBudgetMinor: remainingAsync.value!,
            periodStart: periodInfo.start,
            periodEndExclusive: periodInfo.end,
            today: today,
            payoutDate: widget.payout.date,
            fromToday: _fromToday,
          )
        : null;

    if (maxDaily != _lastMaxDailyValue) {
      _lastMaxDailyValue = maxDaily;
      if (maxDaily != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _enforceMaxIfNeeded();
        });
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Лимит на день',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: 'Сумма',
            prefixText: '₽ ',
            hintText: 'Например, 1500',
            errorText: _errorText,
            helperText: _maxHint,
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() {
                _errorText = null;
              });
            }
            _enforceMaxIfNeeded();
          },
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Пересчитывать от сегодня'),
          subtitle: const Text(
            'Если включено, бюджет периода = лимит × оставшиеся дни от сегодня',
          ),
          value: _fromToday,
          onChanged: (value) {
            setState(() {
              _fromToday = value ?? false;
              _maxHint = null;
              _lastMaxDailyValue = null;
            });
            _enforceMaxIfNeeded(showHint: true);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      _controller.clear();
                      setState(() => _errorText = null);
                    },
              child: const Text('Очистить'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
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
  }
}
