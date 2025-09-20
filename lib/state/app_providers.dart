import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock/mock_models.dart';
import '../data/mock/mock_repositories.dart';

final budgetPeriodRepositoryProvider = Provider<BudgetPeriodRepository>((ref) {
  return BudgetPeriodRepository();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class ActivePeriodNotifier extends StateNotifier<BudgetPeriod> {
  ActivePeriodNotifier(this._repository) : super(_repository.activePeriod);

  final BudgetPeriodRepository _repository;

  void setActive(String id) {
    _repository.setActive(id);
    state = _repository.activePeriod;
  }
}

final activePeriodProvider =
    StateNotifierProvider<ActivePeriodNotifier, BudgetPeriod>((ref) {
  final repository = ref.watch(budgetPeriodRepositoryProvider);
  return ActivePeriodNotifier(repository);
});

final periodsProvider = Provider<List<BudgetPeriod>>((ref) {
  final repository = ref.watch(budgetPeriodRepositoryProvider);
  return repository.periods;
});

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository();
});

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository();
});

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository();
});

final accountsProvider = Provider<List<Account>>((ref) {
  final repository = ref.watch(accountsRepositoryProvider);
  return repository.getAccounts();
});

final activePeriodOperationsProvider = Provider<List<Operation>>((ref) {
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

  final totalIncome = repository.totalForType(period.id, OperationType.income);
  final totalExpense = repository.totalForType(period.id, OperationType.expense);
  final totalSavings = repository.totalForType(period.id, OperationType.savings);
  final remainingBudget = totalIncome - totalExpense - totalSavings;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final periodEnd = DateTime(period.end.year, period.end.month, period.end.day);
  final periodStart = DateTime(period.start.year, period.start.month, period.start.day);
  int daysLeft;
  if (today.isBefore(periodStart)) {
    daysLeft = periodEnd.difference(periodStart).inDays + 1;
  } else if (today.isAfter(periodEnd)) {
    daysLeft = 1;
  } else {
    daysLeft = periodEnd.difference(today).inDays + 1;
  }

  final todayBudget = daysLeft > 0 ? remainingBudget / daysLeft : remainingBudget;
  final todaySpent = repository.spentOnDate(period.id, now);
  final normalizedBudget = todayBudget <= 0 ? 1.0 : todayBudget;
  final progress = (todaySpent / normalizedBudget).clamp(0.0, 1.0);

  return PeriodSummary(
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    totalSavings: totalSavings,
    remainingBudget: remainingBudget,
    remainingPerDay: daysLeft > 0 ? remainingBudget / daysLeft : remainingBudget,
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
