import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/planned_master_repository.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

final plannedMasterRepoProvider = Provider<PlannedMasterRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SqlitePlannedMasterRepository(database: database);
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
