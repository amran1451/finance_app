import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/category.dart';
import '../models/transaction_record.dart';
import 'accounts_repository.dart';

abstract class TransactionsRepository {
  Future<TransactionRecord?> getById(int id);

  Future<List<TransactionRecord>> getAll();

  Future<List<TransactionRecord>> getByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    bool? isPlanned,
    bool? includedInPeriod,
  });

  Future<int> add(TransactionRecord record, {bool asSavingPair = false});

  Future<void> update(TransactionRecord record);

  Future<void> delete(int id);
}

class SqliteTransactionsRepository implements TransactionsRepository {
  SqliteTransactionsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> add(TransactionRecord record, {bool asSavingPair = false}) async {
    final db = await _db;
    return db.transaction((txn) async {
      final categoryType = await _getCategoryType(txn, record.categoryId);
      final adjustedRecord = record.copyWith(
        id: null,
        type: categoryType == CategoryType.saving
            ? TransactionType.saving
            : record.type,
      );
      final primaryValues = Map<String, Object?>.from(adjustedRecord.toMap())
        ..remove('id');
      final primaryId = await txn.insert('transactions', primaryValues);

      if (asSavingPair && categoryType == CategoryType.saving) {
        final savingsAccountId = await _findSavingsAccountId(txn);
        if (savingsAccountId == null) {
          throw StateError(
            'Счёт "${SqliteAccountsRepository.savingsAccountName}" не найден',
          );
        }
        if (savingsAccountId != record.accountId) {
          final pairRecord = adjustedRecord.copyWith(
            id: null,
            accountId: savingsAccountId,
          );
          final pairValues = Map<String, Object?>.from(pairRecord.toMap())
            ..remove('id');
          await txn.insert('transactions', pairValues);
        }
      }

      return primaryId;
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<TransactionRecord>> getAll() async {
    final db = await _db;
    final rows = await db.query('transactions', orderBy: 'date DESC, id DESC');
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<TransactionRecord?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return TransactionRecord.fromMap(rows.first);
  }

  @override
  Future<List<TransactionRecord>> getByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    bool? isPlanned,
    bool? includedInPeriod,
  }) async {
    final db = await _db;
    final where = StringBuffer('date >= ? AND date <= ?');
    final args = <Object?>[_formatDate(from), _formatDate(to)];

    if (accountId != null) {
      where.write(' AND account_id = ?');
      args.add(accountId);
    }
    if (categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(categoryId);
    }
    if (isPlanned != null) {
      where.write(' AND is_planned = ?');
      args.add(isPlanned ? 1 : 0);
    }
    if (includedInPeriod != null) {
      where.write(' AND included_in_period = ?');
      args.add(includedInPeriod ? 1 : 0);
    }

    final rows = await db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<void> update(TransactionRecord record) async {
    final id = record.id;
    if (id == null) {
      throw ArgumentError('Transaction id is required for update');
    }
    final db = await _db;
    await db.update(
      'transactions',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<CategoryType> _getCategoryType(DatabaseExecutor executor, int id) async {
    final rows = await executor.query(
      'categories',
      columns: ['type'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Category not found');
    }
    return _typeFromString(rows.first['type'] as String?);
  }

  Future<int?> _findSavingsAccountId(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'accounts',
      columns: ['id', 'name'],
      where: 'LOWER(name) = ?',
      whereArgs: [SqliteAccountsRepository.savingsAccountName.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id'] as int?;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  CategoryType _typeFromString(String? raw) {
    switch (raw) {
      case 'income':
        return CategoryType.income;
      case 'expense':
        return CategoryType.expense;
      case 'saving':
        return CategoryType.saving;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown category type');
    }
  }
}
