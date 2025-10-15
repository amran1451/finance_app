import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/repositories/accounts_repository.dart';
import 'package:finance_app/data/repositories/transactions_repository.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/utils/period_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;
  late Database db;
  late TransactionsRepository repository;
  late int accountId;
  late int categoryId;
  late AccountsRepository accountsRepository;
  const anchors = (1, 15);

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
    PeriodRef? period,
    int? planId,
  }) async {
    final resolvedPeriod =
        period ?? periodRefForDate(date, anchors.$1, anchors.$2);
    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': categoryId,
      'type': 'expense',
      'amount_minor': amountMinor,
      'date': formatDate(date),
      'is_planned': planned ? 1 : 0,
      'included_in_period': included ? 1 : 0,
      'period_id': resolvedPeriod.id,
      'planned_id': planId,
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
      period: const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first),
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

  test('sumPlannedExpenses counts only plans marked as included', () async {
    final period = const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first);
    final start = DateTime(2024, 1, 1);
    final endExclusive = DateTime(2024, 2, 1);

    final masterId = await db.insert('planned_master', {
      'type': 'expense',
      'title': 'Groceries Plan',
      'default_amount_minor': 1000,
      'category_id': categoryId,
      'note': null,
      'archived': 0,
    });

    await repository.assignMasterToPeriod(
      masterId: masterId,
      period: period,
      start: start,
      endExclusive: endExclusive,
      categoryId: categoryId,
      amountMinor: 1500,
      included: true,
      accountId: accountId,
    );

    final plannedRows = await db.query(
      'transactions',
      where: 'is_planned = 1 AND planned_id = ?',
      whereArgs: [masterId],
      limit: 1,
    );
    expect(plannedRows, hasLength(1));
    final plannedId = plannedRows.first['id'] as int;

    final initialTotal = await repository.sumPlannedExpenses(
      period: period,
      start: start,
      endExclusive: endExclusive,
      periodId: period.id,
    );
    expect(initialTotal, 1500);

    await repository.setPlannedIncluded(plannedId, false);

    final afterToggleOff = await repository.sumPlannedExpenses(
      period: period,
      start: start,
      endExclusive: endExclusive,
      periodId: period.id,
    );
    expect(afterToggleOff, 0);

    await repository.setPlannedIncluded(plannedId, true);

    await db.update(
      'transactions',
      {'amount_minor': 2000},
      where: 'id = ?',
      whereArgs: [plannedId],
    );

    final afterAmountChange = await repository.sumPlannedExpenses(
      period: period,
      start: start,
      endExclusive: endExclusive,
      periodId: period.id,
    );
    expect(afterAmountChange, 2000);
  });

  test('updating actual plan instance keeps it linked to original planned item',
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
      period: const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first),
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
    final plannedId = plannedRows.first['id'] as int;

    await repository.setPlannedIncluded(plannedId, true);

    final actualRows = await db.query(
      'transactions',
      where: 'plan_instance_id = ? AND is_planned = 0',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(actualRows, hasLength(1));

    final actual = TransactionRecord.fromMap(actualRows.first);
    final updatedDate = DateTime(2024, 1, 15);

    await repository.update(
      actual.copyWith(date: updatedDate),
      includedInPeriod: true,
      uiPeriod: const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first),
    );

    final updatedRows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [actual.id],
      limit: 1,
    );
    expect(updatedRows, hasLength(1));
    final updated = TransactionRecord.fromMap(updatedRows.first);
    expect(updated.date, updatedDate);
    expect(updated.planInstanceId, plannedId);
    expect(updated.source?.toLowerCase(), 'plan');

    final plannedRowsAfter = await db.query(
      'transactions',
      where: 'planned_id = ?',
      whereArgs: [masterId],
      limit: 1,
    );
    expect(plannedRowsAfter, hasLength(1));
    expect(plannedRowsAfter.first['id'], plannedId);
  });

  test('deleting actual plan record resets inclusion instead of removing plan',
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
      period: const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first),
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
    final plannedId = plannedRows.first['id'] as int;

    await repository.setPlannedIncluded(plannedId, true);

    final actualRows = await db.query(
      'transactions',
      where: 'plan_instance_id = ? AND is_planned = 0',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(actualRows, hasLength(1));
    final actualId = actualRows.first['id'] as int;

    await repository.delete(actualId);

    final plannedAfterDeletion = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(plannedAfterDeletion, hasLength(1));
    expect(plannedAfterDeletion.first['included_in_period'], 0);

    final actualAfterDeletion = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [actualId],
      limit: 1,
    );
    expect(actualAfterDeletion, isEmpty);
  });

  test('deleting plan instance without explicit source resets inclusion',
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
      period: const PeriodRef(year: 2024, month: 1, half: HalfPeriod.first),
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
    final plannedId = plannedRows.first['id'] as int;

    await repository.setPlannedIncluded(plannedId, true);

    final actualRows = await db.query(
      'transactions',
      where: 'plan_instance_id = ? AND is_planned = 0',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(actualRows, hasLength(1));
    final actualId = actualRows.first['id'] as int;

    // Simulate legacy data with trimmed/uppercase source values.
    await db.update(
      'transactions',
      {'source': ' PLAN  '},
      where: 'id = ?',
      whereArgs: [actualId],
    );

    await repository.delete(actualId);

    final plannedAfterDeletion = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [plannedId],
      limit: 1,
    );
    expect(plannedAfterDeletion, hasLength(1));
    expect(plannedAfterDeletion.first['included_in_period'], 0);

    final actualAfterDeletion = await db.query(
      'transactions',
      where: 'plan_instance_id = ?',
      whereArgs: [plannedId],
    );
    expect(actualAfterDeletion, isEmpty);
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
      date: start.add(const Duration(days: 2)),
      amountMinor: 650,
      included: true,
      planId: 42,
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

    const period = PeriodRef(year: 2024, month: 1, half: HalfPeriod.first);
    final total = await repository.sumUnplannedExpensesInRange(
      start,
      start.add(const Duration(days: 3)),
      periodId: period.id,
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

  test('sumExpensesOnDateWithinPeriod counts only included operations', () async {
    final periodStart = DateTime(2024, 1, 1);
    final periodEndExclusive = DateTime(2024, 2, 1);
    final targetDate = DateTime(2024, 1, 15);

    await insertTransaction(
      date: targetDate,
      amountMinor: 1_500,
      included: true,
    );
    await insertTransaction(
      date: targetDate,
      amountMinor: 2_000,
      included: false,
    );
    await insertTransaction(
      date: targetDate.add(const Duration(days: 1)),
      amountMinor: 3_000,
      included: true,
    );
    await insertTransaction(
      date: targetDate,
      amountMinor: 2_500,
      included: true,
      planId: 77,
    );

    const period = PeriodRef(year: 2024, month: 1, half: HalfPeriod.first);
    final total = await repository.sumExpensesOnDateWithinPeriod(
      date: targetDate,
      periodStart: periodStart,
      periodEndExclusive: periodEndExclusive,
      periodId: period.id,
    );

    expect(total, 1_500);
  });

  test('sumActualExpenses excludes transactions not included in period', () async {
    const period = PeriodRef(year: 2024, month: 1, half: HalfPeriod.first);
    final periodStart = DateTime(2024, 1, 1);
    final periodEndExclusive = DateTime(2024, 2, 1);

    await insertTransaction(
      date: DateTime(2024, 1, 5),
      amountMinor: 800,
      included: true,
    );
    await insertTransaction(
      date: DateTime(2024, 1, 12),
      amountMinor: 1_200,
      included: false,
    );
    await insertTransaction(
      date: DateTime(2024, 1, 20),
      amountMinor: 600,
      included: true,
      planned: true,
    );
    await insertTransaction(
      date: DateTime(2024, 1, 25),
      amountMinor: 500,
      included: true,
    );
    await insertTransaction(
      date: DateTime(2024, 1, 18),
      amountMinor: 400,
      included: true,
      planId: 108,
    );
    await insertTransaction(
      date: DateTime(2024, 2, 1),
      amountMinor: 700,
      included: true,
    );

    final total = await repository.sumActualExpenses(
      period: period,
      start: periodStart,
      endExclusive: periodEndExclusive,
      periodId: period.id,
    );

    expect(total, 1_300);
  });
}
