import 'package:flutter/material.dart';

class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onBackspace,
    required this.onDecimal,
    required this.onClear,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onBackspace;
  final VoidCallback onDecimal;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      minimumSize: const Size(72, 64),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );

    Widget buildButton(String label, VoidCallback onPressed) {
      return ElevatedButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: Text(
          label,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );
    }

    return Column(
      children: [
        for (final row in _buttonRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((button) {
                switch (button) {
                  case _KeypadButton.digit1:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('1', () => onDigitPressed('1')),
                      ),
                    );
                  case _KeypadButton.digit2:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('2', () => onDigitPressed('2')),
                      ),
                    );
                  case _KeypadButton.digit3:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('3', () => onDigitPressed('3')),
                      ),
                    );
                  case _KeypadButton.digit4:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('4', () => onDigitPressed('4')),
                      ),
                    );
                  case _KeypadButton.digit5:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('5', () => onDigitPressed('5')),
                      ),
                    );
                  case _KeypadButton.digit6:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('6', () => onDigitPressed('6')),
                      ),
                    );
                  case _KeypadButton.digit7:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('7', () => onDigitPressed('7')),
                      ),
                    );
                  case _KeypadButton.digit8:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('8', () => onDigitPressed('8')),
                      ),
                    );
                  case _KeypadButton.digit9:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('9', () => onDigitPressed('9')),
                      ),
                    );
                  case _KeypadButton.decimal:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton(',', onDecimal),
                      ),
                    );
                  case _KeypadButton.digit0:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('0', () => onDigitPressed('0')),
                      ),
                    );
                  case _KeypadButton.backspace:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton(
                          onPressed: onBackspace,
                          style: buttonStyle,
                          child: const Icon(Icons.backspace_outlined),
                        ),
                      ),
                    );
                  case _KeypadButton.clear:
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: buildButton('Сброс', onClear),
                      ),
                    );
                }
              }).toList(),
            ),
          ),
      ],
    );
  }
}

enum _KeypadButton {
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
  decimal,
  digit0,
  backspace,
  clear,
}

const List<List<_KeypadButton>> _buttonRows = [
  [_KeypadButton.digit1, _KeypadButton.digit2, _KeypadButton.digit3],
  [_KeypadButton.digit4, _KeypadButton.digit5, _KeypadButton.digit6],
  [_KeypadButton.digit7, _KeypadButton.digit8, _KeypadButton.digit9],
  [_KeypadButton.decimal, _KeypadButton.digit0, _KeypadButton.backspace],
  [_KeypadButton.clear],
];
