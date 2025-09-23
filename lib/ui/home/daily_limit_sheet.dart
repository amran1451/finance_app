import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';

Future<bool> showEditDailyLimitSheet(BuildContext context, WidgetRef ref) async {
  final currentValue = await ref.read(dailyLimitProvider.future);
  final controller = TextEditingController(
    text: currentValue != null ? (currentValue / 100).toStringAsFixed(2) : '',
  );
  String? errorText;
  var isSaving = false;
  var saved = false;

  try {
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
              Future<void> save() async {
                if (isSaving) {
                  return;
                }
                setState(() {
                  errorText = null;
                  isSaving = true;
                });

                final raw = controller.text.trim().replaceAll(',', '.');
                int? minorValue;
                if (raw.isEmpty) {
                  minorValue = null;
                } else {
                  final parsed = double.tryParse(raw);
                  if (parsed == null) {
                    setState(() {
                      errorText = 'Введите число';
                      isSaving = false;
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
                  if (payout != null) {
                    final period = await ref.read(currentPeriodProvider.future);
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
                        errorText = 'Лимит не может превышать $maxDaily';
                        isSaving = false;
                      });
                      return;
                    }
                  }
                }

                try {
                  final repository = ref.read(settingsRepoProvider);
                  await repository.setDailyLimitMinor(minorValue);
                  bumpDbTick(ref);
                  if (!sheetContext.mounted) {
                    return;
                  }
                  saved = true;
                  Navigator.of(sheetContext).pop();
                } catch (error) {
                  if (!sheetContext.mounted) {
                    return;
                  }
                  setState(() {
                    errorText = 'Не удалось сохранить: $error';
                    isSaving = false;
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
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Сумма',
                      prefixText: '₽ ',
                      hintText: 'Например, 1500',
                      errorText: errorText,
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () {
                                controller.clear();
                                setState(() => errorText = null);
                              },
                        child: const Text('Очистить'),
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
  } finally {
    controller.dispose();
  }

  return saved;
}
