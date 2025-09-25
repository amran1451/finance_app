import 'package:flutter/material.dart';

import '../../data/models/category.dart';

class CategoryTabs extends StatelessWidget {
  const CategoryTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final CategoryType selected;
  final ValueChanged<CategoryType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final clampedScale = mediaQuery.textScaleFactor.clamp(0.9, 1.1).toDouble();
    final textStyle =
        theme.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

    Widget buildLabel(String text) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(text, maxLines: 1),
      );
    }

    return MediaQuery(
      data: mediaQuery.copyWith(textScaleFactor: clampedScale),
      child: SegmentedButton<CategoryType>(
        segments: [
          ButtonSegment(
            value: CategoryType.income,
            label: buildLabel('Доходы'),
            icon: const Icon(Icons.trending_up),
          ),
          ButtonSegment(
            value: CategoryType.expense,
            label: buildLabel('Расходы'),
            icon: const Icon(Icons.trending_down),
          ),
          ButtonSegment(
            value: CategoryType.saving,
            label: buildLabel('Сбережения'),
            icon: const Icon(Icons.savings),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (value) {
          if (value.isEmpty) {
            return;
          }
          onChanged(value.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          textStyle: MaterialStatePropertyAll(textStyle),
        ),
      ),
    );
  }
}
