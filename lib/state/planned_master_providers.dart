import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/category.dart' as category_models;
import '../data/models/transaction_record.dart';
import '../data/repositories/necessity_repository.dart';
import '../data/repositories/planned_instances_repository.dart';
import '../data/repositories/planned_master_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../utils/period_utils.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

@immutable
class ExpenseMasterFilters {
  const ExpenseMasterFilters({
    this.categoryId,
    this.necessityId,
    this.search = '',
    this.sortDesc = false,
  });

  final int? categoryId;
  final int? necessityId;
  final String search;
  final bool sortDesc;

  ExpenseMasterFilters copyWith({
    int? categoryId,
    Object? necessityId = _sentinel,
    String? search,
    bool? sortDesc,
  }) {
    return ExpenseMasterFilters(
      categoryId: categoryId ?? this.categoryId,
      necessityId: necessityId == _sentinel
          ? this.necessityId
          : necessityId as int?,
      search: search ?? this.search,
      sortDesc: sortDesc ?? this.sortDesc,
    );
  }

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ExpenseMasterFilters &&
        other.categoryId == categoryId &&
        other.necessityId == necessityId &&
        other.search == search &&
        other.sortDesc == sortDesc;
  }

  @override
  int get hashCode => Object.hash(categoryId, necessityId, search, sortDesc);
}

final plannedMasterRepoProvider = Provider<PlannedMasterRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SqlitePlannedMasterRepository(database: database);
});

final availableExpenseMastersProvider = FutureProvider.family<
    List<PlannedMasterView>, (PeriodRef, ExpenseMasterFilters)>((ref, args) async {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final period = args.$1;
  final filters = args.$2;
  final bounds = period.bounds(anchor1, anchor2);
  final repository = ref.watch(plannedMasterRepoProvider);
  final search = filters.search.trim().isEmpty ? null : filters.search.trim();
  return repository.queryAvailableForPeriod(
    start: bounds.start,
    endExclusive: bounds.endExclusive,
    categoryId: filters.categoryId,
    necessityId: filters.necessityId,
    search: search,
    sortByAmountDesc: filters.sortDesc,
  );
});

final plannedInstancesRepoProvider =
    Provider<PlannedInstancesRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SqlitePlannedInstancesRepository(database: database);
});

final plannedInstancesByMasterProvider =
    FutureProvider.family<List<TransactionRecord>, int>((ref, masterId) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final records = await repository.listPlanned();
  return [
    for (final record in records)
      if (record.plannedId == masterId) record,
  ];
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

typedef PlannedMasterAssignmentQuery = ({String? type, bool includeAssigned});

final plannedMastersForAssignmentProvider = FutureProvider.family<
    List<PlannedMaster>, PlannedMasterAssignmentQuery>((ref, query) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(plannedMasterRepoProvider);
  if (query.includeAssigned) {
    final masters = await repository.list();
    final type = query.type?.toLowerCase();
    if (type == null) {
      return masters;
    }
    return [
      for (final master in masters)
        if (master.type == type) master,
    ];
  }
  final bounds = ref.watch(periodBoundsProvider);
  return repository.listAssignableForPeriod(
    bounds.$1,
    bounds.$2,
    type: query.type,
  );
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

final plannedFacadeProvider = Provider<PlannedFacade>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final masterRepository = ref.watch(plannedMasterRepoProvider);
  final instancesRepository = ref.watch(plannedInstancesRepoProvider);
  final settingsRepository = ref.watch(settingsRepoProvider);
  final necessityRepository = ref.watch(necessityRepoProvider);
  return PlannedFacade(
    database: database,
    masterRepository: masterRepository,
    instancesRepository: instancesRepository,
    settingsRepository: settingsRepository,
    necessityRepository: necessityRepository,
  );
});

class PlannedFacade {
  PlannedFacade({
    required AppDatabase database,
    required PlannedMasterRepository masterRepository,
    required PlannedInstancesRepository instancesRepository,
    required SettingsRepository settingsRepository,
    required NecessityRepository necessityRepository,
  })  : _database = database,
        _masterRepository = masterRepository,
        _instancesRepository = instancesRepository,
        _settingsRepository = settingsRepository,
        _necessityRepository = necessityRepository;

  final AppDatabase _database;
  final PlannedMasterRepository _masterRepository;
  final PlannedInstancesRepository _instancesRepository;
  final SettingsRepository _settingsRepository;
  final NecessityRepository _necessityRepository;

  Future<void> createMasterAndAssignToCurrentPeriod({
    required String type,
    required String title,
    required int categoryId,
    required int amountMinor,
    required PeriodRef period,
    bool includedInPeriod = true,
    int? necessityId,
    String? note,
    bool reuseExisting = true,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Title cannot be empty');
    }
    final normalizedType = type.toLowerCase();
    final sanitizedNote = note == null || note.trim().isEmpty ? null : note.trim();
    final anchors = await _resolveAnchors();
    final bounds = period.bounds(anchors.$1, anchors.$2);
    final necessityLabel =
        necessityId == null ? null : await _loadNecessityLabel(necessityId);

    final db = await _database.database;
    await db.transaction((txn) async {
      PlannedMaster? master;
      if (reuseExisting) {
        master = await _masterRepository.findByTitleAndType(
          normalizedType,
          trimmedTitle,
          executor: txn,
        );
      }
      master ??= await _masterRepository.createMaster(
        type: normalizedType,
        title: trimmedTitle,
        categoryId: categoryId,
        amountMinor: amountMinor,
        necessityId: necessityId,
        note: sanitizedNote,
        executor: txn,
      );
      final masterId = master.id;
      if (masterId == null) {
        throw StateError('Planned master identifier is missing');
      }
      await _instancesRepository.assignMasterToPeriod(
        masterId: masterId,
        start: bounds.start,
        endExclusive: bounds.endExclusive,
        categoryId: categoryId,
        amountMinor: amountMinor,
        type: normalizedType,
        includedInPeriod: includedInPeriod,
        necessityId: necessityId,
        necessityLabel: necessityLabel,
        note: sanitizedNote,
        executor: txn,
      );
    });
  }

  Future<(int, int)> _resolveAnchors() async {
    final day1 = await _settingsRepository.getAnchorDay1();
    final day2 = await _settingsRepository.getAnchorDay2();
    if (day1 <= day2) {
      return (day1, day2);
    }
    return (day2, day1);
  }

  Future<String?> _loadNecessityLabel(int? id) async {
    if (id == null) {
      return null;
    }
    final label = await _necessityRepository.findById(id);
    return label?.name;
  }
}
