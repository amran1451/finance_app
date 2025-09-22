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
    required int accountId,
  });

  Future<void> delete(int id);

  Future<Payout?> getLast();

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
    if (accountId == null) {
      throw ArgumentError('accountId is required for payouts');
    }
    final db = await _db;
    final normalizedDate = _normalizeDate(date);
    return db.transaction((txn) async {
      final payout = Payout(
        type: type,
        date: normalizedDate,
        amountMinor: amountMinor,
        accountId: accountId,
      );
      final payoutValues = _payoutValues(payout);
      final payoutId = await txn.insert('payouts', payoutValues);
      await _syncIncomeTransaction(
        txn,
        payoutId: payoutId,
        type: type,
        date: normalizedDate,
        amountMinor: amountMinor,
        accountId: accountId,
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
    required int accountId,
  }) async {
    final db = await _db;
    final normalizedDate = _normalizeDate(date);
    await db.transaction((txn) async {
      final payout = Payout(
        id: id,
        type: type,
        date: normalizedDate,
        amountMinor: amountMinor,
        accountId: accountId,
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
        date: normalizedDate,
        amountMinor: amountMinor,
        accountId: accountId,
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
      'included_in_period': 0,
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

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}
