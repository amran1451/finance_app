import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/models/payout.dart';
import 'package:finance_app/data/repositories/payouts_repository.dart';
import 'package:finance_app/utils/period_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;
  late Database db;
  late PayoutsRepository repository;
  late int accountId;

  setUp(() async {
    dbDir = await Directory.systemTemp.createTemp('payouts_repo_test');
    final dbPath = p.join(dbDir.path, 'finance_app.db');

    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(dbDir.path);
    await deleteDatabase(dbPath);

    db = await AppDatabase.instance.database;
    repository = SqlitePayoutsRepository();

    accountId = await db.insert('accounts', {
      'name': 'Карта',
      'currency': 'RUB',
      'start_balance_minor': 0,
      'is_archived': 0,
    });
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final dbPath = p.join(dbDir.path, 'finance_app.db');
    await deleteDatabase(dbPath);
    if (dbDir.existsSync()) {
      await dbDir.delete(recursive: true);
    }
  });

  PeriodRef _period(HalfPeriod half) =>
      PeriodRef(year: 2024, month: 1, half: half);

  test('throws when salary is recorded in the first half', () async {
    await expectLater(
      repository.upsertWithClampToSelectedPeriod(
        selectedPeriod: _period(HalfPeriod.first),
        pickedDate: DateTime(2024, 1, 5),
        type: PayoutType.salary,
        amountMinor: 10_000,
        accountId: accountId,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when advance is recorded in the second half', () async {
    await expectLater(
      repository.upsertWithClampToSelectedPeriod(
        selectedPeriod: _period(HalfPeriod.second),
        pickedDate: DateTime(2024, 1, 20),
        type: PayoutType.advance,
        amountMinor: 15_000,
        accountId: accountId,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('allows advance in the first half', () async {
    final result = await repository.upsertWithClampToSelectedPeriod(
      selectedPeriod: _period(HalfPeriod.first),
      pickedDate: DateTime(2024, 1, 6),
      type: PayoutType.advance,
      amountMinor: 12_500,
      accountId: accountId,
    );

    expect(result.payout.type, PayoutType.advance);
    expect(result.period.half, HalfPeriod.first);
  });

  test('allows early salary in the second half within grace period', () async {
    final result = await repository.upsertWithClampToSelectedPeriod(
      selectedPeriod: _period(HalfPeriod.second),
      pickedDate: DateTime(2024, 1, 12),
      type: PayoutType.salary,
      amountMinor: 20_000,
      accountId: accountId,
      shiftPeriodStart: true,
    );

    expect(result.payout.type, PayoutType.salary);
    expect(result.period.half, HalfPeriod.second);
  });
}
