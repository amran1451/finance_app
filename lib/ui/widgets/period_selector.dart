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

    final labels = ['1–15', '15–31'];
    final segments = <ButtonSegment<String>>[];

    for (var i = 0; i < periods.length && i < labels.length; i++) {
      segments.add(
        ButtonSegment(
          value: periods[i].id,
          label: Text(labels[i]),
        ),
      );
    }

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return SegmentedButton<String>(
      segments: segments,
      selected: {activePeriod.id},
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
        controller.setActive(selection.first);
      },
    );
  }
}
