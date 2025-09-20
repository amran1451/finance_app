import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_models.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../../utils/formatting.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final period = ref.watch(activePeriodProvider);
    final operationsRepository = ref.watch(operationsRepositoryProvider);
    final necessityLabels = ref.watch(necessityLabelsProvider);
    final selectedNecessity = entryState.necessityIndex;

    final upcomingDates = List.generate(7, (index) {
      final date = DateTime.now().add(Duration(days: index));
      return DateTime(date.year, date.month, date.day);
    });

    Future<void> saveOperation() async {
      if (!entryState.canSave || entryState.category == null) {
        return;
      }

      operationsRepository.addOperation(
        periodId: period.id,
        amount: entryState.amount,
        type: entryState.type,
        category: entryState.category!,
        date: entryState.selectedDate,
        note: entryState.note.isEmpty ? null : entryState.note,
        plannedId: entryState.attachToPlanned ? 'planned-mock' : null,
      );

      ref.invalidate(activePeriodOperationsProvider);
      ref.invalidate(periodSummaryProvider);
      controller.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
      if (kReturnToOperationsAfterSave) {
        context.goNamed(RouteNames.operations);
      } else {
        context.goNamed(RouteNames.home);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Предпросмотр'),
        actions: [
          TextButton(
            onPressed: () {
              controller.reset();
              context.goNamed(RouteNames.home);
            },
            child: const Text('Закрыть'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryRow(
                      label: 'Категория',
                      value: entryState.category?.name ?? 'Не выбрано',
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'Сумма',
                      value: formatCurrency(entryState.amount),
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'Тип операции',
                      value: entryState.type.label,
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'Период',
                      value: period.title,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Критичность/необходимость',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < necessityLabels.length; i++)
                          ChoiceChip(
                            label: Text(necessityLabels[i]),
                            selected: selectedNecessity == i,
                            onSelected: (_) => controller.setNecessityIndex(i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Дата',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final date in upcomingDates)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ChoiceChip(
                        label: Text(formatShortDate(date)),
                        selected: entryState.selectedDate == date,
                        onSelected: (_) => controller.setDate(date),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Комментарий',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: entryState.note,
              minLines: 2,
              maxLines: 3,
              onChanged: controller.setNote,
              decoration: const InputDecoration(
                hintText: 'Например: покупки к ужину',
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                title: const Text('Привязать к запланированному'),
                subtitle: Text(entryState.attachToPlanned
                    ? 'Связано (заглушка)'
                    : 'Можно будет выбрать в следующих версиях'),
                trailing: Switch(
                  value: entryState.attachToPlanned,
                  onChanged: (value) {
                    controller.setAttachToPlanned(value);
                    if (value) {
                      if (entryState.type == OperationType.income) {
                        context.pushNamed(RouteNames.plannedIncome);
                      } else if (entryState.type == OperationType.expense) {
                        context.pushNamed(RouteNames.plannedExpense);
                      } else {
                        context.pushNamed(RouteNames.plannedSavings);
                      }
                    }
                  },
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: entryState.canSave ? saveOperation : null,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
