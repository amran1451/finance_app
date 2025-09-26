import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'necessity_repository.dart' as necessity_repo;

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

class PlannedMasterView {
  const PlannedMasterView({
    required this.id,
    required this.type,
    required this.title,
    this.defaultAmountMinor,
    this.categoryId,
    this.note,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.assignedNow,
    this.necessityId,
    this.necessityName,
    this.necessityColor,
  });

  final int id;
  final String type;
  final String title;
  final int? defaultAmountMinor;
  final int? categoryId;
  final String? note;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool assignedNow;
  final int? necessityId;
  final String? necessityName;
  final int? necessityColor;

  PlannedMaster toMaster() {
    return PlannedMaster(
      id: id,
      type: type,
      title: title,
      defaultAmountMinor: defaultAmountMinor,
      categoryId: categoryId,
      note: note,
      archived: archived,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory PlannedMasterView.fromMap(Map<String, Object?> map) {
    return PlannedMasterView(
      id: _readInt(map['id']),
      type: (map['type'] as String? ?? '').toLowerCase(),
      title: map['title'] as String? ?? '',
      defaultAmountMinor: _readNullableInt(map['default_amount_minor']),
      categoryId: _readNullableInt(map['category_id']),
      note: map['note'] as String?,
      archived: _readBool(map['archived']),
      createdAt: PlannedMaster._parseDateTime(map['created_at'] as String?),
      updatedAt: PlannedMaster._parseDateTime(map['updated_at'] as String?),
      assignedNow: _readBool(map['assigned_now']),
      necessityId: _readNullableInt(map['necessity_id']),
      necessityName: map['necessity_name'] as String?,
      necessityColor: _parseColor(map['necessity_color']),
    );
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static int _readInt(Object? value) {
    final result = _readNullableInt(value);
    return result ?? 0;
  }

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }

  static int? _parseColor(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      final normalized = raw.trim();
      if (normalized.isEmpty) {
        return null;
      }
      final hex = normalized.startsWith('#')
          ? normalized.substring(1)
          : normalized;
      if (hex.length == 6) {
        final value = int.tryParse(hex, radix: 16);
        return value != null ? 0xFF000000 | value : null;
      }
      if (hex.length == 8) {
        return int.tryParse(hex, radix: 16);
      }
    }
    return null;
  }
}

const Object _updateOptional = Object();

abstract class PlannedMasterRepository {
  Future<List<PlannedMaster>> list({bool includeArchived = false});

  Future<PlannedMaster?> getById(int id);

  Future<List<PlannedMaster>> listAssignableForPeriod(
    DateTime start,
    DateTime endExclusive, {
    String? type,
  });

  Future<List<PlannedMasterView>> query({
    String? type,
    List<int>? necessityIds,
    bool? assignedInPeriod,
    bool archived = false,
    String? search,
    String sort = 'title',
    bool desc = false,
    required DateTime periodStart,
    required DateTime periodEndEx,
  });

  Future<Map<int, necessity_repo.NecessityLabel>> listNecessityLabels();

  Future<int> create({
    required String type,
    required String title,
    int? defaultAmountMinor,
    int? categoryId,
    String? note,
  });

  Future<bool> update(
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

  static const String _assignedNowExpression = '''
    EXISTS(
      SELECT 1 FROM transactions t
      WHERE t.is_planned = 1
        AND t.planned_id = pm.id
        AND t.date >= ?
        AND t.date < ?
    )
  ''';

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
  Future<List<PlannedMaster>> listAssignableForPeriod(
    DateTime start,
    DateTime endExclusive, {
    String? type,
  }) async {
    final db = await _db;
    final normalizedType = type == null ? null : _normalizeType(type);
    final rows = await db.rawQuery(
      '''
      SELECT pm.*
      FROM planned_master pm
      WHERE pm.archived = 0
        AND (?1 IS NULL OR pm.type = ?1)
        AND NOT EXISTS (
          SELECT 1
          FROM transactions t
          WHERE t.is_planned = 1
            AND t.planned_id = pm.id
            AND t.date >= ?2
            AND t.date < ?3
        )
      ORDER BY pm.title COLLATE NOCASE
      ''',
      [
        normalizedType,
        _formatDate(start),
        _formatDate(endExclusive),
      ],
    );
    return rows.map(PlannedMaster.fromMap).toList();
  }

  @override
  Future<List<PlannedMasterView>> query({
    String? type,
    List<int>? necessityIds,
    bool? assignedInPeriod,
    bool archived = false,
    String? search,
    String sort = 'title',
    bool desc = false,
    required DateTime periodStart,
    required DateTime periodEndEx,
  }) async {
    final db = await _db;
    final normalizedType = type == null ? null : _normalizeType(type);
    final sql = StringBuffer()
      ..writeln('SELECT pm.*,')
      ..writeln('       $_assignedNowExpression AS assigned_now,')
      ..writeln('       pm.necessity_id AS necessity_id,')
      ..writeln('       nl.name AS necessity_name,')
      ..writeln('       nl.color AS necessity_color')
      ..writeln('FROM planned_master pm')
      ..writeln('LEFT JOIN necessity_labels nl ON nl.id = pm.necessity_id')
      ..writeln('WHERE pm.archived = ?');

    final args = <Object?>[
      _formatDate(periodStart),
      _formatDate(periodEndEx),
      archived ? 1 : 0,
    ];

    if (normalizedType != null) {
      sql.writeln('  AND pm.type = ?');
      args.add(normalizedType);
    }

    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim().replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      sql.writeln('  AND pm.title LIKE ? ESCAPE "\\"');
      args.add(pattern);
    }

    if (necessityIds != null && necessityIds.isNotEmpty) {
      final placeholders = List.filled(necessityIds.length, '?').join(', ');
      sql.writeln('  AND pm.necessity_id IN ($placeholders)');
      args.addAll(necessityIds);
    }

    if (assignedInPeriod != null) {
      sql.writeln(
        assignedInPeriod
            ? '  AND $_assignedNowExpression'
            : '  AND NOT $_assignedNowExpression',
      );
      args
        ..add(_formatDate(periodStart))
        ..add(_formatDate(periodEndEx));
    }

    sql.writeln('ORDER BY ${_buildOrderBy(sort, desc)}');

    final rows = await db.rawQuery(sql.toString(), args);
    return rows.map(PlannedMasterView.fromMap).toList();
  }

  @override
  Future<Map<int, necessity_repo.NecessityLabel>> listNecessityLabels() async {
    final db = await _db;
    final rows = await db.query(
      'necessity_labels',
      where: 'archived = 0',
      orderBy: 'sort_order ASC, id ASC',
    );
    final result = <int, necessity_repo.NecessityLabel>{};
    for (final row in rows) {
      final id = _readInt(row['id']);
      result[id] = necessity_repo.NecessityLabel(
        id: id,
        name: row['name'] as String? ?? '',
        color: row['color'] as String?,
        sortOrder: _readInt(row['sort_order']),
        archived: _readInt(row['archived']) != 0,
      );
    }
    return result;
  }

  @override
  Future<bool> update(
    int id, {
    String? type,
    String? title,
    Object? defaultAmountMinor = _updateOptional,
    Object? categoryId = _updateOptional,
    Object? note = _updateOptional,
    bool? archived,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      return false;
    }

    final normalizedType = type == null ? null : _normalizeType(type);

    final next = existing.copyWith(
      type: normalizedType,
      title: title,
      defaultAmountMinor: defaultAmountMinor,
      categoryId: categoryId,
      note: note,
      archived: archived,
      updatedAt: DateTime.now().toUtc(),
    );

    final updatedValues = next.toMap()
      ..remove('id')
      ..remove('created_at');

    final db = await _db;
    final rowsUpdated = await db.update(
      'planned_master',
      updatedValues,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rowsUpdated > 0;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  String _normalizeType(String type) {
    final normalized = type.toLowerCase();
    if (!_allowedTypes.contains(normalized)) {
      throw ArgumentError.value(type, 'type', 'Unsupported planned type');
    }
    return normalized;
  }

  String _buildOrderBy(String sort, bool desc) {
    final direction = desc ? 'DESC' : 'ASC';
    switch (sort) {
      case 'amount':
        return '''
          CASE WHEN pm.default_amount_minor IS NULL THEN 1 ELSE 0 END ASC,
          pm.default_amount_minor $direction,
          pm.title COLLATE NOCASE ASC,
          pm.id ASC
        ''';
      case 'updated_at':
        return 'pm.updated_at $direction, pm.title COLLATE NOCASE ASC, pm.id ASC';
      case 'title':
      default:
        return 'pm.title COLLATE NOCASE $direction, pm.id ASC';
    }
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
