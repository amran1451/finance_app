import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/bootstrap/app_bootstrapper.dart';
import '../data/db/app_database.dart';
import '../data/models/account.dart' as account_models;
import '../data/models/payout.dart' as payout_models;
import '../data/mock/mock_models.dart' as mock;
import '../data/mock/mock_repositories.dart' as mock_repo;
import '../data/models/category.dart' as category_models;
import '../data/models/transaction_record.dart' as transaction_models;
import '../data/repositories/accounts_repository.dart' as accounts_repo;
import '../data/repositories/analytics_repository.dart' as analytics_repo;
import '../data/repositories/categories_repository.dart' as categories_repo;
import '../data/repositories/payouts_repository.dart' as payouts_repo;
import '../data/repositories/periods_repository.dart' as periods_repo;
import '../data/repositories/necessity_repository.dart' as necessity_repo;
import '../data/repositories/reason_repository.dart' as reason_repo;
import '../data/repositories/settings_repository.dart' as settings_repo;
import '../data/repositories/transactions_repository.dart' as transactions_repo;
import '../utils/period_utils.dart';
import 'db_refresh.dart';

class TelemetryService {
  const TelemetryService();

  void log(String event, {Map<String, Object?>? properties}) {
    final payload = properties == null || properties.isEmpty ? '' : ' $properties';
    debugPrint('[telemetry] $event$payload');
  }
}

final telemetryProvider = Provider<TelemetryService>((_) {
  return const TelemetryService();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final appBootstrapProvider = FutureProvider<void>((ref) async {
  final database = ref.watch(appDatabaseProvider);
  final bootstrapper = AppBootstrapper(database: database);
  await bootstrapper.run();
});

final accountsRepoProvider =
    Provider<accounts_repo.AccountsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return accounts_repo.SqliteAccountsRepository(database: database);
});

final analyticsRepoProvider =
    Provider<analytics_repo.AnalyticsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return analytics_repo.AnalyticsRepository(database: database);
});

final accountsDbProvider =
    FutureProvider<List<account_models.Account>>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(accountsRepoProvider);
  return repository.getAll();
});

final activeAccountsProvider =
    FutureProvider<List<account_models.Account>>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(accountsRepoProvider);
  return repository.listActive();
});

final categoriesRepositoryProvider =
    Provider<categories_repo.CategoriesRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return categories_repo.SqliteCategoriesRepository(database: database);
});

final categoryGroupsProvider = FutureProvider.family<
    List<category_models.Category>, category_models.CategoryType>((ref, type) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
  return repository.groupsByType(type);
});

final categoriesByTypeProvider = FutureProvider.family<
    List<category_models.Category>, category_models.CategoryType>((ref, type) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
  return repository.getByType(type);
});

final categoryChildrenProvider = FutureProvider.family<
    List<category_models.Category>, int>((ref, groupId) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
  return repository.childrenOf(groupId);
});

typedef CategoryTree = ({
  List<category_models.Category> groups,
  List<category_models.Category> categories,
});

final categoryTreeProvider = FutureProvider.family<
    CategoryTree, category_models.CategoryType>((ref, type) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(categoriesRepositoryProvider);
  final groups = await repository.groupsByType(type);
  final categories = await repository.getByType(type);
  return (groups: groups, categories: categories);
});

final transactionsRepoProvider =
    Provider<transactions_repo.TransactionsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final repository =
      transactions_repo.SqliteTransactionsRepository(database: database);
  return _TransactionsRepositoryWithDbTick(ref, repository);
});

final payoutsRepoProvider = Provider<payouts_repo.PayoutsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final repository =
      payouts_repo.SqlitePayoutsRepository(database: database);
  return _PayoutsRepositoryWithDbTick(ref, repository);
});

final periodsRepoProvider = Provider<periods_repo.PeriodsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final repository = periods_repo.SqlitePeriodsRepository(database: database);
  return _PeriodsRepositoryWithDbTick(ref, repository);
});

final settingsRepoProvider = Provider<settings_repo.SettingsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return settings_repo.SqliteSettingsRepository(database: database);
});

final defaultAccountIdProvider = FutureProvider<int?>((ref) async {
  final repository = ref.watch(settingsRepoProvider);
  return repository.getDefaultAccountId();
});

final necessityRepoProvider = Provider<necessity_repo.NecessityRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return necessity_repo.NecessityRepositorySqlite(database: database);
});

final reasonRepoProvider = Provider<reason_repo.ReasonRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return reason_repo.ReasonRepositorySqlite(database: database);
});

class _TransactionsRepositoryWithDbTick
    implements transactions_repo.TransactionsRepository {
  _TransactionsRepositoryWithDbTick(this._ref, this._delegate);

  final Ref _ref;
  final transactions_repo.TransactionsRepository _delegate;

  @override
  Future<transaction_models.TransactionRecord?> findByPayoutId(
    int payoutId,
  ) {
    return _delegate.findByPayoutId(payoutId);
  }

  @override
  Future<int> add(
    transaction_models.TransactionRecord record, {
    bool asSavingPair = false,
    bool? includedInPeriod,
    PeriodRef? uiPeriod,
    DatabaseExecutor? executor,
  }) async {
    final result = await _delegate.add(
      record,
      asSavingPair: asSavingPair,
      includedInPeriod: includedInPeriod,
      uiPeriod: uiPeriod,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
    return result;
  }

  @override
  Future<void> assignMasterToPeriod({
    required int masterId,
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required bool included,
    int? necessityId,
    String? note,
    required int accountId,
    DatabaseExecutor? executor,
  }) async {
    await _delegate.assignMasterToPeriod(
      masterId: masterId,
      period: period,
      start: start,
      endExclusive: endExclusive,
      categoryId: categoryId,
      amountMinor: amountMinor,
      included: included,
      necessityId: necessityId,
      note: note,
      accountId: accountId,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) async {
    await _delegate.delete(id, executor: executor);
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<void> deletePlannedInstance(int plannedId,
      {DatabaseExecutor? executor}) async {
    await _delegate.deletePlannedInstance(plannedId, executor: executor);
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<int> deleteInstancesByPlannedId(int plannedId,
      {DatabaseExecutor? executor}) async {
    final result = await _delegate.deleteInstancesByPlannedId(
      plannedId,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
    return result;
  }

  @override
  Future<List<transaction_models.TransactionRecord>> getAll() {
    return _delegate.getAll();
  }

  @override
  Future<transaction_models.TransactionRecord?> getById(int id) {
    return _delegate.getById(id);
  }

  @override
  Future<List<transaction_models.TransactionRecord>> getByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    transaction_models.TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
    String? periodId,
  }) {
    return _delegate.getByPeriod(
      from,
      to,
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      isPlanned: isPlanned,
      includedInPeriod: includedInPeriod,
      periodId: periodId,
    );
  }

  @override
  Future<List<transactions_repo.TransactionListItem>>
      getOperationItemsByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    transaction_models.TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
    bool aggregateSavingPairs = false,
    String? periodId,
  }) {
    return _delegate.getOperationItemsByPeriod(
      from,
      to,
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      isPlanned: isPlanned,
      includedInPeriod: includedInPeriod,
      aggregateSavingPairs: aggregateSavingPairs,
      periodId: periodId,
    );
  }

  @override
  Future<List<transaction_models.TransactionRecord>> listPlanned({
    transaction_models.TransactionType? type,
    bool onlyIncluded = false,
  }) {
    return _delegate.listPlanned(
      type: type,
      onlyIncluded: onlyIncluded,
    );
  }

  @override
  Future<List<transactions_repo.TransactionItem>> listPlannedByPeriod({
    required DateTime start,
    required DateTime endExclusive,
    String? type,
    bool? onlyIncluded,
    String? periodId,
  }) {
    return _delegate.listPlannedByPeriod(
      start: start,
      endExclusive: endExclusive,
      type: type,
      onlyIncluded: onlyIncluded,
      periodId: periodId,
    );
  }

  @override
  Future<int> createPlannedInstance({
    required int plannedId,
    required String type,
    required int accountId,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    String? note,
    int? necessityId,
    String? necessityLabel,
    bool includedInPeriod = false,
    int criticality = 0,
    PeriodRef? period,
    DatabaseExecutor? executor,
  }) async {
    final result = await _delegate.createPlannedInstance(
      plannedId: plannedId,
      type: type,
      accountId: accountId,
      amountMinor: amountMinor,
      date: date,
      categoryId: categoryId,
      note: note,
      necessityId: necessityId,
      necessityLabel: necessityLabel,
      includedInPeriod: includedInPeriod,
      criticality: criticality,
      period: period,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
    return result;
  }

  @override
  Future<int> sumPlannedExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
    String? periodId,
  }) {
    return _delegate.sumPlannedExpenses(
      period: period,
      start: start,
      endExclusive: endExclusive,
      periodId: periodId,
    );
  }

  @override
  Future<void> setIncludedInPeriod({
    required int transactionId,
    required bool value,
    DatabaseExecutor? executor,
  }) async {
    await _delegate.setIncludedInPeriod(
      transactionId: transactionId,
      value: value,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<void> setPlannedCompletion(int id, bool isCompleted,
      {DatabaseExecutor? executor}) async {
    await _delegate.setPlannedCompletion(
      id,
      isCompleted,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<void> setPlannedIncluded(int plannedId, bool included,
      {DatabaseExecutor? executor}) async {
    await _delegate.setPlannedIncluded(
      plannedId,
      included,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<int> sumUnplannedExpensesOnDate(DateTime date) {
    return _delegate.sumUnplannedExpensesOnDate(date);
  }

  @override
  Future<int> sumExpensesOnDateWithinPeriod({
    required DateTime date,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    String? periodId,
  }) {
    return _delegate.sumExpensesOnDateWithinPeriod(
      date: date,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      periodId: periodId,
    );
  }

  @override
  Future<int> sumUnplannedExpensesInRange(
    DateTime from,
    DateTime toExclusive,
    {String? periodId,}
  ) {
    return _delegate.sumUnplannedExpensesInRange(
      from,
      toExclusive,
      periodId: periodId,
    );
  }

  @override
  Future<int> sumActualExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
    String? periodId,
  }) {
    return _delegate.sumActualExpenses(
      period: period,
      start: start,
      endExclusive: endExclusive,
      periodId: periodId,
    );
  }

  @override
  Future<void> update(
    transaction_models.TransactionRecord record, {
    bool? includedInPeriod,
    PeriodRef? uiPeriod,
    DatabaseExecutor? executor,
  }) async {
    await _delegate.update(
      record,
      includedInPeriod: includedInPeriod,
      uiPeriod: uiPeriod,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }
}

class _PeriodsRepositoryWithDbTick implements periods_repo.PeriodsRepository {
  _PeriodsRepositoryWithDbTick(this._ref, this._delegate);

  final Ref _ref;
  final periods_repo.PeriodsRepository _delegate;

  @override
  Future<void> closePeriod(
    PeriodRef period, {
    int? payoutId,
    int? dailyLimitMinor,
    int? spentMinor,
    int? plannedIncludedMinor,
    int? carryoverMinor,
    DatabaseExecutor? executor,
  }) {
    return _delegate.closePeriod(
      period,
      payoutId: payoutId,
      dailyLimitMinor: dailyLimitMinor,
      spentMinor: spentMinor,
      plannedIncludedMinor: plannedIncludedMinor,
      carryoverMinor: carryoverMinor,
      executor: executor,
    );
  }

  @override
  Future<periods_repo.PeriodEntry> getOrCreate(
    int year,
    int month,
    HalfPeriod half,
    DateTime start,
    DateTime endExclusive, {
    DatabaseExecutor? executor,
  }) {
    return _delegate.getOrCreate(
      year,
      month,
      half,
      start,
      endExclusive,
      executor: executor,
    );
  }

  @override
  Future<periods_repo.PeriodStatus> getStatus(PeriodRef period) {
    return _delegate.getStatus(period);
  }

  @override
  Future<void> reopen(
    PeriodRef period, {
    DatabaseExecutor? executor,
  }) {
    return _delegate.reopen(period, executor: executor);
  }

  @override
  Future<void> reopenLast({DatabaseExecutor? executor}) {
    return _delegate.reopenLast(executor: executor);
  }

  @override
  Future<void> setPeriodClosed(
    PeriodRef ref, {
    required bool closed,
    DateTime? at,
  }) async {
    await _delegate.setPeriodClosed(ref, closed: closed, at: at);
    bumpDbTick(_ref);
  }
}

class _PayoutsRepositoryWithDbTick implements payouts_repo.PayoutsRepository {
  _PayoutsRepositoryWithDbTick(this._ref, this._delegate);

  final Ref _ref;
  final payouts_repo.PayoutsRepository _delegate;

  @override
  Future<int> add(
    payout_models.PayoutType type,
    DateTime date,
    int amountMinor, {
    int? accountId,
    DatabaseExecutor? executor,
  }) {
    return _delegate.add(
      type,
      date,
      amountMinor,
      accountId: accountId,
      executor: executor,
    );
  }

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) async {
    await _delegate.delete(id, executor: executor);
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<payout_models.Payout?> findInRange(
    DateTime start,
    DateTime endExclusive, {
    String? assignedPeriodId,
  }) {
    return _delegate.findInRange(
      start,
      endExclusive,
      assignedPeriodId: assignedPeriodId,
    );
  }

  @override
  Future<List<payout_models.Payout>> getHistory(int limit) {
    return _delegate.getHistory(limit);
  }

  @override
  Future<payout_models.Payout?> getLast() {
    return _delegate.getLast();
  }

  @override
  Future<List<payout_models.Payout>> listInRange(
    DateTime start,
    DateTime endExclusive,
  ) {
    return _delegate.listInRange(start, endExclusive);
  }

  @override
  Future<void> setDailyLimit({
    required int payoutId,
    required int dailyLimitMinor,
    required bool fromToday,
    DatabaseExecutor? executor,
  }) async {
    await _delegate.setDailyLimit(
      payoutId: payoutId,
      dailyLimitMinor: dailyLimitMinor,
      fromToday: fromToday,
      executor: executor,
    );
    if (executor == null) {
      bumpDbTick(_ref);
    }
  }

  @override
  Future<({int dailyLimitMinor, bool fromToday})> getDailyLimit(int payoutId) {
    return _delegate.getDailyLimit(payoutId);
  }

  @override
  Future<void> update({
    required int id,
    required payout_models.PayoutType type,
    required DateTime date,
    required int amountMinor,
    int? accountId,
    DatabaseExecutor? executor,
  }) {
    return _delegate.update(
      id: id,
      type: type,
      date: date,
      amountMinor: amountMinor,
      accountId: accountId,
      executor: executor,
    );
  }

  @override
  Future<({payout_models.Payout payout, PeriodRef period})>
      upsertWithClampToSelectedPeriod({
    payout_models.Payout? existing,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required payout_models.PayoutType type,
    required int amountMinor,
    int? accountId,
    bool shiftPeriodStart = false,
    DatabaseExecutor? executor,
  }) {
    return _delegate.upsertWithClampToSelectedPeriod(
      existing: existing,
      selectedPeriod: selectedPeriod,
      pickedDate: pickedDate,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      shiftPeriodStart: shiftPeriodStart,
      executor: executor,
    );
  }
}

final computedBalanceProvider =
    FutureProvider.family<int, int>((ref, accountId) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(accountsRepoProvider);
  return repository.getComputedBalanceMinor(accountId);
});

final reconcileAccountProvider =
    Provider<Future<void> Function(int)>((ref) {
  final repository = ref.watch(accountsRepoProvider);
  return (accountId) => repository.reconcileToComputed(accountId);
});

final budgetPeriodRepositoryProvider =
    Provider<mock_repo.BudgetPeriodRepository>((ref) {
  return mock_repo.BudgetPeriodRepository();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class ActivePeriodNotifier extends StateNotifier<mock.BudgetPeriod> {
  ActivePeriodNotifier(this._repository) : super(_repository.activePeriod);

  final mock_repo.BudgetPeriodRepository _repository;

  void setActive(String id) {
    _repository.setActive(id);
    state = _repository.activePeriod;
  }
}

final activePeriodProvider =
    StateNotifierProvider<ActivePeriodNotifier, mock.BudgetPeriod>((ref) {
  final repository = ref.watch(budgetPeriodRepositoryProvider);
  return ActivePeriodNotifier(repository);
});

final periodsProvider = Provider<List<mock.BudgetPeriod>>((ref) {
  final repository = ref.watch(budgetPeriodRepositoryProvider);
  return repository.periods;
});

final accountsRepositoryProvider =
    Provider<mock_repo.AccountsRepository>((ref) {
  return mock_repo.AccountsRepository();
});

final isSheetOpenProvider = StateProvider<bool>((_) => false);

final plansExpandedProvider = StateProvider<bool>((_) => false);

final necessityLabelsFutureProvider =
    FutureProvider<List<necessity_repo.NecessityLabel>>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(necessityRepoProvider);
  return repository.list();
});

final necessityMapProvider =
    FutureProvider<Map<int, necessity_repo.NecessityLabel>>((ref) async {
  final labels = await ref.watch(necessityLabelsFutureProvider.future);
  return {
    for (final label in labels) label.id: label,
  };
});

final savingPairEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(settingsRepoProvider);
  return repository.getSavingPairEnabled();
});
