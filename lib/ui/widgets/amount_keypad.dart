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
    final buttonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(72, 64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: theme.textTheme.titleLarge,
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

    Widget buildButton(
      Widget child,
      VoidCallback onPressed, {
      int flex = 1,
      ButtonStyle? style,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ElevatedButton(
            onPressed: onPressed,
            style: style ?? buttonStyle,
            child: child,
          ),
        ),
      );
    }

    Widget buildRow(List<Widget> children) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ...children,
          ],
        ),
      );
    }

    Widget buildSpacer({int flex = 1}) {
      return Expanded(flex: flex, child: const SizedBox.shrink());
    }

    return Column(
      children: [
        buildRow([
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
        ]),
        buildRow([
          buildButton(const Text('7'), () => onDigitPressed('7')),
          buildButton(const Text('8'), () => onDigitPressed('8')),
          buildButton(const Text('9'), () => onDigitPressed('9')),
          buildButton(
            const Text('−'),
            () => onOperatorPressed('-'),
            style: operatorStyle,
          ),
        ]),
        buildRow([
          buildButton(const Text('4'), () => onDigitPressed('4')),
          buildButton(const Text('5'), () => onDigitPressed('5')),
          buildButton(const Text('6'), () => onDigitPressed('6')),
          buildButton(
            const Text('+'),
            () => onOperatorPressed('+'),
            style: operatorStyle,
          ),
        ]),
        buildRow([
          buildButton(const Text('1'), () => onDigitPressed('1')),
          buildButton(const Text('2'), () => onDigitPressed('2')),
          buildButton(const Text('3'), () => onDigitPressed('3')),
          buildButton(
            const Text('='),
            onEvaluate,
            style: evaluateStyle,
          ),
        ]),
        buildRow([
          buildButton(
            const Text('0'),
            () => onDigitPressed('0'),
            flex: 2,
          ),
          buildButton(const Text('.'), onDecimal),
          buildSpacer(),
        ]),
      ],
    );
  }
}
