import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../state/app_providers.dart';
import '../../data/repositories/necessity_repository.dart'
    as necessity_repo;
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';

enum OperationsFilter { all, income, expense, saving }

final _operationsFilterProvider =
    StateProvider<OperationsFilter>((_) => OperationsFilter.all);

final _categoriesMapProvider = FutureProvider<Map<int, Category>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepoProvider);
  final categories = await repository.getAll();
  return {
    for (final category in categories)
      if (category.id != null) category.id!: category,
  };
});

class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(halfPeriodTransactionsProvider);
    final periodBounds = ref.watch(halfPeriodBoundsProvider);
    final periodStart = periodBounds.start;
    final periodEndExclusive = periodBounds.endExclusive;
    final categoriesAsync = ref.watch(_categoriesMapProvider);
    final filter = ref.watch(_operationsFilterProvider);

    final rawEnd = periodEndExclusive.subtract(const Duration(days: 1));
    final endInclusive =
        rawEnd.isBefore(periodStart) ? periodStart : rawEnd;
    final boundsLabel =
        '${formatDayMonth(periodStart)} – ${formatDayMonth(endInclusive)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Операции периода'),
      ),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить операции: $error'),
          ),
        ),
        data: (transactions) {
          final categories = categoriesAsync.asData?.value ?? const <int, Category>{};
          final filtered = _applyFilter(transactions, filter);
          if (filtered.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      filter == OperationsFilter.all
                          ? 'Операций пока нет'
                          : 'Нет операций выбранного типа',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final grouped = _groupByDate(filtered);
          final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(boundsLabel, style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<OperationsFilter>(
                  segments: const [
                    ButtonSegment(
                      value: OperationsFilter.all,
                      label: Text('Все'),
                    ),
                    ButtonSegment(
                      value: OperationsFilter.expense,
                      label: Text('Расходы'),
                    ),
                    ButtonSegment(
                      value: OperationsFilter.income,
                      label: Text('Доходы'),
                    ),
                    ButtonSegment(
                      value: OperationsFilter.saving,
                      label: Text('Сбережения'),
                    ),
                  ],
                  selected: {filter},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    ref.read(_operationsFilterProvider.notifier).state = selection.first;
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: dates.length,
                  itemBuilder: (context, index) {
                    final date = dates[index];
                    final items = grouped[date]!;
                    return _OperationsSection(
                      title: formatDate(date),
                      transactions: items,
                      categories: categories,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OperationsSection extends ConsumerWidget {
  const _OperationsSection({
    required this.title,
    required this.transactions,
    required this.categories,
  });

  final String title;
  final List<TransactionRecord> transactions;
  final Map<int, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(transactionsRepoProvider);
    final necessityMapAsync = ref.watch(necessityMapProvider);
    final necessityMap = necessityMapAsync.value ?? const <int, necessity_repo.NecessityLabel>{};

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
        ...transactions.map(
          (record) {
            final category = categories[record.categoryId];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _colorForType(record.type).withOpacity(0.15),
                  child: Icon(
                    _iconForType(record.type),
                    color: _colorForType(record.type),
                  ),
                ),
                title: Text(category?.name ?? 'Категория #${record.categoryId}'),
                subtitle: Text(record.note?.isNotEmpty == true
                    ? record.note!
                    : record.necessityLabel ??
                        necessityMap[record.necessityId]?.name ??
                            'Без комментария'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrencyMinor(record.amountMinor),
                      style: TextStyle(
                        color: _colorForType(record.type),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(_labelForType(record.type)),
                  ],
                ),
                onLongPress: () async {
                  final id = record.id;
                  if (id == null) {
                    return;
                  }
                  final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Удалить операцию?'),
                          content: const Text(
                            'Это действие нельзя отменить. Итоги будут пересчитаны.',
                          ),
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
                  if (!confirm) {
                    return;
                  }
                  await repository.delete(id);
                  bumpDbTick(ref);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Операция удалена')),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

Map<DateTime, List<TransactionRecord>> _groupByDate(
  List<TransactionRecord> transactions,
) {
  final grouped = <DateTime, List<TransactionRecord>>{};
  for (final record in transactions) {
    final date = DateTime(record.date.year, record.date.month, record.date.day);
    grouped.putIfAbsent(date, () => []).add(record);
  }
  return grouped;
}

List<TransactionRecord> _applyFilter(
  List<TransactionRecord> source,
  OperationsFilter filter,
) {
  switch (filter) {
    case OperationsFilter.all:
      return source;
    case OperationsFilter.income:
      return source
          .where((record) => record.type == TransactionType.income)
          .toList();
    case OperationsFilter.expense:
      return source
          .where((record) => record.type == TransactionType.expense)
          .toList();
    case OperationsFilter.saving:
      return source
          .where((record) => record.type == TransactionType.saving)
          .toList();
  }
}

Color _colorForType(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return Colors.green;
    case TransactionType.expense:
      return Colors.redAccent;
    case TransactionType.saving:
      return Colors.blueAccent;
  }
}

IconData _iconForType(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return Icons.trending_up;
    case TransactionType.expense:
      return Icons.trending_down;
    case TransactionType.saving:
      return Icons.savings;
  }
}

String _labelForType(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return 'Доход';
    case TransactionType.expense:
      return 'Расход';
    case TransactionType.saving:
      return 'Сбережение';
  }
}
