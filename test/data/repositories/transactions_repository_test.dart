import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/repositories/accounts_repository.dart';
import 'package:finance_app/data/repositories/transactions_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;
  late Database db;
  late TransactionsRepository repository;
  late int accountId;
  late int categoryId;
  late AccountsRepository accountsRepository;

  String formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  Future<void> insertTransaction({
    required DateTime date,
    required int amountMinor,
    required bool included,
    bool planned = false,
  }) async {
    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': categoryId,
      'type': 'expense',
      'amount_minor': amountMinor,
      'date': formatDate(date),
      'is_planned': planned ? 1 : 0,
      'included_in_period': included ? 1 : 0,
    });
  }

  setUp(() async {
    dbDir = await Directory.systemTemp.createTemp('transactions_repo_test');
    final dbPath = p.join(dbDir.path, 'finance_app.db');

    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(dbDir.path);
    await deleteDatabase(dbPath);

    db = await AppDatabase.instance.database;
    repository = SqliteTransactionsRepository();
    accountsRepository = SqliteAccountsRepository();

    accountId = await db.insert('accounts', {
      'name': 'Wallet',
      'currency': 'RUB',
      'start_balance_minor': 0,
      'is_archived': 0,
    });

    categoryId = await db.insert('categories', {
      'name': 'Groceries',
      'type': 'expense',
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    });
  });

  test(
      'assignMasterToPeriod stores account id and inclusion updates account balance',
      () async {
    final masterId = await db.insert('planned_master', {
      'type': 'expense',
      'title': 'Groceries Plan',
      'default_amount_minor': 1000,
      'category_id': categoryId,
      'note': null,
      'archived': 0,
    });
    final start = DateTime(2024, 1, 1);
    final endExclusive = DateTime(2024, 2, 1);

    await repository.assignMasterToPeriod(
      masterId: masterId,
      start: start,
      endExclusive: endExclusive,
      categoryId: categoryId,
      amountMinor: 1500,
      included: false,
      accountId: accountId,
    );

    final plannedRows = await db.query(
      'transactions',
      where: 'planned_id = ?',
      whereArgs: [masterId],
      limit: 1,
    );
    expect(plannedRows, hasLength(1));
    final planned = plannedRows.first;
    expect(planned['account_id'], accountId);
    expect(planned['is_planned'], 1);

    final plannedId = planned['id'] as int;

    final balanceBefore = await accountsRepository.getComputedBalanceMinor(accountId);
    expect(balanceBefore, 0);

    await repository.setPlannedIncluded(plannedId, true);

    final actualRows = await db.query(
      'transactions',
      where: 'plan_instance_id = ? AND is_planned = 0',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(actualRows, hasLength(1));
    expect(actualRows.first['account_id'], accountId);

    final balanceAfter = await accountsRepository.getComputedBalanceMinor(accountId);
    expect(balanceAfter, -1500);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final dbPath = p.join(dbDir.path, 'finance_app.db');
    await deleteDatabase(dbPath);
    if (dbDir.existsSync()) {
      await dbDir.delete(recursive: true);
    }
  });

  test('sumUnplannedExpensesInRange ignores excluded transactions', () async {
    final start = DateTime(2024, 1, 10);

    await insertTransaction(
      date: start,
      amountMinor: 500,
      included: true,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 1)),
      amountMinor: 300,
      included: false,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 2)),
      amountMinor: 700,
      included: true,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 5)),
      amountMinor: 900,
      included: true,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 1)),
      amountMinor: 400,
      included: true,
      planned: true,
    );

    final total = await repository.sumUnplannedExpensesInRange(
      start,
      start.add(const Duration(days: 3)),
    );

    expect(total, 1200);
  });

  test('getByPeriod with includedInPeriod filter returns only included records',
      () async {
    final start = DateTime(2024, 1, 10);

    await insertTransaction(
      date: start,
      amountMinor: 250,
      included: true,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 1)),
      amountMinor: 150,
      included: false,
    );
    await insertTransaction(
      date: start.add(const Duration(days: 2)),
      amountMinor: 450,
      included: true,
    );

    final records = await repository.getByPeriod(
      start,
      start.add(const Duration(days: 2)),
      isPlanned: false,
      includedInPeriod: true,
    );

    expect(records, hasLength(2));
    expect(records.every((record) => record.includedInPeriod), isTrue);
    expect(records.map((record) => record.amountMinor).toList(), [450, 250]);
  });
}
