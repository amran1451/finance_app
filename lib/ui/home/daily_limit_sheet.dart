import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';

Future<bool> showEditDailyLimitSheet(BuildContext context, WidgetRef ref) async {
  final currentValue = await ref.read(dailyLimitProvider.future);
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
          initialMinorValue: currentValue,
        ),
      );
    },
  );

  return saved ?? false;
}

class _DailyLimitSheet extends ConsumerStatefulWidget {
  const _DailyLimitSheet({required this.initialMinorValue});

  final int? initialMinorValue;

  @override
  ConsumerState<_DailyLimitSheet> createState() => _DailyLimitSheetState();
}

class _DailyLimitSheetState extends ConsumerState<_DailyLimitSheet> {
  late final TextEditingController _controller;
  String? _errorText;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.initialMinorValue;
    _controller = TextEditingController(
      text: value != null ? (value / 100).toStringAsFixed(2) : '',
    );
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

    final raw = _controller.text.trim().replaceAll(',', '.');
    int? minorValue;
    if (raw.isEmpty) {
      minorValue = null;
    } else {
      final parsed = double.tryParse(raw);
      if (parsed == null) {
        setState(() {
          _errorText = 'Введите число';
          _isSaving = false;
        });
        return;
      }
      minorValue = (parsed * 100).round();
      if (minorValue < 0) {
        minorValue = 0;
      }
    }

    if (minorValue != null) {
      final payout = await ref.read(currentPayoutProvider.future);
      if (!mounted) {
        return;
      }
      if (payout != null) {
        final period = await ref.read(currentPeriodProvider.future);
        if (!mounted) {
          return;
        }
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        var remainingDays = period.end.difference(todayStart).inDays;
        if (remainingDays <= 0) {
          remainingDays = 1;
        } else if (remainingDays > period.days) {
          remainingDays = period.days;
        }
        if (remainingDays <= 0) {
          remainingDays = 1;
        }
        final maxDaily = payout.amountMinor ~/ remainingDays;
        if (minorValue > maxDaily) {
          setState(() {
            _errorText = 'Лимит не может превышать $maxDaily';
            _isSaving = false;
          });
          return;
        }
      }
    }

    try {
      final repository = ref.read(settingsRepoProvider);
      await repository.setDailyLimitMinor(minorValue);
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Сумма',
            prefixText: '₽ ',
            hintText: 'Например, 1500',
            errorText: _errorText,
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
