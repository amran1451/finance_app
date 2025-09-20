import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_models.dart';
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

    final formattedAmount = entryState.amount > 0
        ? formatCurrency(entryState.amount)
        : formatCurrency(0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            controller.reset();
            context.pop();
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
            Expanded(
              child: SingleChildScrollView(
                child: AmountKeypad(
                  onDigitPressed: controller.appendDigit,
                  onBackspace: controller.backspace,
                  onDecimal: controller.appendSeparator,
                  onClear: controller.clear,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: entryState.canProceedToCategory
                  ? () => context.pushNamed(RouteNames.entryCategory)
                  : null,
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }
}
