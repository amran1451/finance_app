import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/category.dart';
import '../seed/seed_data.dart';

abstract class CategoriesRepository {
  Future<List<Category>> getAll();

  Future<Category?> getById(int id);

  Future<List<Category>> getByType(CategoryType type);

  Future<int> create(Category category, {DatabaseExecutor? executor});

  Future<void> update(Category category, {DatabaseExecutor? executor});

  Future<void> delete(int id, {DatabaseExecutor? executor});

  Future<void> bulkMove(List<int> ids, int? parentId, {DatabaseExecutor? executor});

  Future<List<Category>> groupsByType(CategoryType type);

  Future<List<Category>> childrenOf(int groupId);

  Future<void> restoreDefaults({DatabaseExecutor? executor});
}

class SqliteCategoriesRepository implements CategoriesRepository {
  SqliteCategoriesRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  Future<T> _runWrite<T>(
    Future<T> Function(DatabaseExecutor executor) action, {
    DatabaseExecutor? executor,
    String? debugContext,
  }) {
    if (executor != null) {
      return action(executor);
    }
    return _database.runInWriteTransaction<T>(
      (txn) => action(txn),
      debugContext: debugContext,
    );
  }

  @override
  Future<int> create(Category category, {DatabaseExecutor? executor}) async {
    final values = category.toMap()..remove('id');
    return _runWrite<int>(
      (db) => db.insert('categories', values),
      executor: executor,
      debugContext: 'categories.create',
    );
  }

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (db) async {
        await db.delete('categories', where: 'id = ?', whereArgs: [id]);
        await db.update(
          'categories',
          {'parent_id': null},
          where: 'parent_id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'categories.delete',
    );
  }

  @override
  Future<void> bulkMove(List<int> ids, int? parentId,
      {DatabaseExecutor? executor}) async {
    if (ids.isEmpty) {
      return;
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    await _runWrite<void>(
      (db) async {
        await db.update(
          'categories',
          {'parent_id': parentId},
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
      },
      executor: executor,
      debugContext: 'categories.bulkMove',
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
  Future<void> restoreDefaults({DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (txn) async {
        await SeedData.seedCategories(txn);
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

      for (final entry in _defaultStandalone()) {
        await _ensureCategory(
          txn,
          type: entry.type,
          name: entry.name,
          cache: cache,
        );
      }
      },
      executor: executor,
      debugContext: 'categories.restoreDefaults',
    );
  }

  @override
  Future<void> update(Category category, {DatabaseExecutor? executor}) async {
    final id = category.id;
    if (id == null) {
      throw ArgumentError('Category id is required for update');
    }
    await _runWrite<void>(
      (db) async {
        await db.update(
          'categories',
          category.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'categories.update',
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

class _DefaultCategoryEntry {
  const _DefaultCategoryEntry(this.type, this.name);

  final CategoryType type;
  final String name;
}

List<_DefaultCategoryEntry> _defaultStandalone() {
  return const [
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
