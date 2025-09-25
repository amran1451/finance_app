import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/payout.dart';

abstract class PayoutsRepository {
  Future<int> add(
    PayoutType type,
    DateTime date,
    int amountMinor, {
    int? accountId,
  });

  Future<void> update({
    required int id,
    required PayoutType type,
    required DateTime date,
    required int amountMinor,
    int? accountId,
  });

  Future<void> delete(int id);

  Future<Payout?> getLast();

  /// Выплата, попадающая в указанный диапазон дат [start; endExclusive)
  Future<Payout?> findInRange(DateTime start, DateTime endExclusive);

  /// Список выплат в диапазоне (для будущих экранов истории)
  Future<List<Payout>> listInRange(DateTime start, DateTime endExclusive);

  Future<List<Payout>> getHistory(int limit);
}

class SqlitePayoutsRepository implements PayoutsRepository {
  SqlitePayoutsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> add(
    PayoutType type,
    DateTime date,
    int amountMinor, {
    int? accountId,
  }) async {
    final db = await _db;
    final normalizedDate = _normalizeDate(date);
    return db.transaction((txn) async {
      final resolvedAccountId = await _resolveAccountId(txn, accountId);
      final adjustedDate = await _clampDateWithDrift(txn, normalizedDate);
      final payout = Payout(
        type: type,
        date: adjustedDate,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
      );
      final payoutValues = _payoutValues(payout);
      final payoutId = await txn.insert('payouts', payoutValues);
      await _syncIncomeTransaction(
        txn,
        payoutId: payoutId,
        type: type,
        date: adjustedDate,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
      );
      return payoutId;
    });
  }

  @override
  Future<void> update({
    required int id,
    required PayoutType type,
    required DateTime date,
    required int amountMinor,
    int? accountId,
  }) async {
    final db = await _db;
    final normalizedDate = _normalizeDate(date);
    await db.transaction((txn) async {
      final resolvedAccountId = await _resolveAccountId(txn, accountId);
      final adjustedDate = await _clampDateWithDrift(txn, normalizedDate);
      final payout = Payout(
        id: id,
        type: type,
        date: adjustedDate,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
      );
      final payoutValues = _payoutValues(payout);
      await txn.update(
        'payouts',
        payoutValues,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _syncIncomeTransaction(
        txn,
        payoutId: id,
        type: type,
        date: adjustedDate,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
      );
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
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
    });
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
        _formatDate(_normalizeDate(start)),
        _formatDate(_normalizeDate(endExclusive)),
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
        _formatDate(_normalizeDate(start)),
        _formatDate(_normalizeDate(endExclusive)),
      ],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Payout.fromMap).toList();
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

  Future<DateTime> _clampDateWithDrift(
    DatabaseExecutor executor,
    DateTime date,
  ) async {
    final normalized = _normalizeDate(date);
    final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(executor);
    final anchor1 = math.min(anchor1Raw, anchor2Raw);
    final anchor2 = math.max(anchor1Raw, anchor2Raw);

    final (_, periodEnd) = _periodBounds(normalized, anchor1, anchor2);
    final lastInPeriod = periodEnd.subtract(const Duration(days: 1));

    if (!normalized.isAfter(lastInPeriod)) {
      return normalized;
    }

    final allowedMax = lastInPeriod.add(const Duration(days: 5));
    if (normalized.isAfter(allowedMax)) {
      return periodEnd;
    }

    return lastInPeriod;
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

  (DateTime start, DateTime endExclusive) _periodBounds(
    DateTime date,
    int anchor1,
    int anchor2,
  ) {
    final previous = _previousAnchorDate(date, anchor1, anchor2);
    var next = _nextAnchorDate(previous, anchor1, anchor2);
    if (!next.isAfter(previous)) {
      next = _nextAnchorDate(next.add(const Duration(days: 1)), anchor1, anchor2);
    }
    return (previous, next);
  }

  DateTime _nextAnchorDate(DateTime from, int anchor1, int anchor2) {
    final normalized = _normalizeDate(from);
    final smaller = math.min(anchor1, anchor2);
    final larger = math.max(anchor1, anchor2);

    if (normalized.day < larger) {
      return _anchorDate(normalized.year, normalized.month, larger);
    }

    final nextMonth = DateTime(normalized.year, normalized.month + 1, 1);
    return _anchorDate(nextMonth.year, nextMonth.month, smaller);
  }

  DateTime _previousAnchorDate(DateTime from, int anchor1, int anchor2) {
    final normalized = _normalizeDate(from);
    final smaller = math.min(anchor1, anchor2);
    final larger = math.max(anchor1, anchor2);

    if (normalized.day <= smaller) {
      final previousMonth = DateTime(normalized.year, normalized.month - 1, 1);
      return _anchorDate(previousMonth.year, previousMonth.month, larger);
    }

    if (normalized.day <= larger) {
      return _anchorDate(normalized.year, normalized.month, smaller);
    }

    return _anchorDate(normalized.year, normalized.month, larger);
  }

  DateTime _anchorDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day.clamp(1, lastDay);
    return DateTime(year, month, safeDay);
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}
