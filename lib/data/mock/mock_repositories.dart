import 'dart:math';

import 'package:flutter/material.dart';

import 'mock_models.dart';

class BudgetPeriodRepository {
  BudgetPeriodRepository() {
    final now = DateTime.now();
    final firstHalfStart = DateTime(now.year, now.month, 1);
    final firstHalfEnd = DateTime(now.year, now.month, 15);
    final secondHalfStart = DateTime(now.year, now.month, 16);
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final secondHalfEnd = DateTime(now.year, now.month, lastDay);

    _periods = [
      BudgetPeriod(
        id: 'period-first-half',
        title: '1-15 ${_monthName(now.month)}',
        start: firstHalfStart,
        end: firstHalfEnd,
      ),
      BudgetPeriod(
        id: 'period-second-half',
        title: '16-$lastDay ${_monthName(now.month)}',
        start: secondHalfStart,
        end: secondHalfEnd,
      ),
    ];
    _activePeriodId = _periods.first.id;
  }

  late final List<BudgetPeriod> _periods;
  late String _activePeriodId;

  List<BudgetPeriod> get periods => List.unmodifiable(_periods);

  BudgetPeriod get activePeriod =>
      _periods.firstWhere((period) => period.id == _activePeriodId);

  void setActive(String id) {
    if (_periods.any((period) => period.id == id)) {
      _activePeriodId = id;
    }
  }

  String _monthName(int month) {
    const names = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return names[month - 1];
  }
}

class AccountsRepository {
  final List<Account> _accounts = [
    Account(
      id: 'account-main',
      name: 'Основной счёт',
      balance: 23500,
      color: Colors.indigo,
    ),
    Account(
      id: 'account-savings',
      name: 'Накопительный',
      balance: 120000,
      color: Colors.teal,
    ),
  ];

  List<Account> getAccounts() => List.unmodifiable(_accounts);
}

class CategoriesRepository {
  CategoriesRepository() {
    _categories = [
      Category(
        id: 'cat-salary',
        name: 'Зарплата',
        type: OperationType.income,
        icon: Icons.work,
      ),
      Category(
        id: 'cat-freelance',
        name: 'Фриланс',
        type: OperationType.income,
        icon: Icons.laptop_mac,
      ),
      Category(
        id: 'cat-groceries',
        name: 'Продукты',
        type: OperationType.expense,
        icon: Icons.shopping_basket,
      ),
      Category(
        id: 'cat-transport',
        name: 'Транспорт',
        type: OperationType.expense,
        icon: Icons.directions_bus,
      ),
      Category(
        id: 'cat-fun',
        name: 'Развлечения',
        type: OperationType.expense,
        icon: Icons.celebration,
      ),
      Category(
        id: 'cat-education',
        name: 'Обучение',
        type: OperationType.savings,
        icon: Icons.school,
      ),
      Category(
        id: 'cat-emergency',
        name: 'Резерв',
        type: OperationType.savings,
        icon: Icons.security,
      ),
    ];
  }

  late final List<Category> _categories;

  List<Category> getByType(OperationType type) {
    return _categories.where((category) => category.type == type).toList();
  }

  Category? getById(String id) {
    return _categories.firstWhere(
      (category) => category.id == id,
      orElse: () => _categories.first,
    );
  }
}

class OperationsRepository {
  final Map<String, List<Operation>> _operationsByPeriod = {};
  int _idCounter = 0;

  List<Operation> getOperations(String periodId) {
    return List.unmodifiable(_operationsByPeriod[periodId] ?? []);
  }

  void seed(String periodId, List<Operation> operations) {
    _operationsByPeriod[periodId] = [...operations];
  }

  Operation addOperation({
    required String periodId,
    required double amount,
    required OperationType type,
    required Category category,
    required DateTime date,
    String? note,
    String? accountId,
    String? plannedId,
  }) {
    final operation = Operation(
      id: 'operation-${_idCounter++}',
      amount: amount,
      type: type,
      category: category,
      date: date,
      note: note,
      accountId: accountId,
      plannedId: plannedId,
    );
    final list = _operationsByPeriod.putIfAbsent(periodId, () => []);
    list.insert(0, operation);
    return operation;
  }

  void removeOperation(String periodId, String operationId) {
    final list = _operationsByPeriod[periodId];
    if (list == null) {
      return;
    }
    list.removeWhere((operation) => operation.id == operationId);
  }

  double totalAmount(
    String periodId,
    bool Function(Operation operation) predicate,
  ) {
    return getOperations(periodId)
        .where(predicate)
        .fold<double>(0, (previousValue, operation) => previousValue + operation.amount);
  }

  double totalForType(String periodId, OperationType type) {
    return totalAmount(periodId, (operation) => operation.type == type);
  }

  double spentOnDate(String periodId, DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    return totalAmount(periodId, (operation) {
      final normalized = DateTime(operation.date.year, operation.date.month, operation.date.day);
      return normalized == target && operation.type == OperationType.expense;
    });
  }

  void seedDefaultsIfNeeded(String periodId, CategoriesRepository categoriesRepository) {
    if (_operationsByPeriod.containsKey(periodId)) {
      return;
    }
    final now = DateTime.now();
    final random = Random(4);
    final groceries = categoriesRepository.getByType(OperationType.expense).first;
    final transport = categoriesRepository.getByType(OperationType.expense)[1];
    final salary = categoriesRepository.getByType(OperationType.income).first;
    final fun = categoriesRepository.getByType(OperationType.expense)[2];

    seed(periodId, [
      Operation(
        id: 'operation-${_idCounter++}',
        amount: 50000,
        type: OperationType.income,
        category: salary,
        date: now.subtract(const Duration(days: 10)),
        note: 'Оклад за месяц',
      ),
      Operation(
        id: 'operation-${_idCounter++}',
        amount: 1450,
        type: OperationType.expense,
        category: groceries,
        date: now.subtract(const Duration(days: 1)),
        note: 'Продукты у дома',
      ),
      Operation(
        id: 'operation-${_idCounter++}',
        amount: 600,
        type: OperationType.expense,
        category: transport,
        date: now,
        note: 'Такси до офиса',
      ),
      Operation(
        id: 'operation-${_idCounter++}',
        amount: 2500.0 + random.nextInt(500).toDouble(),
        type: OperationType.expense,
        category: fun,
        date: now.subtract(const Duration(days: 3)),
        note: 'Кино + ужин',
      ),
    ]);
  }
}
