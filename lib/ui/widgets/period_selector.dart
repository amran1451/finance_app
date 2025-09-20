import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';

class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(periodsProvider);
    final activePeriod = ref.watch(activePeriodProvider);
    final controller = ref.read(activePeriodProvider.notifier);

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: activePeriod.id,
            borderRadius: BorderRadius.circular(16),
            decoration: const InputDecoration(
              labelText: 'Период бюджета',
            ),
            items: [
              for (final period in periods)
                DropdownMenuItem(
                  value: period.id,
                  child: Text(period.title),
                ),
              const DropdownMenuItem(
                value: 'custom',
                child: Text('Пользовательский'),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              if (value == 'custom') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('TODO: Добавить выбор пользовательского периода'),
                  ),
                );
              } else {
                controller.setActive(value);
              }
            },
          ),
        ),
      ],
    );
  }
}
