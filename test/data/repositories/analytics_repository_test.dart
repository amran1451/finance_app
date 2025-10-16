import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/models/analytics.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/data/repositories/analytics_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;
  late Database db;
  late AnalyticsRepository repository;
  late int accountId;
  late int groceriesCategoryId;
  late int transportCategoryId;
  late int plannedMasterId;

  setUp(() async {
    dbDir = await Directory.systemTemp.createTemp('analytics_repo_test');
    final dbPath = p.join(dbDir.path, 'finance_app.db');

    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(dbDir.path);
    await deleteDatabase(dbPath);

    db = await AppDatabase.instance.database;
    repository = AnalyticsRepository();

    accountId = await db.insert('accounts', {
      'name': 'Wallet',
      'currency': 'RUB',
      'start_balance_minor': 0,
      'is_archived': 0,
    });

    groceriesCategoryId = await db.insert('categories', {
      'name': 'Продукты',
      'type': 'expense',
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    });

    transportCategoryId = await db.insert('categories', {
      'name': 'Транспорт',
      'type': 'expense',
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    });

    final necessityId = await db.insert('necessity_labels', {
      'name': 'Важно',
      'color': '#FF7043',
      'archived': 0,
    });

    await db.insert('reason_labels', {
      'name': 'Эмоции',
      'color': '#BA68C8',
      'archived': 0,
    });

    plannedMasterId = await db.insert('planned_master', {
      'type': 'expense',
      'title': 'Продукты',
      'default_amount_minor': 10000,
      'category_id': groceriesCategoryId,
      'note': null,
      'necessity_id': necessityId,
      'archived': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await dbDir.delete(recursive: true);
  });

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  test('loadExpenseBreakdown aggregates planned categories with fallbacks', () async {
    final from = DateTime(2024, 1, 1);
    final to = DateTime(2024, 1, 31);

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': null,
      'type': 'expense',
      'amount_minor': 5200,
      'date': _formatDate(DateTime(2024, 1, 10)),
      'is_planned': 0,
      'planned_id': plannedMasterId,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': groceriesCategoryId,
      'type': 'expense',
      'amount_minor': 3200,
      'date': _formatDate(DateTime(2024, 1, 12)),
      'is_planned': 0,
      'planned_id': plannedMasterId,
      'included_in_period': 1,
    });

    final slices = await repository.loadExpenseBreakdown(
      breakdown: AnalyticsBreakdown.plannedCategory,
      from: from,
      to: to,
      type: TransactionType.expense,
      plannedOnly: true,
    );

    expect(slices, hasLength(1));
    expect(slices.first.label, 'Продукты');
    expect(slices.first.valueMinor, 8400);
    expect(slices.first.operationCount, 2);
  });

  test('loadExpenseBreakdown excludes plan checkbox operations from totals', () async {
    final from = DateTime(2024, 1, 1);
    final to = DateTime(2024, 1, 31);

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': groceriesCategoryId,
      'type': 'expense',
      'amount_minor': 4200,
      'date': _formatDate(DateTime(2024, 1, 5)),
      'is_planned': 0,
      'planned_id': plannedMasterId,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': groceriesCategoryId,
      'type': 'expense',
      'amount_minor': 3100,
      'date': _formatDate(DateTime(2024, 1, 6)),
      'is_planned': 0,
      'planned_id': plannedMasterId,
      'plan_instance_id': 777,
      'source': 'plan',
      'included_in_period': 1,
    });

    final slices = await repository.loadExpenseBreakdown(
      breakdown: AnalyticsBreakdown.plannedCategory,
      from: from,
      to: to,
      type: TransactionType.expense,
      plannedOnly: true,
    );

    expect(slices, hasLength(1));
    expect(slices.first.valueMinor, 4200);
    expect(slices.first.operationCount, 1);
  });

  test('loadExpenseBreakdown groups unplanned by reason', () async {
    final from = DateTime(2024, 2, 1);
    final to = DateTime(2024, 2, 28);

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 1500,
      'date': _formatDate(DateTime(2024, 2, 5)),
      'is_planned': 0,
      'planned_id': null,
      'reason_id': 1,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 2500,
      'date': _formatDate(DateTime(2024, 2, 7)),
      'is_planned': 0,
      'planned_id': null,
      'reason_id': 1,
      'included_in_period': 1,
    });

    final slices = await repository.loadExpenseBreakdown(
      breakdown: AnalyticsBreakdown.unplannedReason,
      from: from,
      to: to,
      unplannedOnly: true,
    );

    expect(slices, hasLength(1));
    final reasonSlice = slices.first;
    expect(reasonSlice.label, 'Эмоции');
    expect(reasonSlice.valueMinor, 4000);
    expect(reasonSlice.operationCount, 2);
  });

  test('loadExpenseSeries ignores plan checkbox operations in totals', () async {
    final from = DateTime(2024, 3, 1);
    final to = DateTime(2024, 3, 5);

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 1500,
      'date': _formatDate(DateTime(2024, 3, 2)),
      'is_planned': 0,
      'planned_id': null,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 2750,
      'date': _formatDate(DateTime(2024, 3, 2)),
      'is_planned': 0,
      'planned_id': null,
      'plan_instance_id': 333,
      'source': 'plan',
      'included_in_period': 1,
    });

    final series = await repository.loadExpenseSeries(
      breakdown: AnalyticsInterval.days,
      from: from,
      to: to,
      type: TransactionType.expense,
    );

    expect(series, hasLength(1));
    expect(series.first.valueMinor, 1500);
  });

  test('loadExpenseSeries aggregates by days respecting filters', () async {
    final from = DateTime(2024, 3, 1);
    final to = DateTime(2024, 3, 5);

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 1500,
      'date': _formatDate(DateTime(2024, 3, 2)),
      'is_planned': 0,
      'planned_id': null,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 2000,
      'date': _formatDate(DateTime(2024, 3, 2)),
      'is_planned': 0,
      'planned_id': null,
      'included_in_period': 1,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': transportCategoryId,
      'type': 'expense',
      'amount_minor': 3000,
      'date': _formatDate(DateTime(2024, 3, 4)),
      'is_planned': 0,
      'planned_id': null,
      'included_in_period': 1,
    });

    final series = await repository.loadExpenseSeries(
      interval: AnalyticsInterval.days,
      from: from,
      to: to,
      unplannedOnly: true,
    );

    expect(series, hasLength(2));
    expect(series.first.bucket, '2024-03-02');
    expect(series.first.valueMinor, 3500);
    expect(series[1].bucket, '2024-03-04');
    expect(series[1].valueMinor, 3000);
  });
}
