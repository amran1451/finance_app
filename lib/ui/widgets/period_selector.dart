import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/budget_providers.dart';

class PeriodSelector extends ConsumerWidget {
  final bool dense;
  final String? label;

  const PeriodSelector({super.key, this.dense = false, this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(periodNavProvider);
    final String displayLabel = label ?? ref.watch(periodLabelProvider);
    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    final iconPadding = dense ? const EdgeInsets.all(4) : const EdgeInsets.all(8);
    final iconConstraints = dense
        ? const BoxConstraints(minWidth: 40, minHeight: 40)
        : const BoxConstraints(minWidth: 48, minHeight: 48);
    final iconDensity = dense ? VisualDensity.compact : VisualDensity.standard;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: nav.prev,
          tooltip: 'Предыдущий период',
          padding: iconPadding,
          constraints: iconConstraints,
          visualDensity: iconDensity,
        ),
        Expanded(
          child: Center(
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: Text(
                displayLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: nav.next,
          tooltip: 'Следующий период',
          padding: iconPadding,
          constraints: iconConstraints,
          visualDensity: iconDensity,
        ),
      ],
    );
  }
}
