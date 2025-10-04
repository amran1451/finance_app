import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class ReasonLabel {
  const ReasonLabel({
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

  ReasonLabel copyWith({
    int? id,
    String? name,
    Object? color = _unset,
    int? sortOrder,
    bool? archived,
  }) {
    return ReasonLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color == _unset ? this.color : color as String?,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  static const Object _unset = Object();
}

abstract class ReasonRepository {
  Future<List<ReasonLabel>> list({bool includeArchived = false});

  Future<ReasonLabel> create({
    required String name,
    String? color,
    int? sortOrder,
    DatabaseExecutor? executor,
  });

  Future<void> update(int id,
      {String? name, String? color, DatabaseExecutor? executor});

  Future<void> archive(int id,
      {bool archived = true, DatabaseExecutor? executor});

  Future<void> reorder(List<int> orderedIds, {DatabaseExecutor? executor});

  Future<ReasonLabel?> findById(int id);
}

class ReasonRepositorySqlite implements ReasonRepository {
  ReasonRepositorySqlite({AppDatabase? database})
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
  Future<ReasonLabel?> findById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'reason_labels',
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
  Future<List<ReasonLabel>> list({bool includeArchived = false}) async {
    final db = await _db;
    final rows = await db.query(
      'reason_labels',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(_mapRow).toList();
  }

  @override
  Future<ReasonLabel> create({
    required String name,
    String? color,
    int? sortOrder,
    DatabaseExecutor? executor,
  }) async {
    return _runWrite<ReasonLabel>(
      (db) async {
        final resolvedSortOrder =
            sortOrder ?? await _nextSortOrder(db, includeArchived: true);
        final id = await db.insert('reason_labels', {
          'name': name,
          'color': color,
          'sort_order': resolvedSortOrder,
          'archived': 0,
        });
        return ReasonLabel(
          id: id,
          name: name,
          color: color,
          sortOrder: resolvedSortOrder,
          archived: false,
        );
      },
      executor: executor,
      debugContext: 'reason.create',
    );
  }

  @override
  Future<void> update(int id,
      {String? name, String? color, DatabaseExecutor? executor}) async {
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
    await _runWrite<void>(
      (db) async {
        await db.update(
          'reason_labels',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'reason.update',
    );
  }

  @override
  Future<void> archive(int id,
      {bool archived = true, DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (db) async {
        await db.update(
          'reason_labels',
          {'archived': archived ? 1 : 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'reason.archive',
    );
  }

  @override
  Future<void> reorder(List<int> orderedIds,
      {DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(
            'reason_labels',
            {'sort_order': i},
            where: 'id = ?',
            whereArgs: [orderedIds[i]],
          );
        }
      },
      executor: executor,
      debugContext: 'reason.reorder',
    );
  }

  Future<int> _nextSortOrder(DatabaseExecutor db,
      {bool includeArchived = false}) async {
    final whereClause = includeArchived ? null : 'archived = 0';
    final rows = await db.query(
      'reason_labels',
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

  ReasonLabel _mapRow(Map<String, Object?> row) {
    return ReasonLabel(
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
