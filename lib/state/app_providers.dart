import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bootstrap/app_bootstrapper.dart';
import '../data/db/app_database.dart';
import '../data/models/account.dart' as account_models;
import '../data/mock/mock_models.dart' as mock;
import '../data/mock/mock_repositories.dart' as mock_repo;
import '../data/models/category.dart' as category_models;
import '../data/repositories/accounts_repository.dart' as accounts_repo;
import '../data/repositories/categories_repository.dart' as categories_repo;
import '../data/repositories/payouts_repository.dart' as payouts_repo;
import '../data/repositories/necessity_repository.dart' as necessity_repo;
import '../data/repositories/reason_repository.dart' as reason_repo;
import '../data/repositories/settings_repository.dart' as settings_repo;
import '../data/repositories/transactions_repository.dart' as transactions_repo;
import 'db_refresh.dart';

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

final accountsDbProvider =
    FutureProvider<List<account_models.Account>>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(accountsRepoProvider);
  return repository.getAll();
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

final necessityRepoProvider = Provider<necessity_repo.NecessityRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return necessity_repo.NecessityRepositorySqlite(database: database);
});

final reasonRepoProvider = Provider<reason_repo.ReasonRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return reason_repo.ReasonRepositorySqlite(database: database);
});

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
