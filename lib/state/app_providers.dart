import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/account.dart' as db_models;
import '../data/mock/mock_models.dart' as mock;
import '../data/mock/mock_repositories.dart' as mock_repo;
import '../data/repositories/accounts_repository.dart' as accounts_repo;
import '../data/repositories/categories_repository.dart' as categories_repo;
import '../data/repositories/payouts_repository.dart' as payouts_repo;
import '../data/repositories/settings_repository.dart' as settings_repo;
import '../data/repositories/transactions_repository.dart' as transactions_repo;

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final accountsRepoProvider =
    Provider<accounts_repo.AccountsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return accounts_repo.SqliteAccountsRepository(database: database);
});

final accountsDbProvider = FutureProvider<List<db_models.Account>>((ref) {
  final repository = ref.watch(accountsRepoProvider);
  return repository.getAll();
});

final categoriesRepoProvider =
    Provider<categories_repo.CategoriesRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return categories_repo.SqliteCategoriesRepository(database: database);
});

final transactionsRepoProvider =
    Provider<transactions_repo.TransactionsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return transactions_repo.SqliteTransactionsRepository(database: database);
});

final payoutsRepoProvider = Provider<payouts_repo.PayoutsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return payouts_repo.SqlitePayoutsRepository(database: database);
});

final settingsRepoProvider = Provider<settings_repo.SettingsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return settings_repo.SqliteSettingsRepository(database: database);
});

final computedBalanceProvider =
    FutureProvider.family<int, int>((ref, accountId) async {
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

final categoriesRepositoryProvider =
    ChangeNotifierProvider<mock_repo.CategoriesRepository>((ref) {
  return mock_repo.CategoriesRepository();
});

final operationsRepositoryProvider =
    Provider<mock_repo.OperationsRepository>((ref) {
  return mock_repo.OperationsRepository();
});

final isSheetOpenProvider = StateProvider<bool>((_) => false);

final accountsProvider = Provider<List<mock.Account>>((ref) {
  final repository = ref.watch(accountsRepositoryProvider);
  return repository.getAccounts();
});

final activePeriodOperationsProvider = Provider<List<mock.Operation>>((ref) {
  final period = ref.watch(activePeriodProvider);
  final repository = ref.watch(operationsRepositoryProvider);
  final categoriesRepository = ref.watch(categoriesRepositoryProvider);

  repository.seedDefaultsIfNeeded(period.id, categoriesRepository);
  return repository.getOperations(period.id);
});

class PeriodSummary {
  PeriodSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.totalSavings,
    required this.remainingBudget,
    required this.remainingPerDay,
    required this.todaySpent,
    required this.todayBudget,
    required this.dailyProgress,
  });

  final double totalIncome;
  final double totalExpense;
  final double totalSavings;
  final double remainingBudget;
  final double remainingPerDay;
  final double todaySpent;
  final double todayBudget;
  final double dailyProgress;
}

final periodSummaryProvider = Provider<PeriodSummary>((ref) {
  final period = ref.watch(activePeriodProvider);
  final repository = ref.watch(operationsRepositoryProvider);

  final totalIncome =
      repository.totalForType(period.id, mock.OperationType.income);
  final totalExpense =
      repository.totalForType(period.id, mock.OperationType.expense);
  final totalSavings =
      repository.totalForType(period.id, mock.OperationType.savings);
  final remainingBudget = totalIncome - totalExpense - totalSavings;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final periodEnd = DateTime(period.end.year, period.end.month, period.end.day);
  final periodStart =
      DateTime(period.start.year, period.start.month, period.start.day);
  int daysLeft;
  if (today.isBefore(periodStart)) {
    daysLeft = periodEnd.difference(periodStart).inDays + 1;
  } else if (today.isAfter(periodEnd)) {
    daysLeft = 1;
  } else {
    daysLeft = periodEnd.difference(today).inDays + 1;
  }

  final todayBudget =
      daysLeft > 0 ? remainingBudget / daysLeft : remainingBudget;
  final todaySpent = repository.spentOnDate(period.id, now);
  final normalizedBudget = todayBudget <= 0 ? 1.0 : todayBudget;
  final progress = (todaySpent / normalizedBudget).clamp(0.0, 1.0);

  return PeriodSummary(
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    totalSavings: totalSavings,
    remainingBudget: remainingBudget,
    remainingPerDay:
        daysLeft > 0 ? remainingBudget / daysLeft : remainingBudget,
    todaySpent: todaySpent,
    todayBudget: todayBudget,
    dailyProgress: progress,
  );
});

final hasOperationsProvider = Provider<bool>((ref) {
  final operations = ref.watch(activePeriodOperationsProvider);
  return operations.isNotEmpty;
});

final necessityLabelsProvider = StateProvider<List<String>>((ref) => const [
      'Необходимо',
      'Вынуждено',
      'Эмоции',
    ]);
