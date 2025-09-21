import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/budget_providers.dart';

class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedHalf = ref.watch(selectedHalfProvider);
    final notifier = ref.read(selectedHalfProvider.notifier);

    return SegmentedButton<HalfPeriod>(
      segments: const [
        ButtonSegment(
          value: HalfPeriod.first,
          label: Text('1–15'),
        ),
        ButtonSegment(
          value: HalfPeriod.second,
          label: Text('15–31'),
        ),
      ],
      selected: {selectedHalf},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.bodyMedium,
      ),
      onSelectionChanged: (selection) {
        if (selection.isEmpty) {
          return;
        }
        notifier.state = selection.first;
      },
    );
  }
}
