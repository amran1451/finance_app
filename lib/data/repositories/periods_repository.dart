import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../../utils/period_utils.dart';

class PeriodEntry {
  const PeriodEntry({
    required this.id,
    required this.year,
    required this.month,
    required this.half,
    required this.start,
    required this.endExclusive,
    required this.isClosed,
    this.closedAt,
  });

  final int id;
  final int year;
  final int month;
  final HalfPeriod half;
  final DateTime start;
  final DateTime endExclusive;
  final bool isClosed;
  final DateTime? closedAt;
}

class PeriodSnapshot {
  const PeriodSnapshot({
    this.payoutId,
    this.dailyLimitMinor,
    this.spentMinor,
    this.plannedIncludedMinor,
    required this.carryoverMinor,
  });

  final int? payoutId;
  final int? dailyLimitMinor;
  final int? spentMinor;
  final int? plannedIncludedMinor;
  final int carryoverMinor;
}

class PeriodStatus {
  const PeriodStatus({
    required this.isClosed,
    this.closedAt,
    this.snapshot,
  });

  final bool isClosed;
  final DateTime? closedAt;
  final PeriodSnapshot? snapshot;

  static const PeriodStatus empty = PeriodStatus(isClosed: false);
}

abstract class PeriodsRepository {
  Future<PeriodEntry> getOrCreate(
    int year,
    int month,
    HalfPeriod half,
    DateTime start,
    DateTime endExclusive, {
    DatabaseExecutor? executor,
  });

  Future<void> closePeriod(
    PeriodRef period, {
    int? payoutId,
    int? dailyLimitMinor,
    int? spentMinor,
    int? plannedIncludedMinor,
    int? carryoverMinor,
    DatabaseExecutor? executor,
  });

  Future<PeriodStatus> getStatus(PeriodRef period);

  Future<void> reopen(
    PeriodRef period, {
    DatabaseExecutor? executor,
  });

  Future<void> reopenLast({DatabaseExecutor? executor});

  Future<void> setPeriodClosed(
    PeriodRef ref, {
    required bool closed,
    DateTime? at,
  });
}

class SqlitePeriodsRepository implements PeriodsRepository {
  SqlitePeriodsRepository({AppDatabase? database})
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
  Future<PeriodEntry> getOrCreate(
    int year,
    int month,
    HalfPeriod half,
    DateTime start,
    DateTime endExclusive, {
    DatabaseExecutor? executor,
  }) async {
    final normalizedStart = normalizeDate(start);
    final normalizedEndExclusive = normalizeDate(endExclusive);

    if (executor != null) {
      return _ensurePeriod(
        executor,
        year,
        month,
        half,
        normalizedStart,
        normalizedEndExclusive,
      );
    }

    final db = await _db;
    final existing = await _findPeriod(db, year, month, half);
    if (existing != null) {
      final evaluation = _calculateBoundaryUpdate(
        existing,
        normalizedStart,
        normalizedEndExclusive,
      );
      if (!evaluation.needsUpdate) {
        return _mapEntry(existing);
      }
    }

    return _runWrite<PeriodEntry>(
      (txn) => _ensurePeriod(
        txn,
        year,
        month,
        half,
        normalizedStart,
        normalizedEndExclusive,
      ),
      debugContext: 'periods.getOrCreate',
    );
  }

  @override
  Future<void> closePeriod(
    PeriodRef period, {
    int? payoutId,
    int? dailyLimitMinor,
    int? spentMinor,
    int? plannedIncludedMinor,
    int? carryoverMinor,
    DatabaseExecutor? executor,
  }) async {
    await _runWrite<void>(
      (txn) async {
        final existing =
            await _findPeriod(txn, period.year, period.month, period.half);
        if (existing == null) {
          throw StateError(
            'Period ${period.year}-${period.month} ${period.half} not initialized',
          );
        }

        final now = DateTime.now();
        await txn.update(
          'periods',
          {
            'payout_id': payoutId,
            'daily_limit_minor': dailyLimitMinor,
            'spent_minor': spentMinor,
            'planned_included_minor': plannedIncludedMinor,
            'carryover_minor': carryoverMinor ?? 0,
            'closed': 1,
            'closed_at': now.toIso8601String(),
            'isClosed': 1,
            'closedAt': now.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      },
      executor: executor,
      debugContext: 'periods.closePeriod',
    );
  }

  Future<PeriodEntry> _ensurePeriod(
    DatabaseExecutor executor,
    int year,
    int month,
    HalfPeriod half,
    DateTime normalizedStart,
    DateTime normalizedEndExclusive,
  ) async {
    final existing = await _findPeriod(executor, year, month, half);
    if (existing != null) {
      final evaluation = _calculateBoundaryUpdate(
        existing,
        normalizedStart,
        normalizedEndExclusive,
      );
      if (evaluation.needsUpdate) {
        final id = existing['id'] as int?;
        if (id == null) {
          throw StateError('Period row missing id');
        }
        await executor.update(
          'periods',
          {
            'start': _formatDate(evaluation.effectiveStart),
            'end_exclusive': _formatDate(evaluation.effectiveEndExclusive),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        existing['start'] = _formatDate(evaluation.effectiveStart);
        existing['end_exclusive'] =
            _formatDate(evaluation.effectiveEndExclusive);
      }
      return _mapEntry(existing);
    }

    final id = await executor.insert('periods', {
      'year': year,
      'month': month,
      'half': _halfToDb(half),
      'start': _formatDate(normalizedStart),
      'end_exclusive': _formatDate(normalizedEndExclusive),
      'carryover_minor': 0,
      'closed': 0,
      'isClosed': 0,
    });

    final inserted = await _findById(executor, id);
    if (inserted == null) {
      throw StateError('Failed to create period row for $year-$month $half');
    }
    return _mapEntry(inserted);
  }

  _BoundaryEvaluation _calculateBoundaryUpdate(
    Map<String, Object?> row,
    DateTime normalizedStart,
    DateTime normalizedEndExclusive,
  ) {
    final storedStartRaw = row['start'] as String?;
    final storedEndRaw = row['end_exclusive'] as String?;
    final storedStartParsed = _parseDate(storedStartRaw);
    final storedEndParsed = _parseDate(storedEndRaw);
    final storedStart =
        storedStartParsed != null ? normalizeDate(storedStartParsed) : null;
    final storedEndExclusive =
        storedEndParsed != null ? normalizeDate(storedEndParsed) : null;

    var effectiveStart = storedStart ?? normalizedStart;
    if (normalizedStart.isBefore(effectiveStart)) {
      effectiveStart = normalizedStart;
    }

    var effectiveEndExclusive = storedEndExclusive ?? normalizedEndExclusive;
    if (normalizedEndExclusive.isAfter(effectiveEndExclusive)) {
      effectiveEndExclusive = normalizedEndExclusive;
    }

    final needsStartUpdate = storedStart == null
        ? true
        : !effectiveStart.isAtSameMomentAs(storedStart);
    final needsEndUpdate = storedEndExclusive == null
        ? true
        : !effectiveEndExclusive.isAtSameMomentAs(storedEndExclusive);

    return _BoundaryEvaluation(
      effectiveStart: effectiveStart,
      effectiveEndExclusive: effectiveEndExclusive,
      needsStartUpdate: needsStartUpdate,
      needsEndUpdate: needsEndUpdate,
    );
  }

  @override
  Future<void> reopen(
    PeriodRef period, {
    DatabaseExecutor? executor,
  }) async {
    await _runWrite<void>(
      (txn) async {
        final existing =
            await _findPeriod(txn, period.year, period.month, period.half);
        final id = existing?['id'] as int?;
        if (id == null) {
          return;
        }
        await txn.update(
          'periods',
          {
            'closed': 0,
            'closed_at': null,
            'isClosed': 0,
            'closedAt': null,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'periods.reopen',
    );
  }

  @override
  Future<PeriodStatus> getStatus(PeriodRef period) async {
    final db = await _db;
    final rows = await db.query(
      'periods',
      where: 'year = ? AND month = ? AND half = ?',
      whereArgs: [period.year, period.month, _halfToDb(period.half)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return PeriodStatus.empty;
    }
    final row = rows.first;
    final closed = _readClosed(row);
    final closedAt = _readClosedAt(row);
    final snapshot = _mapSnapshot(row);
    return PeriodStatus(
      isClosed: closed,
      closedAt: closedAt,
      snapshot: snapshot,
    );
  }

  @override
  Future<void> reopenLast({DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (txn) async {
        final rows = await txn.query(
          'periods',
          where: 'isClosed = 1',
          orderBy: 'start DESC, id DESC',
          limit: 1,
        );
        if (rows.isEmpty) {
          return;
        }
        final id = rows.first['id'] as int?;
        if (id == null) {
          return;
        }
        await txn.update(
          'periods',
          {
            'closed': 0,
            'closed_at': null,
            'isClosed': 0,
            'closedAt': null,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'periods.reopenLast',
    );
  }

  @override
  Future<void> setPeriodClosed(
    PeriodRef ref, {
    required bool closed,
    DateTime? at,
  }) async {
    await _runWrite<void>(
      (txn) async {
        final existing =
            await _findPeriod(txn, ref.year, ref.month, ref.half);
        final id = existing?['id'] as int?;
        if (id == null) {
          throw StateError(
            'Period ${ref.year}-${ref.month} ${ref.half} not initialized',
          );
        }
        final closedAt = closed ? (at ?? DateTime.now()) : null;
        await txn.update(
          'periods',
          {
            'isClosed': closed ? 1 : 0,
            'closedAt': closedAt?.millisecondsSinceEpoch,
            'closed': closed ? 1 : 0,
            'closed_at': closedAt?.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      debugContext: 'periods.setPeriodClosed',
    );
  }

  Future<Map<String, Object?>?> _findPeriod(
    DatabaseExecutor executor,
    int year,
    int month,
    HalfPeriod half,
  ) async {
    final rows = await executor.query(
      'periods',
      where: 'year = ? AND month = ? AND half = ?',
      whereArgs: [year, month, _halfToDb(half)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _findById(DatabaseExecutor executor, int id) async {
    final rows = await executor.query(
      'periods',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  PeriodEntry _mapEntry(Map<String, Object?> row) {
    final id = row['id'] as int?;
    if (id == null) {
      throw StateError('Period row missing id');
    }
    final startRaw = row['start'] as String?;
    final endRaw = row['end_exclusive'] as String?;
    return PeriodEntry(
      id: id,
      year: row['year'] as int? ?? 0,
      month: row['month'] as int? ?? 0,
      half: _halfFromDb(row['half'] as String?),
      start: _parseDate(startRaw) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endExclusive:
          _parseDate(endRaw) ?? DateTime.fromMillisecondsSinceEpoch(0),
      isClosed: _readClosed(row),
      closedAt: _readClosedAt(row),
    );
  }

  PeriodSnapshot? _mapSnapshot(Map<String, Object?> row) {
    final payoutId = row['payout_id'] as int?;
    final dailyLimit = row['daily_limit_minor'] as int?;
    final spent = row['spent_minor'] as int?;
    final planned = row['planned_included_minor'] as int?;
    final carryover = _readInt(row['carryover_minor']);
    final hasData =
        payoutId != null || dailyLimit != null || spent != null || planned != null || carryover != 0;
    if (!hasData) {
      return null;
    }
    return PeriodSnapshot(
      payoutId: payoutId,
      dailyLimitMinor: dailyLimit,
      spentMinor: spent,
      plannedIncludedMinor: planned,
      carryoverMinor: carryover,
    );
  }

  String _halfToDb(HalfPeriod half) {
    return half == HalfPeriod.first ? 'H1' : 'H2';
  }

  HalfPeriod _halfFromDb(String? value) {
    if (value == 'H1') {
      return HalfPeriod.first;
    }
    if (value == 'H2') {
      return HalfPeriod.second;
    }
    throw StateError('Unknown half value: $value');
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
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

  bool _readClosed(Map<String, Object?> row) {
    final value = row['isClosed'];
    if (value is int) {
      return value != 0;
    }
    if (value is num) {
      return value.toInt() != 0;
    }
    if (value is bool) {
      return value;
    }
    final legacy = row['closed'];
    if (legacy is int) {
      return legacy != 0;
    }
    if (legacy is num) {
      return legacy.toInt() != 0;
    }
    if (legacy is bool) {
      return legacy;
    }
    return false;
  }

  DateTime? _readClosedAt(Map<String, Object?> row) {
    final value = row['closedAt'];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final legacy = row['closed_at'];
    if (legacy is int) {
      return DateTime.fromMillisecondsSinceEpoch(legacy);
    }
    if (legacy is String) {
      return _parseDateTime(legacy);
    }
    return null;
  }
}

class _BoundaryEvaluation {
  const _BoundaryEvaluation({
    required this.effectiveStart,
    required this.effectiveEndExclusive,
    required this.needsStartUpdate,
    required this.needsEndUpdate,
  });

  final DateTime effectiveStart;
  final DateTime effectiveEndExclusive;
  final bool needsStartUpdate;
  final bool needsEndUpdate;

  bool get needsUpdate => needsStartUpdate || needsEndUpdate;
}
