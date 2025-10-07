import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/app_router.dart';
import '../../state/entry_flow_providers.dart';
import '../../utils/formatting.dart';
import '../widgets/amount_keypad.dart';

class AmountScreen extends ConsumerWidget {
  const AmountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);

    final previewResult = entryState.previewResult;
    final result = entryState.result;
    final amountValue = result ?? previewResult ?? 0;
    final formattedAmount = formatCurrency(amountValue);
    final expression = entryState.expression;
    final expressionDisplay = expression.isEmpty
        ? '0'
        : expression.replaceAll('*', '×').replaceAll('/', '÷');
    final hasOperators = expression.contains(RegExp(r'[+\-*/]'));
    final showResultRow = hasOperators && (previewResult != null || result != null);
    final resultDisplay = formatCurrency(result ?? previewResult ?? amountValue);
    final quickButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );

    void handleNext() {
      final success = controller.tryFinalizeExpression();
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Невалидное выражение')),
        );
        return;
      }

      final updatedState = ref.read(entryFlowControllerProvider);
      if (!updatedState.canProceedToCategory) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сумма должна быть больше 0')),
        );
        return;
      }

      context.pushNamed(RouteNames.entryCategory);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            controller.reset();
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(RouteNames.home);
            }
          },
        ),
        title: const Text('Сумма операции'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Введите сумму',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    expressionDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formattedAmount,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            if (showResultRow) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '= $resultDisplay',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(100),
                  style: quickButtonStyle,
                  child: const Text('+100'),
                ),
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(500),
                  style: quickButtonStyle,
                  child: const Text('+500'),
                ),
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(1000),
                  style: quickButtonStyle,
                  child: const Text('+1000'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: AmountKeypad(
                  onDigitPressed: controller.appendDigit,
                  onOperatorPressed: controller.appendOperator,
                  onDecimal: controller.appendDecimal,
                  onAllClear: controller.clear,
                  onBackspace: controller.backspace,
                  onEvaluate: controller.evaluateExpression,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: handleNext,
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }
}
