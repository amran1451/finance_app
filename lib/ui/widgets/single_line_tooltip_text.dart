import 'package:flutter/material.dart';

class SingleLineTooltipText extends StatelessWidget {
  const SingleLineTooltipText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.textDirection,
    this.textScaler,
    this.textHeightBehavior,
    this.overflow = TextOverflow.ellipsis,
    this.tooltipEnabled = true,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final TextScaler? textScaler;
  final TextHeightBehavior? textHeightBehavior;
  final TextOverflow overflow;
  final bool tooltipEnabled;

  @override
  Widget build(BuildContext context) {
    final displayText = text;
    final textWidget = Text(
      displayText,
      maxLines: 1,
      overflow: overflow,
      softWrap: false,
      style: style,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      textHeightBehavior: textHeightBehavior,
    );

    if (!tooltipEnabled || displayText.trim().isEmpty) {
      return textWidget;
    }

    return Tooltip(
      message: displayText,
      waitDuration: const Duration(milliseconds: 400),
      child: textWidget,
    );
  }
}
