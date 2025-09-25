import 'package:flutter/material.dart';

import '../../data/repositories/necessity_repository.dart'
    as necessity_repo;
import '../../utils/color_hex.dart';

class NecessityChoiceChip extends StatelessWidget {
  const NecessityChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final necessity_repo.NecessityLabel label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hexToColor(label.color);
    final selectedColor = color ?? theme.colorScheme.secondaryContainer;
    final backgroundColor =
        color != null ? color.withOpacity(0.16) : theme.colorScheme.surfaceVariant;
    final borderColor = (color ?? theme.colorScheme.outline).withOpacity(0.6);
    final onSelectedColor =
        ThemeData.estimateBrightnessForColor(selectedColor) == Brightness.dark
            ? Colors.white
            : Colors.black;

    return ChoiceChip(
      label: Text(
        label.name,
        style: TextStyle(
          color: selected ? onSelectedColor : theme.colorScheme.onSurface,
        ),
      ),
      selected: selected,
      selectedColor: selectedColor,
      backgroundColor: backgroundColor,
      checkmarkColor: onSelectedColor,
      side: BorderSide(color: borderColor),
      onSelected: onSelected,
    );
  }
}
