import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/account.dart';

abstract class AccountsRepository {
  Future<List<Account>> getAll();

  Future<Account?> getById(int id);

  Future<List<Account>> listActive();

  Future<int> create(Account account, {DatabaseExecutor? executor});

  Future<void> update(Account account, {DatabaseExecutor? executor});

  Future<void> delete(int id, {DatabaseExecutor? executor});

  Future<int> getComputedBalanceMinor(int accountId,
      {DatabaseExecutor? executor});

  Stream<int> watchAccountBalance(int accountId);

  Future<void> reconcileToComputed(int accountId,
      {DatabaseExecutor? executor});
}

class SqliteAccountsRepository implements AccountsRepository {
  SqliteAccountsRepository({AppDatabase? database, Stream<void>? dbTickStream})
      : _database = database ?? AppDatabase.instance,
        _dbTickStream = dbTickStream ?? const Stream<void>.empty();

  static const String savingsAccountName = 'Сберегательный';

  final AppDatabase _database;
  final Stream<void> _dbTickStream;

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
  Future<int> create(Account account, {DatabaseExecutor? executor}) async {
    final values = account.toMap()..remove('id');
    return _runWrite<int>(
      (db) => db.insert('accounts', values),
      executor: executor,
      debugContext: 'accounts.create',
    );
  }

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (db) async {
        await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
      },
      executor: executor,
      debugContext: 'accounts.delete',
    );
  }

  @override
  Future<List<Account>> getAll() async {
    final db = await _db;
    final rows = await db.query('accounts', orderBy: 'name');
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<List<Account>> listActive() async {
    final db = await _db;
    final rows = await db.query(
      'accounts',
      where: 'is_archived = 0',
      orderBy: 'name',
    );
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<Account?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Account.fromMap(rows.first);
  }

  @override
  Future<int> getComputedBalanceMinor(int accountId,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
    return calcAccountBalance(db, accountId);
  }

  Future<int> calcAccountBalance(DatabaseExecutor db, int accountId) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(a.start_balance_minor, 0)
        + COALESCE(SUM(
           CASE
             WHEN t.type = 'income' THEN t.amount_minor
             WHEN t.type = 'expense' THEN -t.amount_minor
             WHEN t.type = 'saving' THEN CASE
               WHEN LOWER(a.name) = ? THEN t.amount_minor
               ELSE -t.amount_minor
             END
             ELSE 0
           END
        ), 0) AS balance
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id
        AND (t.is_planned = 0 OR t.plan_instance_id IS NOT NULL)
        AND t.deleted = 0
      WHERE a.id = ?
      GROUP BY a.id
      ''',
      [savingsAccountName.toLowerCase(), accountId],
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'Account not found');
    }
    final value = rows.first['balance'] as num?;
    return value?.toInt() ?? 0;
  }

  @override
  Future<void> reconcileToComputed(int accountId,
      {DatabaseExecutor? executor}) async {
    await _runWrite<void>(
      (db) async {
        final computed = await getComputedBalanceMinor(
          accountId,
          executor: db,
        );
        await db.update(
          'accounts',
          {'start_balance_minor': computed},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      },
      executor: executor,
      debugContext: 'accounts.reconcile',
    );
  }

  @override
  Stream<int> watchAccountBalance(int accountId) async* {
    Future<int> load() async {
      try {
        return await getComputedBalanceMinor(accountId);
      } on ArgumentError {
        return 0;
      }
    }

    yield await load();
    await for (final _ in _dbTickStream) {
      yield await load();
    }
  }

  @override
  Future<void> update(Account account, {DatabaseExecutor? executor}) async {
    final id = account.id;
    if (id == null) {
      throw ArgumentError('Account id is required for update');
    }
    await _runWrite<void>(
      (db) async {
        await db.update(
          'accounts',
          account.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      },
      executor: executor,
      debugContext: 'accounts.update',
    );
  }

}
