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
    required this.closed,
    this.closedAt,
  });

  final int id;
  final int year;
  final int month;
  final HalfPeriod half;
  final DateTime start;
  final DateTime endExclusive;
  final bool closed;
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
    required this.closed,
    this.closedAt,
    this.snapshot,
  });

  final bool closed;
  final DateTime? closedAt;
  final PeriodSnapshot? snapshot;

  static const PeriodStatus empty = PeriodStatus(closed: false);
}

abstract class PeriodsRepository {
  Future<PeriodEntry> getOrCreate(
    int year,
    int month,
    HalfPeriod half,
    DateTime start,
    DateTime endExclusive,
  );

  Future<void> closePeriod(
    PeriodRef period, {
    int? payoutId,
    int? dailyLimitMinor,
    int? spentMinor,
    int? plannedIncludedMinor,
    int? carryoverMinor,
  });

  Future<PeriodStatus> getStatus(PeriodRef period);

  Future<void> reopenLast();
}

class SqlitePeriodsRepository implements PeriodsRepository {
  SqlitePeriodsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<PeriodEntry> getOrCreate(
    int year,
    int month,
    HalfPeriod half,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await _findPeriod(txn, year, month, half);
      if (existing != null) {
        final normalizedStart = normalizeDate(start);
        final normalizedEndExclusive = normalizeDate(endExclusive);
        final storedStartRaw = existing['start'] as String?;
        final storedEndRaw = existing['end_exclusive'] as String?;
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

        if (needsStartUpdate || needsEndUpdate) {
          await txn.update(
            'periods',
            {
              'start': _formatDate(effectiveStart),
              'end_exclusive': _formatDate(effectiveEndExclusive),
            },
            where: 'id = ?',
            whereArgs: [existing['id']],
          );
          existing['start'] = _formatDate(effectiveStart);
          existing['end_exclusive'] = _formatDate(effectiveEndExclusive);
        }

        return _mapEntry(existing);
      }

      final id = await txn.insert('periods', {
        'year': year,
        'month': month,
        'half': _halfToDb(half),
        'start': _formatDate(start),
        'end_exclusive': _formatDate(endExclusive),
        'carryover_minor': 0,
        'closed': 0,
      });

      final inserted = await _findById(txn, id);
      if (inserted == null) {
        throw StateError('Failed to create period row for $year-$month $half');
      }
      return _mapEntry(inserted);
    });
  }

  @override
  Future<void> closePeriod(
    PeriodRef period, {
    int? payoutId,
    int? dailyLimitMinor,
    int? spentMinor,
    int? plannedIncludedMinor,
    int? carryoverMinor,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await _findPeriod(txn, period.year, period.month, period.half);
      if (existing == null) {
        throw StateError('Period ${period.year}-${period.month} ${period.half} not initialized');
      }

      await txn.update(
        'periods',
        {
          'payout_id': payoutId,
          'daily_limit_minor': dailyLimitMinor,
          'spent_minor': spentMinor,
          'planned_included_minor': plannedIncludedMinor,
          'carryover_minor': carryoverMinor ?? 0,
          'closed': 1,
          'closed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
    });
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
    final closed = (row['closed'] as int? ?? 0) != 0;
    final closedAt = _parseDateTime(row['closed_at'] as String?);
    final snapshot = _mapSnapshot(row);
    return PeriodStatus(
      closed: closed,
      closedAt: closedAt,
      snapshot: snapshot,
    );
  }

  @override
  Future<void> reopenLast() async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'periods',
        where: 'closed = 1',
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
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
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
    return rows.first;
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
    return rows.first;
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
      closed: (row['closed'] as int? ?? 0) != 0,
      closedAt: _parseDateTime(row['closed_at'] as String?),
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
}
