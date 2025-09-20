import 'package:flutter/material.dart';

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.label,
  });

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: value.clamp(0.0, 1.0),
            semanticsLabel: label,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
