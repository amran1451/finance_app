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
    final payout = Payout(
      type: type,
      date: date,
      amountMinor: amountMinor,
      accountId: accountId,
    );
    final values = payout.toMap()..remove('id');
    return db.insert('payouts', values);
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
}
