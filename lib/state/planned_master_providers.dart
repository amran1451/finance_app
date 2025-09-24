import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart' as category_models;
import '../data/repositories/planned_master_repository.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

final plannedMasterRepoProvider = Provider<PlannedMasterRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SqlitePlannedMasterRepository(database: database);
});

final plannedMasterByIdProvider =
    FutureProvider.family<PlannedMaster?, int>((ref, id) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(plannedMasterRepoProvider);
  return repository.getById(id);
});

final plannedMasterListProvider =
    FutureProvider<List<PlannedMaster>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(plannedMasterRepoProvider);
  return repository.list();
});

final plannedInstancesForSelectedPeriodProvider =
    FutureProvider.family<List<TransactionItem>, String?>((ref, type) async {
  ref.watch(dbTickProvider);
  final bounds = ref.watch(periodBoundsProvider);
  final repository = ref.watch(transactionsRepoProvider);
  return repository.listPlannedByPeriod(
    start: bounds.$1,
    endExclusive: bounds.$2,
    type: type,
  );
});

final plannedIncludedForSelectedPeriodProvider =
    FutureProvider.family<List<TransactionItem>, String?>((ref, type) async {
  ref.watch(dbTickProvider);
  final bounds = ref.watch(periodBoundsProvider);
  final repository = ref.watch(transactionsRepoProvider);
  return repository.listPlannedByPeriod(
    start: bounds.$1,
    endExclusive: bounds.$2,
    type: type,
    onlyIncluded: true,
  );
});

final plannedInstancesCountByMasterProvider =
    FutureProvider<Map<int, int>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final records = await repository.listPlanned();
  final result = <int, int>{};
  for (final record in records) {
    final masterId = record.plannedId;
    if (masterId == null) {
      continue;
    }
    result[masterId] = (result[masterId] ?? 0) + 1;
  }
  return result;
});

final categoriesMapProvider = FutureProvider<
    Map<int, category_models.Category>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
  final categories = await repository.getAll();
  return {
    for (final category in categories)
      if (category.id != null) category.id!: category,
  };
});
