import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/app_router.dart';
import '../../state/entry_flow_providers.dart';
import '../../utils/category_type_extensions.dart';
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
              padding: const EdgeInsets.all(24),
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
                children: [
                  Text(
                    expressionDisplay,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    formattedAmount,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Тип: ${entryState.type.label}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(100),
                  child: const Text('+100'),
                ),
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(500),
                  child: const Text('+500'),
                ),
                OutlinedButton(
                  onPressed: () => controller.addQuickAmount(1000),
                  child: const Text('+1000'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (expression.isNotEmpty && previewResult != null && result == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '= ${formatCurrency(previewResult)}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
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
