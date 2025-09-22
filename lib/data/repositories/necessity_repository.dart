import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class NecessityLabel {
  const NecessityLabel({
    required this.id,
    required this.name,
    this.color,
    required this.sortOrder,
    required this.archived,
  });

  final int id;
  final String name;
  final String? color;
  final int sortOrder;
  final bool archived;

  NecessityLabel copyWith({
    int? id,
    String? name,
    Object? color = _unset,
    int? sortOrder,
    bool? archived,
  }) {
    return NecessityLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color == _unset ? this.color : color as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  static const Object _unset = Object();
}

abstract class NecessityRepository {
  Future<List<NecessityLabel>> list({bool includeArchived = false});
  Future<NecessityLabel> create({
    required String name,
    String? color,
    int? sortOrder,
  });
  Future<void> update(int id, {String? name, String? color});
  Future<void> archive(int id, {bool archived = true});
  Future<void> reorder(List<int> orderedIds);
  Future<NecessityLabel?> findById(int id);
}

class NecessityRepositorySqlite implements NecessityRepository {
  NecessityRepositorySqlite({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<NecessityLabel?> findById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'necessity_labels',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  @override
  Future<List<NecessityLabel>> list({bool includeArchived = false}) async {
    final db = await _db;
    final rows = await db.query(
      'necessity_labels',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(_mapRow).toList();
  }

  @override
  Future<NecessityLabel> create({
    required String name,
    String? color,
    int? sortOrder,
  }) async {
    final db = await _db;
    final resolvedSortOrder =
        sortOrder ?? await _nextSortOrder(db, includeArchived: true);
    final id = await db.insert('necessity_labels', {
      'name': name,
      'color': color,
      'sort_order': resolvedSortOrder,
      'archived': 0,
    });
    return NecessityLabel(
      id: id,
      name: name,
      color: color,
      sortOrder: resolvedSortOrder,
      archived: false,
    );
  }

  @override
  Future<void> update(int id, {String? name, String? color}) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (name != null) {
      values['name'] = name;
    }
    if (color != null) {
      values['color'] = color;
    }
    if (values.isEmpty) {
      return;
    }
    await db.update(
      'necessity_labels',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> archive(int id, {bool archived = true}) async {
    final db = await _db;
    await db.update(
      'necessity_labels',
      {'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> reorder(List<int> orderedIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'necessity_labels',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<int> _nextSortOrder(Database db, {bool includeArchived = false}) async {
    final whereClause = includeArchived ? null : 'archived = 0';
    final rows = await db.query(
      'necessity_labels',
      columns: ['MAX(sort_order) as max_order'],
      where: whereClause,
    );
    if (rows.isEmpty) {
      return 0;
    }
    final maxValue = rows.first['max_order'];
    if (maxValue == null) {
      return 0;
    }
    return _readInt(maxValue) + 1;
  }

  NecessityLabel _mapRow(Map<String, Object?> row) {
    return NecessityLabel(
      id: _readInt(row['id']),
      name: row['name'] as String? ?? '',
      color: row['color'] as String?,
      sortOrder: _readInt(row['sort_order']),
      archived: _readInt(row['archived']) != 0,
    );
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
