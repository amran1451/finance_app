import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class PlannedMaster {
  const PlannedMaster({
    this.id,
    required this.type,
    required this.title,
    this.defaultAmountMinor,
    this.categoryId,
    this.note,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String type;
  final String title;
  final int? defaultAmountMinor;
  final int? categoryId;
  final String? note;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlannedMaster copyWith({
    int? id,
    String? type,
    String? title,
    Object? defaultAmountMinor = _sentinel,
    Object? categoryId = _sentinel,
    Object? note = _sentinel,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlannedMaster(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      defaultAmountMinor: defaultAmountMinor == _sentinel
          ? this.defaultAmountMinor
          : defaultAmountMinor as int?,
      categoryId: categoryId == _sentinel ? this.categoryId : categoryId as int?,
      note: note == _sentinel ? this.note : note as String?,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PlannedMaster.fromMap(Map<String, Object?> map) {
    return PlannedMaster(
      id: map['id'] as int?,
      type: (map['type'] as String? ?? '').toLowerCase(),
      title: map['title'] as String? ?? '',
      defaultAmountMinor: map['default_amount_minor'] as int?,
      categoryId: map['category_id'] as int?,
      note: map['note'] as String?,
      archived: (map['archived'] as int? ?? 0) != 0,
      createdAt: _parseDateTime(map['created_at'] as String?),
      updatedAt: _parseDateTime(map['updated_at'] as String?),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'default_amount_minor': defaultAmountMinor,
      'category_id': categoryId,
      'note': note,
      'archived': archived ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static const Object _sentinel = Object();

  static DateTime _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    }
    return DateTime.tryParse(raw) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
  }
}

const Object _updateOptional = Object();

abstract class PlannedMasterRepository {
  Future<List<PlannedMaster>> list({bool includeArchived = false});

  Future<PlannedMaster?> getById(int id);

  Future<int> create({
    required String type,
    required String title,
    int? defaultAmountMinor,
    int? categoryId,
    String? note,
  });

  Future<void> update(
    int id, {
    String? type,
    String? title,
    Object? defaultAmountMinor = _updateOptional,
    Object? categoryId = _updateOptional,
    Object? note = _updateOptional,
    bool? archived,
  });

  Future<void> delete(int id);
}

class SqlitePlannedMasterRepository implements PlannedMasterRepository {
  SqlitePlannedMasterRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static const Object _sentinel = Object();
  static const Set<String> _allowedTypes = {'expense', 'income', 'saving'};

  Future<Database> get _db async => _database.database;

  @override
  Future<int> create({
    required String type,
    required String title,
    int? defaultAmountMinor,
    int? categoryId,
    String? note,
  }) async {
    final db = await _db;
    final normalizedType = _normalizeType(type);
    final values = <String, Object?>{
      'type': normalizedType,
      'title': title,
      'default_amount_minor': defaultAmountMinor,
      'category_id': categoryId,
      'note': note,
    };
    return db.insert('planned_master', values);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    final linked = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM transactions WHERE planned_id = ?',
      [id],
    );
    final count = linked.isNotEmpty ? _readInt(linked.first['cnt']) : 0;
    if (count > 0) {
      throw StateError('Cannot delete planned master with existing instances');
    }
    await db.delete('planned_master', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<PlannedMaster?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'planned_master',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PlannedMaster.fromMap(rows.first);
  }

  @override
  Future<List<PlannedMaster>> list({bool includeArchived = false}) async {
    final db = await _db;
    final rows = await db.query(
      'planned_master',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'archived ASC, title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(PlannedMaster.fromMap).toList();
  }

  @override
  Future<void> update(
    int id, {
    String? type,
    String? title,
    Object? defaultAmountMinor = _updateOptional,
    Object? categoryId = _updateOptional,
    Object? note = _updateOptional,
    bool? archived,
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (type != null) {
      values['type'] = _normalizeType(type);
    }
    if (title != null) {
      values['title'] = title;
    }
    if (defaultAmountMinor != _updateOptional) {
      values['default_amount_minor'] = defaultAmountMinor as int?;
    }
    if (categoryId != _updateOptional) {
      values['category_id'] = categoryId as int?;
    }
    if (note != _updateOptional) {
      values['note'] = note as String?;
    }
    if (archived != null) {
      values['archived'] = archived ? 1 : 0;
    }
    if (values.isEmpty) {
      return;
    }
    values['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'planned_master',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  String _normalizeType(String type) {
    final normalized = type.toLowerCase();
    if (!_allowedTypes.contains(normalized)) {
      throw ArgumentError.value(type, 'type', 'Unsupported planned type');
    }
    return normalized;
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
