import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/payout.dart';
import '../../utils/payout_rules.dart';
import '../../utils/period_utils.dart';

abstract class PayoutsRepository {
  Future<int> add(
    PayoutType type,
    DateTime date,
    int amountMinor, {
    int? accountId,
    DatabaseExecutor? executor,
  });

  Future<void> update({
    required int id,
    required PayoutType type,
    required DateTime date,
    required int amountMinor,
    int? accountId,
    DatabaseExecutor? executor,
  });

  Future<void> delete(int id, {DatabaseExecutor? executor});

  Future<Payout?> getLast();

  /// Выплата, попадающая в указанный диапазон дат [start; endExclusive)
  Future<Payout?> findInRange(DateTime start, DateTime endExclusive);

  /// Список выплат в диапазоне (для будущих экранов истории)
  Future<List<Payout>> listInRange(DateTime start, DateTime endExclusive);

  Future<void> setDailyLimit({
    required int payoutId,
    required int dailyLimitMinor,
    required bool fromToday,
    DatabaseExecutor? executor,
  });

  Future<({int dailyLimitMinor, bool fromToday})> getDailyLimit(int payoutId);

  Future<List<Payout>> getHistory(int limit);

  Future<({Payout payout, PeriodRef period})> upsertWithClampToSelectedPeriod({
    Payout? existing,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    int? accountId,
    bool shiftPeriodStart = false,
    DatabaseExecutor? executor,
  });
}

class SqlitePayoutsRepository implements PayoutsRepository {
  SqlitePayoutsRepository({AppDatabase? database})
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
  Future<int> add(
    PayoutType type,
    DateTime date,
    int amountMinor, {
    int? accountId,
    DatabaseExecutor? executor,
  }) async {
    final normalizedDate = normalizeDate(date);
    return _runWrite<int>(
      (txn) async {
        final resolvedAccountId = await _resolveAccountId(txn, accountId);
        final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
        final anchors = [anchor1Raw, anchor2Raw]..sort();
        final selected = periodRefForDate(normalizedDate, anchors[0], anchors[1]);
        final result = await _upsertWithExecutor(
          txn,
          existing: null,
          existingId: null,
          selectedPeriod: selected,
          pickedDate: normalizedDate,
          type: type,
          amountMinor: amountMinor,
          accountId: resolvedAccountId,
          anchor1: anchors[0],
          anchor2: anchors[1],
          shiftPeriodStart: false,
        );
        return result.payout.id!;
      },
      executor: executor,
      debugContext: 'payouts.add',
    );
  }

  @override
  Future<void> update({
    required int id,
    required PayoutType type,
    required DateTime date,
    required int amountMinor,
    int? accountId,
    DatabaseExecutor? executor,
  }) async {
    final normalizedDate = normalizeDate(date);
    await _runWrite<void>(
      (txn) async {
        final resolvedAccountId = await _resolveAccountId(txn, accountId);
        final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
        final anchors = [anchor1Raw, anchor2Raw]..sort();
        final selected = periodRefForDate(normalizedDate, anchors[0], anchors[1]);
        await _upsertWithExecutor(
          txn,
          existing: null,
          existingId: id,
          selectedPeriod: selected,
          pickedDate: normalizedDate,
          type: type,
          amountMinor: amountMinor,
          accountId: resolvedAccountId,
          anchor1: anchors[0],
          anchor2: anchors[1],
          shiftPeriodStart: false,
        );
      },
      executor: executor,
      debugContext: 'payouts.update',
    );
  }

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (txn) async {
        final impactedPeriods = await txn.query(
          'periods',
          where: 'start_anchor_payout_id = ?',
          whereArgs: [id],
        );

        await txn.delete(
          'transactions',
          where: 'payout_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'payouts',
          where: 'id = ?',
          whereArgs: [id],
        );

        await _restorePeriodStarts(
          txn,
          periodRows: impactedPeriods,
        );
      },
      executor: executor,
      debugContext: 'payouts.delete',
    );
  }

  @override
  Future<List<Payout>> getHistory(int limit) async {
    final db = await _db;
    final rows = await db.query(
      'payouts',
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Payout.fromMap).toList();
  }

  @override
  Future<Payout?> getLast() async {
    final db = await _db;
    final rows = await db.query(
      'payouts',
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Payout.fromMap(rows.first);
  }

  @override
  Future<Payout?> findInRange(DateTime start, DateTime endExclusive) async {
    final db = await _db;
    final rows = await db.query(
      'payouts',
      where: 'date >= ? AND date < ?',
      whereArgs: [
        _formatDate(normalizeDate(start)),
        _formatDate(normalizeDate(endExclusive)),
      ],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Payout.fromMap(rows.first);
  }

  @override
  Future<List<Payout>> listInRange(DateTime start, DateTime endExclusive) async {
    final db = await _db;
    final rows = await db.query(
      'payouts',
      where: 'date >= ? AND date < ?',
      whereArgs: [
        _formatDate(normalizeDate(start)),
        _formatDate(normalizeDate(endExclusive)),
      ],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Payout.fromMap).toList();
  }

  @override
  Future<void> setDailyLimit({
    required int payoutId,
    required int dailyLimitMinor,
    required bool fromToday,
    DatabaseExecutor? executor,
  }) async {
    await _runWrite<void>(
      (db) async {
        await db.update(
          'payouts',
          {
            'daily_limit_minor': dailyLimitMinor,
            'daily_limit_from_today': fromToday ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [payoutId],
        );
      },
      executor: executor,
      debugContext: 'payouts.setDailyLimit',
    );
  }

  @override
  Future<({int dailyLimitMinor, bool fromToday})> getDailyLimit(int payoutId) async {
    final db = await _db;
    final rows = await db.query(
      'payouts',
      columns: ['daily_limit_minor', 'daily_limit_from_today'],
      where: 'id = ?',
      whereArgs: [payoutId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Payout $payoutId not found');
    }
    final row = rows.first;
    final limit = (row['daily_limit_minor'] as int?) ?? 0;
    final fromToday = ((row['daily_limit_from_today'] as int?) ?? 0) == 1;
    return (dailyLimitMinor: limit, fromToday: fromToday);
  }

  @override
  Future<({Payout payout, PeriodRef period})> upsertWithClampToSelectedPeriod({
    Payout? existing,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    int? accountId,
    bool shiftPeriodStart = false,
    DatabaseExecutor? executor,
  }) async {
    final normalized = normalizeDate(pickedDate);
    return _runWrite<({Payout payout, PeriodRef period})>(
      (txn) async {
        final resolvedAccountId =
            await _resolveAccountId(txn, accountId ?? existing?.accountId);
        final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
        final anchors = [anchor1Raw, anchor2Raw]..sort();
        return _upsertWithExecutor(
          txn,
          existing: existing,
          existingId: existing?.id,
          selectedPeriod: selectedPeriod,
          pickedDate: normalized,
          type: type,
          amountMinor: amountMinor,
          accountId: resolvedAccountId,
          anchor1: anchors[0],
          anchor2: anchors[1],
          shiftPeriodStart: shiftPeriodStart,
        );
      },
      executor: executor,
      debugContext: 'payouts.upsertClamp',
    );
  }

  Map<String, Object?> _payoutValues(Payout payout) {
    final values = payout.toMap();
    values.remove('id');
    return values;
  }

  Future<void> _syncIncomeTransaction(
    DatabaseExecutor executor, {
    required int payoutId,
    required PayoutType type,
    required DateTime date,
    required int amountMinor,
    required int accountId,
  }) async {
    final categoryId = await _ensureIncomeCategory(executor, type);
    final dateString = _formatDate(date);
    final existing = await executor.query(
      'transactions',
      columns: ['id'],
      where: 'payout_id = ?',
      whereArgs: [payoutId],
      limit: 1,
    );

    final transactionValues = <String, Object?>{
      'account_id': accountId,
      'category_id': categoryId,
      'type': 'income',
      'amount_minor': amountMinor,
      'date': dateString,
      'time': null,
      'note': null,
      'is_planned': 0,
      'included_in_period': 1,
      'tags': null,
      'payout_id': payoutId,
    };

    if (existing.isEmpty) {
      await executor.insert('transactions', transactionValues);
    } else {
      final transactionId = existing.first['id'] as int;
      await executor.update(
        'transactions',
        transactionValues,
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    }
  }

  Future<int> _ensureIncomeCategory(
    DatabaseExecutor executor,
    PayoutType type,
  ) async {
    final name = _categoryNameForType(type);
    final existing = await executor.query(
      'categories',
      columns: ['id'],
      where: 'type = ? AND name = ? AND is_group = 0',
      whereArgs: ['income', name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final values = <String, Object?>{
      'type': 'income',
      'name': name,
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    };
    return executor.insert('categories', values);
  }

  String _categoryNameForType(PayoutType type) {
    switch (type) {
      case PayoutType.advance:
        return 'Аванс';
      case PayoutType.salary:
        return 'Зарплата';
    }
  }

  Future<int> _resolveAccountId(DatabaseExecutor executor, int? accountId) async {
    if (accountId != null) {
      return accountId;
    }
    final defaultAccount = await executor.query(
      'accounts',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: ['Карта'],
      limit: 1,
    );
    if (defaultAccount.isNotEmpty) {
      return defaultAccount.first['id'] as int;
    }
    final anyAccount = await executor.query(
      'accounts',
      columns: ['id'],
      limit: 1,
    );
    if (anyAccount.isNotEmpty) {
      return anyAccount.first['id'] as int;
    }
    throw StateError('Не найден счёт для привязки выплаты');
  }

  Future<(int, int)> _loadAnchorDays(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: ['anchor_day_1', 'anchor_day_2'],
    );
    int? day1;
    int? day2;
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = int.tryParse((row['value'] as String?) ?? '');
      if (key == 'anchor_day_1') {
        day1 = value;
      } else if (key == 'anchor_day_2') {
        day2 = value;
      }
    }
    day1 ??= 1;
    day2 ??= 15;
    return (day1, day2);
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  Future<Payout?> _loadPayoutById(DatabaseExecutor executor, int id) async {
    final rows = await executor.query(
      'payouts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Payout.fromMap(rows.first);
  }

  Future<({Payout payout, PeriodRef period})> _upsertWithExecutor(
    DatabaseExecutor executor, {
    required Payout? existing,
    required int? existingId,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    required int accountId,
    required int anchor1,
    required int anchor2,
    required bool shiftPeriodStart,
  }) async {
    final normalizedPicked = normalizeDate(pickedDate);
    final bounds = periodBoundsFor(selectedPeriod, anchor1, anchor2);
    final normalizedStart = normalizeDate(bounds.start);
    final normalizedEndExclusive = normalizeDate(bounds.endExclusive);
    final earliestAllowed = normalizedStart.subtract(
      const Duration(days: kEarlyPayoutGraceDays),
    );
    final latestAllowed = normalizedEndExclusive.subtract(
      const Duration(days: 1),
    );

    if (normalizedPicked.isBefore(earliestAllowed) ||
        normalizedPicked.isAfter(latestAllowed)) {
      throw ArgumentError.value(
        pickedDate,
        'pickedDate',
        'Дата выплаты вне допустимого диапазона выбранного периода',
      );
    }

    final resolvedExisting = existing ??
        (existingId != null ? await _loadPayoutById(executor, existingId) : null);

    final payout = (resolvedExisting ??
            Payout(
              id: existingId,
              type: type,
              date: normalizedPicked,
              amountMinor: amountMinor,
              accountId: accountId,
            ))
        .copyWith(
      id: existingId,
      type: type,
      date: normalizedPicked,
      amountMinor: amountMinor,
      accountId: accountId,
    );
    final payoutValues = _payoutValues(payout);
    late final int payoutId;
    if (existingId != null) {
      payoutId = existingId;
      await executor.update(
        'payouts',
        payoutValues,
        where: 'id = ?',
        whereArgs: [payoutId],
      );
    } else {
      payoutId = await executor.insert('payouts', payoutValues);
    }

    await _syncIncomeTransaction(
      executor,
      payoutId: payoutId,
      type: type,
      date: normalizedPicked,
      amountMinor: amountMinor,
      accountId: accountId,
    );

    if (shiftPeriodStart) {
      await _updatePeriodStart(
        executor,
        period: selectedPeriod,
        newStart: normalizedPicked,
        anchor1: anchor1,
        anchor2: anchor2,
        payoutId: payoutId,
      );
    }

    return (
      payout: payout.copyWith(id: payoutId),
      period: selectedPeriod,
    );
  }

  Future<void> _updatePeriodStart(
    DatabaseExecutor executor, {
    required PeriodRef period,
    required DateTime newStart,
    required int anchor1,
    required int anchor2,
    required int payoutId,
  }) async {
    final normalizedStart = normalizeDate(newStart);
    final rows = await executor.query(
      'periods',
      where: 'year = ? AND month = ? AND half = ?',
      whereArgs: [period.year, period.month, _halfToDb(period.half)],
      limit: 1,
    );

    if (rows.isEmpty) {
      return;
    }

    final row = rows.first;
    final id = row['id'] as int?;
    if (id == null) {
      return;
    }

    final defaultBounds = period.bounds(anchor1, anchor2);
    final storedStart =
        _parseDate(row['start'] as String?) ?? normalizeDate(defaultBounds.start);
    final storedEndExclusiveRaw =
        _parseDate(row['end_exclusive'] as String?) ?? defaultBounds.endExclusive;
    final storedEndExclusive = normalizeDate(storedEndExclusiveRaw);

    if (!normalizedStart.isBefore(storedStart)) {
      return;
    }

    if (!normalizedStart.isBefore(storedEndExclusive)) {
      return;
    }

    await executor.update(
      'periods',
      {
        'start': _formatDate(normalizedStart),
        'start_anchor_payout_id': payoutId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _restorePeriodStarts(
    DatabaseExecutor executor, {
    required List<Map<String, Object?>> periodRows,
  }) async {
    if (periodRows.isEmpty) {
      return;
    }

    final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(executor);
    final anchors = [anchor1Raw, anchor2Raw]..sort();

    for (final row in periodRows) {
      final id = row['id'] as int?;
      final year = row['year'] as int?;
      final month = row['month'] as int?;
      final halfRaw = row['half'] as String?;
      if (id == null || year == null || month == null || halfRaw == null) {
        continue;
      }

      final half = halfRaw == 'H1' ? HalfPeriod.first : HalfPeriod.second;
      final period = PeriodRef(year: year, month: month, half: half);
      final defaultBounds = period.bounds(anchors[0], anchors[1]);
      final defaultStart = normalizeDate(defaultBounds.start);
      final storedEndRaw = row['end_exclusive'] as String?;
      final storedEndParsed = _parseDate(storedEndRaw) ?? defaultBounds.endExclusive;
      final normalizedEndExclusive = normalizeDate(storedEndParsed);

      var earliestAllowed = normalizeDate(
        defaultStart.subtract(const Duration(days: kEarlyPayoutGraceDays)),
      );
      if (!normalizedEndExclusive.isAfter(earliestAllowed)) {
        earliestAllowed = defaultStart;
      }

      final candidates = await executor.query(
        'payouts',
        columns: ['id', 'date'],
        where: 'date >= ? AND date < ?',
        whereArgs: [
          _formatDate(earliestAllowed),
          _formatDate(normalizedEndExclusive),
        ],
        orderBy: 'date ASC, id ASC',
        limit: 1,
      );

      var nextStart = defaultStart;
      int? anchorPayoutId;

      if (candidates.isNotEmpty) {
        final candidate = candidates.first;
        final candidateDateRaw = candidate['date'] as String?;
        final candidateDate = _parseDate(candidateDateRaw);
        if (candidateDate != null) {
          final normalizedCandidate = normalizeDate(candidateDate);
          if (normalizedCandidate.isBefore(defaultStart)) {
            nextStart = normalizedCandidate;
            anchorPayoutId = candidate['id'] as int?;
          }
        }
      }

      await executor.update(
        'periods',
        {
          'start': _formatDate(nextStart),
          'start_anchor_payout_id': anchorPayoutId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  String _halfToDb(HalfPeriod half) {
    return half == HalfPeriod.first ? 'H1' : 'H2';
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
