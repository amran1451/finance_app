import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/category.dart';

abstract class CategoriesRepository {
  Future<List<Category>> getAll();

  Future<Category?> getById(int id);

  Future<List<Category>> getByType(CategoryType type);

  Future<int> create(Category category);

  Future<void> update(Category category);

  Future<void> delete(int id);

  Future<List<Category>> groupsByType(CategoryType type);

  Future<List<Category>> childrenOf(int groupId);

  Future<void> restoreDefaults();
}

class SqliteCategoriesRepository implements CategoriesRepository {
  SqliteCategoriesRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> create(Category category) async {
    final db = await _db;
    final values = category.toMap()..remove('id');
    return db.insert('categories', values);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await db.update(
      'categories',
      {'parent_id': null},
      where: 'parent_id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<Category>> getAll() async {
    final db = await _db;
    final rows = await db.query('categories', orderBy: 'name');
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<Category?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Category.fromMap(rows.first);
  }

  @override
  Future<List<Category>> getByType(CategoryType type) async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      where: 'type = ? AND is_group = 0',
      whereArgs: [_typeToString(type)],
      orderBy: 'name',
    );
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<List<Category>> groupsByType(CategoryType type) async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      where: 'type = ? AND is_group = 1',
      whereArgs: [_typeToString(type)],
      orderBy: 'name',
    );
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<List<Category>> childrenOf(int groupId) async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      where: 'parent_id = ? AND is_group = 0',
      whereArgs: [groupId],
      orderBy: 'name',
    );
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<void> restoreDefaults() async {
    final db = await _db;
    await db.transaction((txn) async {
      final defaultGroups = _defaultGroups();
      for (final group in defaultGroups) {
        final groupId = await _ensureCategory(
          txn,
          type: group.type,
          name: group.name,
          isGroup: true,
        );
        for (final child in group.children) {
          await _ensureCategory(
            txn,
            type: group.type,
            name: child,
            parentId: groupId,
          );
        }
      }

      for (final entry in _defaultStandalone()) {
        await _ensureCategory(
          txn,
          type: entry.type,
          name: entry.name,
        );
      }
    });
  }

  @override
  Future<void> update(Category category) async {
    final id = category.id;
    if (id == null) {
      throw ArgumentError('Category id is required for update');
    }
    final db = await _db;
    await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> _ensureCategory(
    DatabaseExecutor executor, {
    required CategoryType type,
    required String name,
    bool isGroup = false,
    int? parentId,
  }) async {
    final whereBuffer = StringBuffer('type = ? AND name = ?');
    final args = <Object?>[_typeToString(type), name];
    if (parentId == null) {
      whereBuffer.write(' AND parent_id IS NULL');
    } else {
      whereBuffer.write(' AND parent_id = ?');
      args.add(parentId);
    }
    whereBuffer.write(' AND is_group = ?');
    args.add(isGroup ? 1 : 0);

    final existing = await executor.query(
      'categories',
      columns: ['id'],
      where: whereBuffer.toString(),
      whereArgs: args,
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    final values = <String, Object?>{
      'type': _typeToString(type),
      'name': name,
      'is_group': isGroup ? 1 : 0,
      'parent_id': parentId,
      'archived': 0,
    };
    return executor.insert('categories', values);
  }

  String _typeToString(CategoryType type) {
    switch (type) {
      case CategoryType.income:
        return 'income';
      case CategoryType.expense:
        return 'expense';
      case CategoryType.saving:
        return 'saving';
    }
  }
}

class _DefaultCategoryGroup {
  const _DefaultCategoryGroup(
    this.type,
    this.name,
    this.children,
  );

  final CategoryType type;
  final String name;
  final List<String> children;
}

class _DefaultCategoryEntry {
  const _DefaultCategoryEntry(this.type, this.name);

  final CategoryType type;
  final String name;
}

List<_DefaultCategoryGroup> _defaultGroups() {
  return const [
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Еда',
      ['Магазины', 'Рестораны', 'Кафе', 'Доставка', 'Перекусы'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Транспорт',
      ['Общественный', 'Такси', 'Топливо', 'Парковка'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Дом',
      [
        'Аренда',
        'Коммунальные',
        'Интернет/Связь',
        'Обслуживание/Ремонт',
      ],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Здоровье',
      ['Аптека', 'Врач/Исследования', 'Страховка'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Личное/Уход',
      ['Косметика', 'Парикмахер/Салон'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Образование',
      ['Курсы', 'Книги/Материалы'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Развлечения',
      ['Кино/Театр', 'Игры', 'Прочее'],
    ),
  ];
}

List<_DefaultCategoryEntry> _defaultStandalone() {
  return const [
    _DefaultCategoryEntry(CategoryType.expense, 'Подписки'),
    _DefaultCategoryEntry(CategoryType.expense, 'Одежда/Обувь'),
    _DefaultCategoryEntry(CategoryType.expense, 'Подарки'),
    _DefaultCategoryEntry(CategoryType.expense, 'Питомцы'),
    _DefaultCategoryEntry(CategoryType.expense, 'Электроника'),
    _DefaultCategoryEntry(CategoryType.expense, 'Налоги/Сборы'),
    _DefaultCategoryEntry(CategoryType.expense, 'Другое'),
    _DefaultCategoryEntry(CategoryType.income, 'Зарплата'),
    _DefaultCategoryEntry(CategoryType.income, 'Аванс'),
    _DefaultCategoryEntry(CategoryType.income, 'Премии/Бонусы'),
    _DefaultCategoryEntry(CategoryType.income, 'Фриланс/Подработка'),
    _DefaultCategoryEntry(CategoryType.income, 'Подарки'),
    _DefaultCategoryEntry(CategoryType.income, 'Проценты/Кэшбэк'),
    _DefaultCategoryEntry(CategoryType.income, 'Другое'),
    _DefaultCategoryEntry(CategoryType.saving, 'Резервный фонд'),
    _DefaultCategoryEntry(CategoryType.saving, 'Крупные цели'),
    _DefaultCategoryEntry(CategoryType.saving, 'Короткие цели'),
  ];
}
