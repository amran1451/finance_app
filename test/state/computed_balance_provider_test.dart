import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/state/app_providers.dart';
import 'package:finance_app/state/db_refresh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;

  setUp(() async {
    dbDir = await Directory.systemTemp.createTemp('computed_balance_test');
    final dbPath = p.join(dbDir.path, 'finance_app.db');

    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(dbDir.path);
    await deleteDatabase(dbPath);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await dbDir.delete(recursive: true);
  });

  test('computedBalanceProvider recomputes after db tick bump', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appBootstrapProvider.future);

    final accounts = await container.read(activeAccountsProvider.future);
    expect(accounts, isNotEmpty);
    final accountId = accounts.first.id!;

    final initial = await container.read(computedBalanceProvider(accountId).future);
    expect(initial, 0);

    final db = await AppDatabase.instance.database;

    final categoryId = await db.insert('categories', {
      'name': 'Test Category',
      'type': 'expense',
      'is_group': 0,
      'parent_id': null,
      'archived': 0,
    });

    await db.insert('transactions', {
      'account_id': accountId,
      'category_id': categoryId,
      'type': 'expense',
      'amount_minor': 2500,
      'date': '2024-01-10',
      'is_planned': 0,
      'included_in_period': 1,
    });

    bumpDbTick(container);

    final updated = await container.read(computedBalanceProvider(accountId).future);
    expect(updated, -2500);
  });
}
