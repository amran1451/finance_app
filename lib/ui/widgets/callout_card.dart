import 'package:flutter/material.dart';

class CalloutCard extends StatelessWidget {
  const CalloutCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.child,
    this.borderless = false,
    this.centered = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? child;
  final bool borderless;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    final crossAxisAlignment =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final headerContent = Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          title,
          textAlign: textAlign,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );

    final content = Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (trailing != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: headerContent),
              trailing!,
            ],
          )
        else
          headerContent,
        if (child != null) ...[
          const SizedBox(height: 16),
          child!,
        ],
      ],
    );

    final borderRadius = BorderRadius.circular(20);
    final cardColor = borderless
        ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4)
        : null;

    return Card(
      elevation: borderless ? 0 : null,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      surfaceTintColor: borderless ? Colors.transparent : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: content,
        ),
      ),
    );
  }
}
