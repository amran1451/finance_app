import 'package:flutter/material.dart';

class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onOperatorPressed,
    required this.onBackspace,
    required this.onDecimal,
    required this.onAllClear,
    required this.onEvaluate,
  });

  final ValueChanged<String> onDigitPressed;
  final ValueChanged<String> onOperatorPressed;
  final VoidCallback onBackspace;
  final VoidCallback onDecimal;
  final VoidCallback onAllClear;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final clampedTextScale =
            mediaQuery.textScaleFactor.clamp(0.9, 1.1).toDouble();
        final mediaQueryData = mediaQuery.copyWith(
          textScaleFactor: clampedTextScale,
        );

        const baseWidth = 400.0;
        final maxWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : baseWidth;
        final normalized = maxWidth / baseWidth;
        final scale = normalized.clamp(0.88, 0.92);

        final buttonStyle = ElevatedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: theme.textTheme.titleMedium,
        );

        final secondaryStyle = buttonStyle.copyWith(
          backgroundColor: MaterialStatePropertyAll(
            theme.colorScheme.surfaceVariant,
          ),
          foregroundColor: MaterialStatePropertyAll(
            theme.colorScheme.onSurfaceVariant,
          ),
        );

        final operatorStyle = buttonStyle.copyWith(
          backgroundColor: MaterialStatePropertyAll(
            theme.colorScheme.secondaryContainer,
          ),
          foregroundColor: MaterialStatePropertyAll(
            theme.colorScheme.onSecondaryContainer,
          ),
        );

        final evaluateStyle = buttonStyle.copyWith(
          backgroundColor: MaterialStatePropertyAll(theme.colorScheme.primary),
          foregroundColor: MaterialStatePropertyAll(theme.colorScheme.onPrimary),
        );

        Widget buildButton(Widget child, VoidCallback onPressed,
            {ButtonStyle? style}) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox.expand(
              child: ElevatedButton(
                onPressed: onPressed,
                style: style ?? buttonStyle,
                child: child,
              ),
            ),
          );
        }

        Widget buildSpacer() {
          return const SizedBox.shrink();
        }

        final children = <Widget>[
          buildButton(
            const Text('AC'),
            onAllClear,
            style: secondaryStyle,
          ),
          buildButton(
            const Icon(Icons.backspace_outlined),
            onBackspace,
            style: secondaryStyle,
          ),
          buildButton(
            const Text('÷'),
            () => onOperatorPressed('/'),
            style: operatorStyle,
          ),
          buildButton(
            const Text('×'),
            () => onOperatorPressed('*'),
            style: operatorStyle,
          ),
          buildButton(const Text('7'), () => onDigitPressed('7')),
          buildButton(const Text('8'), () => onDigitPressed('8')),
          buildButton(const Text('9'), () => onDigitPressed('9')),
          buildButton(
            const Text('−'),
            () => onOperatorPressed('-'),
            style: operatorStyle,
          ),
          buildButton(const Text('4'), () => onDigitPressed('4')),
          buildButton(const Text('5'), () => onDigitPressed('5')),
          buildButton(const Text('6'), () => onDigitPressed('6')),
          buildButton(
            const Text('+'),
            () => onOperatorPressed('+'),
            style: operatorStyle,
          ),
          buildButton(const Text('1'), () => onDigitPressed('1')),
          buildButton(const Text('2'), () => onDigitPressed('2')),
          buildButton(const Text('3'), () => onDigitPressed('3')),
          buildButton(
            const Text('='),
            onEvaluate,
            style: evaluateStyle,
          ),
          buildButton(const Text('0'), () => onDigitPressed('0')),
          buildButton(const Text('.'), onDecimal),
          buildSpacer(),
          buildSpacer(),
        ];

        final grid = MediaQuery(
          data: mediaQueryData,
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.15,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: children,
          ),
        );

        return Align(
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: grid,
          ),
        );
      },
    );
  }
}
