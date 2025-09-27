import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/categories_repository.dart';
import '../data/repositories/planned_master_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../utils/period_utils.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

enum PlannedType { income, expense, saving }

extension on PlannedType {
  TransactionType toTransactionType() {
    switch (this) {
      case PlannedType.income:
        return TransactionType.income;
      case PlannedType.expense:
        return TransactionType.expense;
      case PlannedType.saving:
        return TransactionType.saving;
    }
  }
}

class PlannedItemView {
  const PlannedItemView({
    required this.record,
    this.category,
    this.master,
  });

  final TransactionRecord record;
  final Category? category;
  final PlannedMaster? master;

  double get amount => record.amountMinor / 100;

  bool get includedInPeriod => record.includedInPeriod;

  bool get isCompleted => record.includedInPeriod;

  bool get isDone => isCompleted;

  String get title {
    final masterTitle = master?.title;
    if (masterTitle != null && masterTitle.trim().isNotEmpty) {
      return masterTitle.trim();
    }
    final note = record.note;
    if (note != null && note.trim().isNotEmpty) {
      return note.trim();
    }
    return category?.name ?? 'Без названия';
  }

  String? get necessityLabel => record.necessityLabel;

  int get criticality => record.criticality;
}

String _typeToQuery(PlannedType type) {
  switch (type) {
    case PlannedType.income:
      return 'income';
    case PlannedType.expense:
      return 'expense';
    case PlannedType.saving:
      return 'saving';
  }
}

Future<List<PlannedItemView>> _loadPlannedItemsForPeriod(
  Ref ref,
  PlannedType type,
  PeriodRef period, {
  required bool onlyIncluded,
}) async {
  ref.watch(dbTickProvider);
  final transactionsRepo = ref.watch(transactionsRepoProvider);
  final categoriesRepo = ref.watch(categoriesRepositoryProvider);
  final masterRepo = ref.watch(plannedMasterRepoProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final records = await transactionsRepo.listPlannedByPeriod(
    start: bounds.start,
    endExclusive: bounds.endExclusive,
    type: _typeToQuery(type),
    onlyIncluded: onlyIncluded ? true : null,
  );
  if (records.isEmpty) {
    return const [];
  }
  final categories = await categoriesRepo.getAll();
  final categoriesById = {
    for (final category in categories)
      if (category.id != null) category.id!: category,
  };
  final masters = await masterRepo.list(includeArchived: true);
  final mastersById = {
    for (final master in masters)
      if (master.id != null) master.id!: master,
  };
  return [
    for (final record in records)
      PlannedItemView(
        record: record,
        category: categoriesById[record.categoryId],
        master:
            record.plannedId != null ? mastersById[record.plannedId!] : null,
      ),
  ];
}

typedef PlannedPeriodArgs = ({PlannedType type, PeriodRef period});

final plannedForPeriodProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedPeriodArgs>((ref, args) async {
  return _loadPlannedItemsForPeriod(
    ref,
    args.type,
    args.period,
    onlyIncluded: false,
  );
});

final plannedIncludedForPeriodProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedPeriodArgs>((ref, args) async {
  return _loadPlannedItemsForPeriod(
    ref,
    args.type,
    args.period,
    onlyIncluded: true,
  );
});

final plannedIncludedSumProvider = FutureProvider.family<int, PlannedPeriodArgs>(
    (ref, args) async {
  final items = await ref.watch(plannedIncludedForPeriodProvider(args).future);
  return items.fold<int>(0, (sum, item) => sum + item.record.amountMinor);
});

final plannedItemsByTypeProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedType>((ref, type) async {
  final period = ref.watch(selectedPeriodRefProvider);
  return ref
      .watch(plannedForPeriodProvider((type: type, period: period)).future);
});

final plannedExpensesForPeriodProvider = FutureProvider.family
    <List<PlannedItemView>, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  return _loadPlannedItemsForPeriod(
    ref,
    PlannedType.expense,
    period,
    onlyIncluded: false,
  );
});

final plannedIncludedByTypeProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedType>((ref, type) async {
  final period = ref.watch(selectedPeriodRefProvider);
  return ref.watch(
    plannedIncludedForPeriodProvider((type: type, period: period)).future,
  );
});

final plannedTotalByTypeProvider =
    FutureProvider.family<int, PlannedType>((ref, type) async {
  final items = await ref.watch(plannedItemsByTypeProvider(type).future);
  return items.fold<int>(0, (sum, item) => sum + item.record.amountMinor);
});

final plannedIncludedTotalProvider =
    FutureProvider.family<int, PlannedType>((ref, type) async {
  final items = await ref.watch(plannedIncludedByTypeProvider(type).future);
  return items.fold<int>(0, (sum, item) => sum + item.record.amountMinor);
});

typedef PlannedRemainder = ({int remainderMinor, int deficitMinor});

final plannedRemainderForPeriodProvider =
    FutureProvider<PlannedRemainder?>((ref) async {
  ref.watch(dbTickProvider);
  final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
  if (payout == null) {
    return null;
  }

  final dailyLimitMinor = await ref.watch(dailyLimitProvider.future) ?? 0;
  final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
  var periodDays = periodEndExclusive.difference(periodStart).inDays;
  if (periodDays < 0) {
    periodDays = 0;
  }

  final plannedSpentIncludedMinor =
      await ref.watch(plannedIncludedTotalProvider(PlannedType.expense).future);

  final rawRemainder = payout.amountMinor -
      dailyLimitMinor * periodDays -
      plannedSpentIncludedMinor;

  final remainderMinor = rawRemainder > 0 ? rawRemainder : 0;
  final deficitMinor = rawRemainder < 0 ? -rawRemainder : 0;

  return (
    remainderMinor: remainderMinor,
    deficitMinor: deficitMinor,
  );
});

final plannedActionsProvider = Provider<PlannedActions>((ref) {
  final repo = ref.watch(transactionsRepoProvider);
  return PlannedActions(repo);
});

final sumIncludedPlannedExpensesProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final repository = ref.watch(transactionsRepoProvider);
  return repository.sumIncludedPlannedExpenses(
    period: period,
    start: bounds.start,
    endExclusive: bounds.endExclusive,
  );
});

final plannedPoolRemainingProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  final base = await ref.watch(plannedPoolBaseProvider.future);
  final used = await ref.watch(sumIncludedPlannedExpensesProvider(period).future);
  final remaining = base - used;
  return math.max(remaining, 0);
});

class PlannedActions {
  const PlannedActions(this._repository);

  final TransactionsRepository _repository;

  Future<int> add(TransactionRecord record) {
    return _repository.add(record, asSavingPair: false);
  }

  Future<void> update(TransactionRecord record) {
    return _repository.update(record);
  }

  Future<void> remove(int id) {
    return _repository.delete(id);
  }

  Future<void> toggle(int id, bool value) {
    return _repository.setPlannedIncluded(id, value);
  }
}
