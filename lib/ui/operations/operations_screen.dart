import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../state/app_providers.dart';
import '../../data/repositories/necessity_repository.dart'
    as necessity_repo;
import '../../data/repositories/reason_repository.dart' as reason_repo;
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/operations_filters.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/reason_providers.dart';
import '../../utils/formatting.dart';
import '../../utils/period_utils.dart';
import '../../routing/app_router.dart';
import '../../data/repositories/transactions_repository.dart'
    show TransactionListItem;
import '../widgets/single_line_tooltip_text.dart';

final _categoriesMapProvider = FutureProvider<Map<int, Category>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
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
    final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
    final transactionsAsync = ref.watch(
      periodOperationsProvider((start: periodStart, endExclusive: periodEndExclusive)),
    );
    final categoriesAsync = ref.watch(_categoriesMapProvider);
    final filter = ref.watch(opTypeFilterProvider);

    final rawEnd = periodEndExclusive.subtract(const Duration(days: 1));
    final endInclusive =
        rawEnd.isBefore(periodStart) ? periodStart : rawEnd;
    final boundsLabel =
        '${formatDayMonth(periodStart)} – ${formatDayMonth(endInclusive)}';

    final mediaQuery = MediaQuery.of(context);
    final clampedTextScale =
        mediaQuery.textScaleFactor.clamp(0.9, 1.1).toDouble();
    final filterTextStyle =
        Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14);

    final navigator = Navigator.of(context);

    return PopScope(
      canPop: navigator.canPop(),
      onPopInvoked: (didPop) {
        if (didPop) {
          return;
        }

        context.goNamed(RouteNames.home);
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Операции периода'),
        leading: IconButton(
          icon: Icon(
            navigator.canPop() ? Icons.arrow_back : Icons.close,
          ),
          onPressed: () {
            if (navigator.canPop()) {
              context.pop();
            } else {
              context.goNamed(RouteNames.home);
            }
          },
          tooltip: navigator.canPop() ? 'Назад' : 'Закрыть',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              context.goNamed(RouteNames.home);
            },
            tooltip: 'Домой',
          ),
        ],
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
          final categories =
              categoriesAsync.asData?.value ?? const <int, Category>{};
          final grouped = <DateTime, _DailyOperationsGroup>{};
          final dates = <DateTime>[];

          if (transactions.isNotEmpty) {
            grouped.addAll(_groupByDate(transactions));
            dates.addAll(grouped.keys);
            dates.sort((a, b) => b.compareTo(a));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(boundsLabel, style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MediaQuery(
                  data: mediaQuery.copyWith(textScaleFactor: clampedTextScale),
                  child: SegmentedButton<OpTypeFilter>(
                    segments: const [
                      ButtonSegment(
                        value: OpTypeFilter.all,
                        label: _SegmentLabel('Все'),
                      ),
                      ButtonSegment(
                        value: OpTypeFilter.expense,
                        label: _SegmentLabel('Расходы'),
                      ),
                      ButtonSegment(
                        value: OpTypeFilter.income,
                        label: _SegmentLabel('Доходы'),
                      ),
                      ButtonSegment(
                        value: OpTypeFilter.saving,
                        label: _SegmentLabel('Сбережения'),
                      ),
                    ],
                    selected: {filter},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: const MaterialStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      textStyle: MaterialStatePropertyAll(filterTextStyle),
                    ),
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      ref.read(opTypeFilterProvider.notifier).state = selection.first;
                    },
                  ),
                ),
              ),
              Expanded(
                child: transactions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.receipt_long, size: 64),
                              const SizedBox(height: 16),
                              Text(
                                filter == OpTypeFilter.all
                                    ? 'Операций пока нет'
                                    : 'Нет операций выбранного типа',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: dates.length,
                        itemBuilder: (context, index) {
                          final date = dates[index];
                          final group = grouped[date]!;
                          return _OperationsSection(
                            title: formatDate(date),
                            group: group,
                            filter: filter,
                            categories: categories,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(text, maxLines: 1),
    );
  }
}

class _OperationsSection extends ConsumerWidget {
  const _OperationsSection({
    required this.title,
    required this.group,
    required this.filter,
    required this.categories,
  });

  final String title;
  final _DailyOperationsGroup group;
  final OpTypeFilter filter;
  final Map<int, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(transactionsRepoProvider);
    final necessityMapAsync = ref.watch(necessityMapProvider);
    final necessityMap = necessityMapAsync.value ?? const <int, necessity_repo.NecessityLabel>{};
    final reasonMapAsync = ref.watch(reasonMapProvider);
    final reasonMap = reasonMapAsync.value ?? const <int, reason_repo.ReasonLabel>{};
    final transactions = group.transactions;
    final dailySummaryLabel = _formatDailyTotalLabel(filter, group);
    final dailySummaryColor = _colorForDailyTotal(filter, group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                dailySummaryLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: dailySummaryColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        ...transactions.map(
          (item) {
            final record = item.record;
            final category = categories[record.categoryId];
            final isPlanOperation = _isPlanOperation(record);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: CircleAvatar(
                  backgroundColor: _colorForType(record.type).withOpacity(0.15),
                  child: Icon(
                    _iconForType(record.type),
                    color: _colorForType(record.type),
                  ),
                ),
                title: SingleLineTooltipText(
                  text: category?.name ?? 'Категория #${record.categoryId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleLineTooltipText(
                      text: _subtitleForRecord(
                        record,
                        necessityMap,
                        reasonMap,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (isPlanOperation) ...[
                      const SizedBox(height: 4),
                      const _PlanBadge(),
                    ],
                  ],
                ),
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
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _labelForType(record.type),
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                onLongPress: () async {
                  final (anchor1, anchor2) = ref.read(anchorDaysProvider);
                  final periodRef =
                      periodRefForDate(record.date, anchor1, anchor2);
                  final status =
                      await ref.read(periodStatusProvider(periodRef).future);
                  if (status.isClosed) {
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Период закрыт. Чтобы изменить операцию, откройте период.',
                        ),
                      ),
                    );
                    return;
                  }
                  final action = await showModalBottomSheet<_OperationAction>(
                    context: context,
                    builder: (context) => const _OperationActionsSheet(),
                  );
                  if (action == null) {
                    return;
                  }
                  if (action != _OperationAction.edit &&
                      action != _OperationAction.delete) {
                    return;
                  }
                  final latestStatus =
                      await ref.read(periodStatusProvider(periodRef).future);
                  if (latestStatus.isClosed) {
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Период закрыт. Чтобы изменить операцию, откройте период.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (action == _OperationAction.delete) {
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
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
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
                    final counterpartId = item.savingCounterpart?.id;
                    if (counterpartId != null) {
                      await repository.delete(counterpartId);
                    }
                    bumpDbTick(ref);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Операция удалена')),
                    );
                    return;
                  }
                  if (action == _OperationAction.edit) {
                    final id = record.id;
                    if (id == null) {
                      return;
                    }
                    final category = categories[record.categoryId];
                    if (category == null) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Категория не найдена')),
                      );
                      return;
                    }
                    final selectedPeriodRef =
                        ref.read(selectedPeriodRefProvider);
                    final originLabel = ref.read(
                      periodLabelForRefProvider(selectedPeriodRef),
                    );
                    final entryAsync =
                        ref.read(periodEntryProvider(selectedPeriodRef));
                    final originEntryId = record.effectivePeriodRefId ??
                        entryAsync.maybeWhen(
                          data: (value) => value.id,
                          orElse: () => null,
                        );
                    ref
                        .read(entryFlowControllerProvider.notifier)
                        .loadFromTransaction(
                          record: record,
                          category: category,
                          savingCounterpart: item.savingCounterpart,
                          originPeriod: selectedPeriodRef,
                          originPeriodEntryId: originEntryId,
                          originPeriodLabel: originLabel,
                        );
                    if (!context.mounted) {
                      return;
                    }
                    context.pushNamed(RouteNames.entryReview);
                  }
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

enum _OperationAction { edit, delete }

class _PlanBadge extends StatelessWidget {
  const _PlanBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'План',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _OperationActionsSheet extends StatelessWidget {
  const _OperationActionsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Редактировать'),
            onTap: () => Navigator.of(context).pop(_OperationAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить'),
            onTap: () => Navigator.of(context).pop(_OperationAction.delete),
          ),
        ],
      ),
    );
  }
}

Map<DateTime, _DailyOperationsGroup> _groupByDate(
  List<TransactionListItem> transactions,
) {
  final grouped = <DateTime, _DailyOperationsGroup>{};
  for (final item in transactions) {
    final record = item.record;
    final date = DateTime(record.date.year, record.date.month, record.date.day);
    final group = grouped.putIfAbsent(date, () => _DailyOperationsGroup());
    group.transactions.add(item);
    if (_isPlanOperation(record)) {
      continue;
    }
    switch (record.type) {
      case TransactionType.expense:
        group.expenseNonPlanTotalMinor += record.amountMinor;
        break;
      case TransactionType.income:
        group.incomeNonPlanTotalMinor += record.amountMinor;
        break;
      case TransactionType.saving:
        group.savingNonPlanTotalMinor += record.amountMinor;
        break;
    }
  }
  return grouped;
}

String _formatDailyTotalLabel(
  OpTypeFilter filter,
  _DailyOperationsGroup group,
) {
  switch (filter) {
    case OpTypeFilter.all:
      final expense = group.expenseNonPlanTotalMinor;
      if (expense == 0) {
        return formatCurrencyMinor(0);
      }
      return '−${formatCurrencyMinor(expense)}';
    case OpTypeFilter.expense:
      final amount = group.expenseNonPlanTotalMinor;
      if (amount == 0) {
        return formatCurrencyMinor(0);
      }
      return '−${formatCurrencyMinor(amount)}';
    case OpTypeFilter.income:
      final amount = group.incomeNonPlanTotalMinor;
      if (amount == 0) {
        return formatCurrencyMinor(0);
      }
      return formatCurrencyMinor(amount);
    case OpTypeFilter.saving:
      final amount = group.savingNonPlanTotalMinor;
      if (amount == 0) {
        return formatCurrencyMinor(0);
      }
      return formatCurrencyMinor(amount);
  }
}

Color? _colorForDailyTotal(
  OpTypeFilter filter,
  _DailyOperationsGroup group,
) {
  switch (filter) {
    case OpTypeFilter.all:
      final expense = group.expenseNonPlanTotalMinor;
      if (expense > 0) {
        return _colorForType(TransactionType.expense);
      }
      return null;
    case OpTypeFilter.expense:
      return group.expenseNonPlanTotalMinor > 0
          ? _colorForType(TransactionType.expense)
          : null;
    case OpTypeFilter.income:
      return group.incomeNonPlanTotalMinor > 0
          ? _colorForType(TransactionType.income)
          : null;
    case OpTypeFilter.saving:
      return group.savingNonPlanTotalMinor > 0
          ? _colorForType(TransactionType.saving)
          : null;
  }
}

class _DailyOperationsGroup {
  _DailyOperationsGroup();

  final List<TransactionListItem> transactions = [];
  int expenseNonPlanTotalMinor = 0;
  int incomeNonPlanTotalMinor = 0;
  int savingNonPlanTotalMinor = 0;
}

bool _isPlanOperation(TransactionRecord record) {
  if (record.isPlanned) {
    return true;
  }
  if (record.plannedId != null) {
    return true;
  }
  if (record.planInstanceId != null) {
    return true;
  }
  final source = record.source;
  if (source != null && source.toLowerCase() == 'plan') {
    return true;
  }
  return false;
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

String _subtitleForRecord(
  TransactionRecord record,
  Map<int, necessity_repo.NecessityLabel> necessityMap,
  Map<int, reason_repo.ReasonLabel> reasonMap,
) {
  final isPlanOperation = _isPlanOperation(record);

  if (isPlanOperation) {
    return record.necessityLabel ??
        necessityMap[record.necessityId]?.name ??
        'Без комментария';
  }

  final note = record.note?.trim();
  if (note != null && note.isNotEmpty) {
    return note;
  }

  if (record.type == TransactionType.expense) {
    return record.reasonLabel ??
        reasonMap[record.reasonId]?.name ??
        'Без комментария';
  }

  if (record.type == TransactionType.saving) {
    return record.necessityLabel ??
        necessityMap[record.necessityId]?.name ??
        'Без комментария';
  }

  return 'Без комментария';
}
