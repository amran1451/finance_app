import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/mock_models.dart';
import '../../state/app_providers.dart';
import '../../utils/formatting.dart';

class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final operations = ref.watch(activePeriodOperationsProvider);

    final grouped = <DateTime, List<Operation>>{};
    for (final operation in operations) {
      final date = DateTime(operation.date.year, operation.date.month, operation.date.day);
      grouped.putIfAbsent(date, () => []).add(operation);
    }
    final dates = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Операции периода'),
      ),
      body: operations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.receipt_long, size: 64),
                    SizedBox(height: 16),
                    Text('Пока нет операций. Нажмите “+”, чтобы добавить первую!'),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: dates.length,
              itemBuilder: (context, index) {
                final date = dates[index];
                final items = grouped[date]!;
                return _OperationsSection(
                  title: formatDate(date),
                  operations: items,
                  periodId: period.id,
                );
              },
            ),
    );
  }
}

class _OperationsSection extends ConsumerWidget {
  const _OperationsSection({
    required this.title,
    required this.operations,
    required this.periodId,
  });

  final String title;
  final List<Operation> operations;
  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(operationsRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...operations.map(
          (operation) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: operation.type.color.withOpacity(0.15),
                child: Icon(
                  operation.category.icon,
                  color: operation.type.color,
                ),
              ),
              title: Text(operation.category.name),
              subtitle: Text(operation.note ?? 'Без комментария'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(operation.amount),
                    style: TextStyle(
                      color: operation.type == OperationType.expense
                          ? Colors.redAccent
                          : operation.type == OperationType.income
                              ? Colors.green
                              : Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(operation.type.label),
                ],
              ),
              onLongPress: () async {
                final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить операцию?'),
                        content: const Text('Это действие нельзя отменить.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (confirm) {
                  repository.removeOperation(periodId, operation.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Операция удалена')),
                  );
                  ref.invalidate(activePeriodOperationsProvider);
                  ref.invalidate(periodSummaryProvider);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
