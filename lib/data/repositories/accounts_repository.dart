import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/account.dart';

abstract class AccountsRepository {
  Future<List<Account>> getAll();

  Future<Account?> getById(int id);

  Future<int> create(Account account);

  Future<void> update(Account account);

  Future<void> delete(int id);

  Future<int> getComputedBalanceMinor(int accountId);

  Future<void> reconcileToComputed(int accountId);
}

class SqliteAccountsRepository implements AccountsRepository {
  SqliteAccountsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  static const String savingsAccountName = 'Сберегательный';

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> create(Account account) async {
    final db = await _db;
    final values = account.toMap()..remove('id');
    return db.insert('accounts', values);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Account>> getAll() async {
    final db = await _db;
    final rows = await db.query('accounts', orderBy: 'name');
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
  Future<int> getComputedBalanceMinor(int accountId) async {
    final db = await _db;
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
      WHERE account_id = ? AND is_planned = 0 AND included_in_period = 1
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
  Future<void> reconcileToComputed(int accountId) async {
    final computed = await getComputedBalanceMinor(accountId);
    final db = await _db;
    await db.update(
      'accounts',
      {'start_balance_minor': computed},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  @override
  Future<void> update(Account account) async {
    final id = account.id;
    if (id == null) {
      throw ArgumentError('Account id is required for update');
    }
    final db = await _db;
    await db.update(
      'accounts',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  int _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}
