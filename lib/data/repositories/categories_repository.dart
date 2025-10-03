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

  Future<void> bulkMove(List<int> ids, int? parentId);

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
  Future<void> bulkMove(List<int> ids, int? parentId) async {
    if (ids.isEmpty) {
      return;
    }
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'categories',
      {'parent_id': parentId},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
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
      final existingRows = await txn.query(
        'categories',
        columns: ['id', 'type', 'name', 'is_group', 'parent_id'],
      );
      final cache = <_CategoryKey, int>{};
      for (final row in existingRows) {
        final id = row['id'] as int?;
        final type = row['type'] as String?;
        final name = row['name'] as String?;
        if (id == null || type == null || name == null) {
          continue;
        }
        final isGroup = ((row['is_group'] as int?) ?? 0) != 0;
        final parentId = row['parent_id'] as int?;
        cache[_CategoryKey(
          type: type,
          name: name,
          parentId: parentId,
          isGroup: isGroup,
        )] = id;
      }

      final defaultGroups = _defaultGroups();
      for (final group in defaultGroups) {
        final groupId = await _ensureCategory(
          txn,
          type: group.type,
          name: group.name,
          isGroup: true,
          cache: cache,
        );
        for (final child in group.children) {
          await _ensureCategory(
            txn,
            type: group.type,
            name: child,
            parentId: groupId,
            cache: cache,
          );
        }
      }

      for (final entry in _defaultStandalone()) {
        await _ensureCategory(
          txn,
          type: entry.type,
          name: entry.name,
          cache: cache,
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
    Map<_CategoryKey, int>? cache,
  }) async {
    final typeValue = _typeToString(type);
    final key = _CategoryKey(
      type: typeValue,
      name: name,
      parentId: parentId,
      isGroup: isGroup,
    );

    if (cache != null) {
      final cachedId = cache[key];
      if (cachedId != null) {
        return cachedId;
      }
    } else {
      final whereBuffer = StringBuffer('type = ? AND name = ?');
      final args = <Object?>[typeValue, name];
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
        final id = existing.first['id'] as int;
        cache?[key] = id;
        return id;
      }
    }

    final values = <String, Object?>{
      'type': typeValue,
      'name': name,
      'is_group': isGroup ? 1 : 0,
      'parent_id': parentId,
      'archived': 0,
    };
    final id = await executor.insert('categories', values);
    cache?[key] = id;
    return id;
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

class _CategoryKey {
  const _CategoryKey({
    required this.type,
    required this.name,
    required this.parentId,
    required this.isGroup,
  });

  final String type;
  final String name;
  final int? parentId;
  final bool isGroup;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _CategoryKey &&
        other.type == type &&
        other.name == name &&
        other.parentId == parentId &&
        other.isGroup == isGroup;
  }

  @override
  int get hashCode => Object.hash(type, name, parentId, isGroup);
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
      [
        'Продукты',
        'Перекус',
        'Сигареты',
        'Доставка',
        'Кафе',
        'Рестораны',
      ],
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
        'Интернет',
        'Ремонт',
      ],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Здоровье',
      ['Аптека', 'Врач', 'Страховка'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Личное/Уход',
      ['Косметика', 'Парикмахер'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Образование',
      ['Курсы', 'Книги'],
    ),
    _DefaultCategoryGroup(
      CategoryType.expense,
      'Развлечения',
      ['Кино', 'Игры', 'Прочее'],
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
    _DefaultCategoryEntry(CategoryType.saving, 'Цели'),
  ];
}
