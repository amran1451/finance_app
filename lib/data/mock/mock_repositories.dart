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

  List<Account> listActive() => List.unmodifiable(_accounts);
}

class CategoriesRepository extends ChangeNotifier {
  CategoriesRepository() {
    _categories = [];
    _seedDefaultTree();
  }

  late final List<Category> _categories;
  int _idCounter = 0;

  List<Category> getByType(CategoryType type) {
    return _categories
        .where((category) => category.type == type && !category.isGroup)
        .toList();
  }

  Category? getById(String id) {
    try {
      return _categories.firstWhere((category) => category.id == id);
    } catch (_) {
      return null;
    }
  }

  void addGroup({
    required CategoryType type,
    required String name,
  }) {
    final category = Category(
      id: 'group-${_idCounter++}',
      type: type,
      name: name,
      icon: Icons.folder,
      parentId: null,
      isGroup: true,
    );
    _categories.add(category);
    notifyListeners();
  }

  void addCategory({
    required CategoryType type,
    required String name,
    String? parentId,
  }) {
    final category = Category(
      id: 'cat-custom-${_idCounter++}',
      type: type,
      name: name,
      icon: _defaultIconForType(type),
      parentId: parentId,
      isGroup: false,
    );
    _categories.add(category);
    notifyListeners();
  }

  void updateCategory(
    String id, {
    String? name,
    String? parentId,
  }) {
    final index = _categories.indexWhere((element) => element.id == id);
    if (index == -1) {
      return;
    }
    final current = _categories[index];
    _categories[index] = Category(
      id: current.id,
      type: current.type,
      name: name ?? current.name,
      icon: current.icon,
      parentId: parentId ?? current.parentId,
      isGroup: current.isGroup,
    );
    notifyListeners();
  }

  void removeCategory(String id) {
    final target = getById(id);
    if (target == null) {
      return;
    }

    if (target.isGroup) {
      _categories.removeWhere(
        (category) => category.id == id || category.parentId == id,
      );
    } else {
      _categories.removeWhere((category) => category.id == id);
    }
    notifyListeners();
  }

  List<Category> groupsByType(CategoryType type) {
    return _categories
        .where((category) => category.type == type && category.isGroup)
        .toList();
  }

  List<Category> childrenOf(String groupId) {
    return _categories
        .where((category) => category.parentId == groupId && !category.isGroup)
        .toList();
  }

  IconData _defaultIconForType(CategoryType type) {
    switch (type) {
      case OperationType.income:
        return Icons.trending_up;
      case OperationType.expense:
        return Icons.trending_down;
      case OperationType.savings:
        return Icons.savings;
    }
  }

  void _seedDefaultTree() {
    if (_categories.isNotEmpty) {
      return;
    }

    var seedCounter = 0;
    String nextId(String prefix) => '$prefix-${seedCounter++}';

    void addGroupWithChildren(
      CategoryType type,
      String name,
      List<String> children,
    ) {
      final groupId = nextId('grp-${type.name}');
      _categories.add(
        Category(
          id: groupId,
          type: type,
          name: name,
          icon: Icons.folder,
          parentId: null,
          isGroup: true,
        ),
      );
      for (final child in children) {
        _categories.add(
          Category(
            id: nextId('cat-${type.name}'),
            type: type,
            name: child,
            icon: _defaultIconForType(type),
            parentId: groupId,
            isGroup: false,
          ),
        );
      }
    }

    void addStandalone(
      CategoryType type,
      String name,
    ) {
      _categories.add(
        Category(
          id: nextId('cat-${type.name}'),
          type: type,
          name: name,
          icon: _defaultIconForType(type),
          parentId: null,
          isGroup: false,
        ),
      );
    }

    addGroupWithChildren(
      OperationType.expense,
      'Еда',
      const ['Магазины', 'Рестораны', 'Кафе', 'Доставка', 'Перекусы'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Транспорт',
      const ['Общественный', 'Такси', 'Топливо', 'Парковка'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Дом',
      const ['Аренда', 'Коммунальные', 'Интернет/Связь', 'Обслуживание/Ремонт'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Здоровье',
      const ['Аптека', 'Врач/Исследования', 'Страховка'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Личное/Уход',
      const ['Косметика', 'Парикмахер/Салон'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Образование',
      const ['Курсы', 'Книги/Материалы'],
    );
    addGroupWithChildren(
      OperationType.expense,
      'Развлечения',
      const ['Кино/Театр', 'Игры', 'Прочее'],
    );

    const expenseStandalone = [
      'Подписки',
      'Одежда/Обувь',
      'Подарки',
      'Питомцы',
      'Электроника',
      'Налоги/Сборы',
      'Другое',
    ];
    for (final name in expenseStandalone) {
      addStandalone(OperationType.expense, name);
    }

    const incomeCategories = [
      'Зарплата',
      'Аванс',
      'Премии/Бонусы',
      'Фриланс/Подработка',
      'Подарки',
      'Проценты/Кэшбэк',
      'Другое',
    ];
    for (final name in incomeCategories) {
      addStandalone(OperationType.income, name);
    }

    const savingCategories = [
      'Резервный фонд',
      'Крупные цели',
      'Короткие цели',
    ];
    for (final name in savingCategories) {
      addStandalone(OperationType.savings, name);
    }

    _idCounter = seedCounter;
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
    Category _findCategory(CategoryType type, String name) {
      return categoriesRepository
          .getByType(type)
          .firstWhere((category) => category.name == name);
    }

    final groceries = _findCategory(OperationType.expense, 'Магазины');
    final transport = _findCategory(OperationType.expense, 'Такси');
    final salary = _findCategory(OperationType.income, 'Зарплата');
    final fun = _findCategory(OperationType.expense, 'Кино/Театр');

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
