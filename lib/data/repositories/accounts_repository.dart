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

  Future<void> reconcileToComputed(int accountId,
      {DatabaseExecutor? executor});
}

class SqliteAccountsRepository implements AccountsRepository {
  SqliteAccountsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  static const String savingsAccountName = 'Сберегательный';

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
    final accountRow = await db.query(
      'accounts',
      columns: ['start_balance_minor', 'name'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (accountRow.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'Account not found');
    }
    final startBalance = (accountRow.first['start_balance_minor'] as int?) ?? 0;
    final name = accountRow.first['name'] as String? ?? '';
    final isSavingsAccount =
        name.trim().toLowerCase() == savingsAccountName.toLowerCase();

    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor END), 0) AS income_sum,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor END), 0) AS expense_sum,
        COALESCE(SUM(CASE WHEN type = 'saving' THEN amount_minor END), 0) AS saving_sum
      FROM transactions
      WHERE account_id = ? AND is_planned = 0
      ''',
      [accountId],
    );
    final row = result.first;
    final incomeSum = _readInt(row['income_sum']);
    final expenseSum = _readInt(row['expense_sum']);
    final savingSum = _readInt(row['saving_sum']);

    final incomingSaving = isSavingsAccount ? savingSum : 0;
    final outgoingSaving = isSavingsAccount ? 0 : savingSum;

    return startBalance + incomeSum - expenseSum + incomingSaving - outgoingSaving;
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

  int _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}
