import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/payout.dart';
import '../../utils/period_utils.dart';

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

  Future<({Payout payout, PeriodRef period})> upsertWithClampToSelectedPeriod({
    Payout? existing,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    int? accountId,
  });
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
    final normalizedDate = normalizeDate(date);
    return db.transaction((txn) async {
      final resolvedAccountId = await _resolveAccountId(txn, accountId);
      final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
      final anchors = [anchor1Raw, anchor2Raw]..sort();
      final selected = periodRefForDate(normalizedDate, anchors[0], anchors[1]);
      final result = await _upsertWithTransaction(
        txn,
        existingId: null,
        selectedPeriod: selected,
        pickedDate: normalizedDate,
        type: type,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
        anchor1: anchors[0],
        anchor2: anchors[1],
      );
      return result.payout.id!;
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
    final normalizedDate = normalizeDate(date);
    await db.transaction((txn) async {
      final resolvedAccountId = await _resolveAccountId(txn, accountId);
      final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
      final anchors = [anchor1Raw, anchor2Raw]..sort();
      final selected = periodRefForDate(normalizedDate, anchors[0], anchors[1]);
      await _upsertWithTransaction(
        txn,
        existingId: id,
        selectedPeriod: selected,
        pickedDate: normalizedDate,
        type: type,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
        anchor1: anchors[0],
        anchor2: anchors[1],
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
  Future<({Payout payout, PeriodRef period})> upsertWithClampToSelectedPeriod({
    Payout? existing,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    int? accountId,
  }) async {
    final db = await _db;
    final normalized = normalizeDate(pickedDate);
    return db.transaction((txn) async {
      final resolvedAccountId = await _resolveAccountId(txn, accountId ?? existing?.accountId);
      final (anchor1Raw, anchor2Raw) = await _loadAnchorDays(txn);
      final anchors = [anchor1Raw, anchor2Raw]..sort();
      return _upsertWithTransaction(
        txn,
        existingId: existing?.id,
        selectedPeriod: selectedPeriod,
        pickedDate: normalized,
        type: type,
        amountMinor: amountMinor,
        accountId: resolvedAccountId,
        anchor1: anchors[0],
        anchor2: anchors[1],
      );
    });
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

  Future<({Payout payout, PeriodRef period})> _upsertWithTransaction(
    Transaction txn, {
    required int? existingId,
    required PeriodRef selectedPeriod,
    required DateTime pickedDate,
    required PayoutType type,
    required int amountMinor,
    required int accountId,
    required int anchor1,
    required int anchor2,
  }) async {
    final (clampedDate, targetPeriod) = _clampToHalfWithWindow(
      pickedDate,
      selectedPeriod,
      anchor1,
      anchor2,
    );

    final payout = Payout(
      id: existingId,
      type: type,
      date: clampedDate,
      amountMinor: amountMinor,
      accountId: accountId,
    );
    final payoutValues = _payoutValues(payout);
    late final int payoutId;
    if (existingId != null) {
      payoutId = existingId;
      await txn.update(
        'payouts',
        payoutValues,
        where: 'id = ?',
        whereArgs: [payoutId],
      );
    } else {
      payoutId = await txn.insert('payouts', payoutValues);
    }

    await _syncIncomeTransaction(
      txn,
      payoutId: payoutId,
      type: type,
      date: clampedDate,
      amountMinor: amountMinor,
      accountId: accountId,
    );

    return (
      payout: payout.copyWith(id: payoutId),
      period: targetPeriod,
    );
  }

  (DateTime, PeriodRef) _clampToHalfWithWindow(
    DateTime picked,
    PeriodRef selected,
    int anchor1,
    int anchor2,
  ) {
    final bounds = periodBoundsFor(selected, anchor1, anchor2);
    final start = bounds.start;
    final endEx = bounds.endExclusive;
    final allowBefore = start.subtract(const Duration(days: 3));
    final allowAfter = endEx.add(const Duration(days: 5));

    if (picked.isBefore(allowBefore)) {
      final prev = selected.prevHalf();
      final prevBounds = periodBoundsFor(prev, anchor1, anchor2);
      final prevDate = prevBounds.endExclusive.subtract(const Duration(days: 1));
      return (prevDate, prev);
    }

    if (picked.isBefore(endEx)) {
      final date = picked.isBefore(start) ? start : picked;
      return (date, selected);
    }

    if (!picked.isAfter(allowAfter)) {
      final clamped = endEx.subtract(const Duration(days: 1));
      return (clamped, selected);
    }

    final next = selected.nextHalf();
    final nextBounds = periodBoundsFor(next, anchor1, anchor2);
    return (nextBounds.start, next);
  }
}
