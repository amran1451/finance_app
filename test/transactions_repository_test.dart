import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/data/repositories/transactions_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String databasePath;

  setUpAll(() async {
    final basePath = await getDatabasesPath();
    databasePath = p.join(basePath, 'finance_app.db');
  });

  setUp(() async {
    await AppDatabase.instance.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('sumUnplannedExpensesInRange ignores transactions excluded from period', () async {
    final repository = SqliteTransactionsRepository();
    final db = await AppDatabase.instance.database;

    await db.insert('accounts', {
      'id': 1,
      'name': 'Cash',
      'currency': 'RUB',
      'start_balance_minor': 0,
      'is_archived': 0,
    });

    await db.insert('categories', {
      'id': 1,
      'type': 'expense',
      'name': 'Groceries',
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    });

    final date = DateTime(2024, 1, 10);

    await repository.add(
      TransactionRecord(
        accountId: 1,
        categoryId: 1,
        type: TransactionType.expense,
        amountMinor: 5000,
        date: date,
        isPlanned: false,
        includedInPeriod: true,
      ),
    );

    await repository.add(
      TransactionRecord(
        accountId: 1,
        categoryId: 1,
        type: TransactionType.expense,
        amountMinor: 7000,
        date: date,
        isPlanned: false,
        includedInPeriod: false,
      ),
    );

    await repository.add(
      TransactionRecord(
        accountId: 1,
        categoryId: 1,
        type: TransactionType.expense,
        amountMinor: 9000,
        date: date,
        isPlanned: true,
        includedInPeriod: true,
      ),
    );

    final total = await repository.sumUnplannedExpensesInRange(
      date,
      date.add(const Duration(days: 1)),
    );

    expect(total, 5000);
  });
}
