import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/budget_providers.dart';
import '../../utils/period_utils.dart';

class PeriodSelector extends ConsumerWidget {
  final bool dense;
  final String? label;

  const PeriodSelector({super.key, this.dense = false, this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(periodNavProvider);
    final String displayLabel = label ?? _formatSelectedPeriodLabel(ref);
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0.12, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: Text(
                  displayLabel,
                  key: ValueKey(displayLabel),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.my_location),
          onPressed: nav.goToToday,
          tooltip: 'Вернуться к текущему периоду',
          padding: iconPadding,
          constraints: iconConstraints,
          visualDensity: iconDensity,
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

String _formatSelectedPeriodLabel(WidgetRef ref) {
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final period = ref.watch(selectedPeriodRefProvider);
  final range = _selectedPeriodRange(period, anchor1, anchor2);
  return _formatRangeLabel(range.start, range.endInclusive);
}

({DateTime start, DateTime endInclusive}) _selectedPeriodRange(
  PeriodRef period,
  int anchor1,
  int anchor2,
) {
  final isAscending = anchor1 <= anchor2;
  late DateTime start;
  late DateTime endExclusive;

  if (period.half == HalfPeriod.first) {
    start = DateTime(period.year, period.month, anchor1);
    endExclusive = isAscending
        ? DateTime(period.year, period.month, anchor2)
        : DateTime(period.year, period.month + 1, anchor2);
  } else {
    start = DateTime(period.year, period.month, anchor2);
    endExclusive = isAscending
        ? DateTime(period.year, period.month + 1, anchor1)
        : DateTime(period.year, period.month, anchor1);
  }

  if (!endExclusive.isAfter(start)) {
    endExclusive = start.add(const Duration(days: 1));
  }

  return (
    start: start,
    endInclusive: endExclusive.subtract(const Duration(days: 1)),
  );
}

String _formatRangeLabel(DateTime start, DateTime endInclusive) {
  final startMonth = _ruMonthShort(start.month);
  final endMonth = _ruMonthShort(endInclusive.month);
  final sameMonth = start.year == endInclusive.year && start.month == endInclusive.month;

  if (sameMonth) {
    return '$startMonth ${start.day}–${endInclusive.day}';
  }

  return '$startMonth ${start.day} – $endMonth ${endInclusive.day}';
}

String _ruMonthShort(int month) {
  const months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  final index = (month - 1).clamp(0, months.length - 1);
  return months[index];
}
