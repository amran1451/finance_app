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

final isSheetOpenProvider = StateProvider<bool>((_) => false);

final necessityLabelsProvider = StateProvider<List<String>>((ref) => const [
      'Необходимо',
      'Вынуждено',
      'Эмоции',
    ]);
