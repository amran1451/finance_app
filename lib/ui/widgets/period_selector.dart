import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/budget_providers.dart';

class PeriodSelector extends ConsumerWidget {
  final bool dense;

  const PeriodSelector({super.key, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedHalf = ref.watch(selectedHalfProvider);
    final notifier = ref.read(selectedHalfProvider.notifier);

    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    final textStyle =
        Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: dense ? 12 : null);

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
        padding: pad,
        visualDensity: VisualDensity.compact,
        textStyle: textStyle,
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
