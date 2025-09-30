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

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _errorText = null;
      _isSaving = true;
    });

    final raw = _controller.text.trim();
    final normalized = raw
        .replaceAll(RegExp(r'[\s\u00A0]'), '')
        .replaceAll(',', '.')
        .replaceAll('₽', '');
    if (normalized.isEmpty) {
      setState(() {
        _errorText = 'Введите сумму';
        _isSaving = false;
      });
      return;
    }

    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      setState(() {
        _errorText = 'Введите число';
        _isSaving = false;
      });
      return;
    }

    var minorValue = (parsed * 100).round();
    if (minorValue <= 0) {
      setState(() {
        _errorText = 'Введите положительную сумму';
        _isSaving = false;
      });
      return;
    }

    final maxDaily = _computeMaxDailyMinor();
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

  int? _computeMaxDailyMinor() {
    final baseDays = ref.read(periodDaysFromPayoutProvider);
    if (baseDays <= 0) {
      return null;
    }
    return widget.payout.amountMinor ~/ baseDays;
  }

  @override
  Widget build(BuildContext context) {
    final baseDays = ref.watch(periodDaysFromPayoutProvider);
    final maxDaily = baseDays > 0 ? widget.payout.amountMinor ~/ baseDays : null;

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
            helperText: maxDaily != null
                ? 'Максимум на период: ${formatCurrencyMinorToRubles(maxDaily)}'
                : null,
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() {
                _errorText = null;
              });
            }
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
            });
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
