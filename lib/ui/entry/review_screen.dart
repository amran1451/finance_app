import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_models.dart' as mock;
import '../../data/models/category.dart' as db_models;
import '../../data/models/transaction_record.dart';
import '../../data/repositories/necessity_repository.dart';
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
    final necessityLabelsAsync = ref.watch(necessityLabelsProvider);
    final necessityLabels =
        necessityLabelsAsync.value ?? <NecessityLabel>[];

    if (!entryState.necessityResolved && necessityLabels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        final fallbackLabel = entryState.necessityLabel;
        if (fallbackLabel != null) {
          final match = _findLabelByName(necessityLabels, fallbackLabel);
          if (match != null) {
            controller.setNecessity(
              id: match.id,
              label: match.name,
              criticality: necessityLabels.indexOf(match),
              resolved: true,
            );
          } else {
            controller.setNecessity(
              id: null,
              label: fallbackLabel,
              criticality: entryState.necessityCriticality,
              resolved: true,
            );
          }
          return;
        }
        final first = necessityLabels.first;
        controller.setNecessity(
          id: first.id,
          label: first.name,
          criticality: 0,
          resolved: true,
        );
      });
    }

    NecessityLabel? selectedNecessityLabel;
    for (final label in necessityLabels) {
      if (label.id == entryState.necessityId) {
        selectedNecessityLabel = label;
        break;
      }
    }

    final upcomingDates = List.generate(7, (index) {
      final date = DateTime.now().add(Duration(days: index));
      return DateTime(date.year, date.month, date.day);
    });

    Future<void> saveOperation() async {
      if (!entryState.canSave || entryState.category == null) {
        return;
      }

      final categoryId =
          await _resolveCategoryId(ref, entryState.category!);
      final accountId = await _defaultAccountId(ref);
      final transactionType = _mapTransactionType(entryState.type);
      final amountMinor = (entryState.amount * 100).round();
      final note = entryState.note.trim().isEmpty
          ? null
          : entryState.note.trim();
      final fallbackNecessityLabel = entryState.necessityLabel;
      final necessityId = selectedNecessityLabel?.id;
      final necessityLabel =
          selectedNecessityLabel?.name ?? fallbackNecessityLabel;
      final necessityCriticality = selectedNecessityLabel != null
          ? necessityLabels.indexOf(selectedNecessityLabel)
          : entryState.necessityCriticality;

      final record = TransactionRecord(
        accountId: accountId,
        categoryId: categoryId,
        type: transactionType,
        amountMinor: amountMinor,
        date: entryState.selectedDate,
        note: note,
        isPlanned: false,
        includedInPeriod: true,
        criticality: necessityCriticality,
        necessityId: necessityId,
        necessityLabel: necessityLabel,
      );

      final transactionsRepository = ref.read(transactionsRepoProvider);
      await transactionsRepository.add(
        record,
        asSavingPair: entryState.type == mock.OperationType.savings,
      );

      ref.invalidate(computedBalanceProvider(accountId));
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
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
                              const SizedBox(height: 16),
                              Text(
                                'Критичность/необходимость',
                                style:
                                    Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (necessityLabelsAsync.isLoading &&
                                  necessityLabels.isEmpty)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (necessityLabels.isEmpty)
                                Text(
                                  'Нет доступных меток. Добавьте их в настройках.',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                )
                              else ...[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (var i = 0;
                                        i < necessityLabels.length;
                                        i++)
                                      ChoiceChip(
                                        label: Text(necessityLabels[i].name),
                                        selected:
                                            necessityLabels[i].id ==
                                                selectedNecessityLabel?.id,
                                        onSelected: (_) => controller
                                            .setNecessity(
                                          id: necessityLabels[i].id,
                                          label: necessityLabels[i].name,
                                          criticality: i,
                                        ),
                                      ),
                                  ],
                                ),
                                if (selectedNecessityLabel == null &&
                                    entryState.necessityLabel != null &&
                                    entryState.necessityResolved)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Метка "${entryState.necessityLabel!}" недоступна. Выберите новую.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                              ],
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
                                if (entryState.type == mock.OperationType.income) {
                                  context.pushNamed(RouteNames.plannedIncome);
                                } else if (entryState.type ==
                                    mock.OperationType.expense) {
                                  context
                                      .pushNamed(RouteNames.plannedExpense);
                                } else {
                                  context
                                      .pushNamed(RouteNames.plannedSavings);
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
              ),
            );
          },
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

NecessityLabel? _findLabelByName(
  List<NecessityLabel> labels,
  String name,
) {
  final normalized = name.trim().toLowerCase();
  for (final label in labels) {
    if (label.name.trim().toLowerCase() == normalized) {
      return label;
    }
  }
  return null;
}

Future<int> _resolveCategoryId(WidgetRef ref, mock.Category category) async {
  final repository = ref.read(categoriesRepoProvider);
  final type = _mapCategoryType(category.type);
  final existing = await repository.getByType(type);
  for (final item in existing) {
    if (item.name == category.name && item.id != null) {
      return item.id!;
    }
  }
  return repository.create(
    db_models.Category(type: type, name: category.name),
  );
}

Future<int> _defaultAccountId(WidgetRef ref) async {
  final accountsRepository = ref.read(accountsRepoProvider);
  final accounts = await accountsRepository.getAll();
  if (accounts.isEmpty) {
    throw StateError('Нет доступных счетов для сохранения операции');
  }
  final preferred = accounts.firstWhere(
    (account) =>
        account.name.trim().toLowerCase() == 'карта',
    orElse: () => accounts.first,
  );
  return preferred.id ?? accounts.first.id!;
}

TransactionType _mapTransactionType(mock.OperationType type) {
  switch (type) {
    case mock.OperationType.income:
      return TransactionType.income;
    case mock.OperationType.expense:
      return TransactionType.expense;
    case mock.OperationType.savings:
      return TransactionType.saving;
  }
}

db_models.CategoryType _mapCategoryType(mock.CategoryType type) {
  switch (type) {
    case mock.OperationType.income:
      return db_models.CategoryType.income;
    case mock.OperationType.expense:
      return db_models.CategoryType.expense;
    case mock.OperationType.savings:
      return db_models.CategoryType.saving;
  }
}
