import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/categories_repository.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';
import 'planned_master_providers.dart';

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
  });

  final TransactionRecord record;
  final Category? category;

  double get amount => record.amountMinor / 100;

  bool get includedInPeriod => record.includedInPeriod;

  bool get isCompleted => record.includedInPeriod;

  bool get isDone => isCompleted;

  String get title {
    final note = record.note;
    if (note != null && note.trim().isNotEmpty) {
      return note.trim();
    }
    return category?.name ?? 'Без названия';
  }

  String? get necessityLabel => record.necessityLabel;

  int get criticality => record.criticality;
}

Future<List<PlannedItemView>> _loadPlannedItems(
  Ref ref,
  PlannedType type, {
  required bool onlyIncluded,
}) async {
  ref.watch(dbTickProvider);
  final transactionsRepo = ref.watch(transactionsRepoProvider);
  final categoriesRepo = ref.watch(categoriesRepositoryProvider);
  final bounds = ref.watch(periodBoundsProvider);
  final typeString = switch (type) {
    PlannedType.income => 'income',
    PlannedType.expense => 'expense',
    PlannedType.saving => 'saving',
  };
  final records = await transactionsRepo.listPlannedByPeriod(
    start: bounds.$1,
    endExclusive: bounds.$2,
    type: typeString,
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
  return [
    for (final record in records)
      PlannedItemView(
        record: record,
        category: categoriesById[record.categoryId],
      ),
  ];
}

final plannedItemsByTypeProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedType>((ref, type) async {
  return _loadPlannedItems(ref, type, onlyIncluded: false);
});

final plannedIncludedByTypeProvider = FutureProvider.family
    <List<PlannedItemView>, PlannedType>((ref, type) async {
  final included =
      await ref.watch(plannedIncludedForSelectedPeriodProvider(
    switch (type) {
      PlannedType.income => 'income',
      PlannedType.expense => 'expense',
      PlannedType.saving => 'saving',
    },
  ).future);
  if (included.isEmpty) {
    return const [];
  }
  final categoriesRepo = ref.watch(categoriesRepositoryProvider);
  final categories = await categoriesRepo.getAll();
  final categoriesById = {
    for (final category in categories)
      if (category.id != null) category.id!: category,
  };
  return [
    for (final record in included)
      PlannedItemView(
        record: record,
        category: categoriesById[record.categoryId],
      ),
  ];
});

final plannedTotalByTypeProvider =
    FutureProvider.family<int, PlannedType>((ref, type) async {
  ref.watch(dbTickProvider);
  final items = await ref.watch(plannedItemsByTypeProvider(type).future);
  return items.fold<int>(0, (sum, item) => sum + item.record.amountMinor);
});

final plannedIncludedTotalProvider =
    FutureProvider.family<int, PlannedType>((ref, type) async {
  ref.watch(dbTickProvider);
  final items = await ref.watch(plannedIncludedByTypeProvider(type).future);
  return items.fold<int>(0, (sum, item) => sum + item.record.amountMinor);
});

final plannedActionsProvider = Provider<PlannedActions>((ref) {
  final repo = ref.watch(transactionsRepoProvider);
  return PlannedActions(repo);
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
    return _repository.setIncludedInPeriod(
      transactionId: id,
      value: value,
    );
  }
}
