import 'package:sqflite/sqflite.dart';

import '../../utils/period_utils.dart';
import '../db/app_database.dart';
import '../models/category.dart';
import '../models/transaction_record.dart';
import 'accounts_repository.dart';

typedef TransactionItem = TransactionRecord;

class TransactionListItem {
  const TransactionListItem({
    required this.record,
    this.savingPairId,
    this.savingCounterpart,
  });

  final TransactionRecord record;
  final int? savingPairId;
  final TransactionRecord? savingCounterpart;

  bool get isSavingPair => savingCounterpart != null;
}

abstract class TransactionsRepository {
  Future<TransactionRecord?> getById(int id);

  Future<List<TransactionRecord>> getAll();

  Future<List<TransactionRecord>> getByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
  });

  Future<List<TransactionListItem>> getOperationItemsByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
    bool aggregateSavingPairs = false,
  });

  Future<int> add(
    TransactionRecord record, {
    bool asSavingPair = false,
    bool? includedInPeriod,
  });

  Future<void> update(
    TransactionRecord record, {
    bool? includedInPeriod,
  });

  Future<void> delete(int id);

  Future<List<TransactionRecord>> listPlanned({
    TransactionType? type,
    bool onlyIncluded = false,
  });

  Future<int> createPlannedInstance({
    required int plannedId,
    required String type,
    required int accountId,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    String? note,
    int? necessityId,
    String? necessityLabel,
    bool includedInPeriod = false,
    int criticality = 0,
  });

  Future<void> assignMasterToPeriod({
    required int masterId,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required bool included,
    int? necessityId,
    String? note,
  });

  Future<List<TransactionItem>> listPlannedByPeriod({
    required DateTime start,
    required DateTime endExclusive,
    String? type,
    bool? onlyIncluded,
  });

  Future<int> deleteInstancesByPlannedId(int plannedId);

  Future<void> setPlannedCompletion(int id, bool isCompleted);

  Future<void> setIncludedInPeriod({
    required int transactionId,
    required bool value,
  });

  Future<int> sumIncludedPlannedExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  });

  Future<void> setPlannedIncluded(int plannedId, bool included);

  /// Сумма внеплановых расходов в [date] (учитывая границы активного периода)
  Future<int> sumUnplannedExpensesOnDate(DateTime date);

  /// Сумма внеплановых расходов в интервале [from, toExclusive)
  Future<int> sumUnplannedExpensesInRange(DateTime from, DateTime toExclusive);

  /// Сумма фактических расходов (type = 'expense', is_planned = 0)
  /// в пределах периода [start, endExclusive).
  Future<int> sumActualExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  });
}

class SqliteTransactionsRepository implements TransactionsRepository {
  SqliteTransactionsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> add(
    TransactionRecord record, {
    bool asSavingPair = false,
    bool? includedInPeriod,
  }) async {
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
      if (adjustedRecord.type == TransactionType.income) {
        primaryValues['necessity_id'] = null;
        primaryValues['necessity_label'] = null;
        primaryValues['reason_id'] = null;
        primaryValues['reason_label'] = null;
        primaryValues['criticality'] = 0;
      }
      if (includedInPeriod != null) {
        primaryValues['included_in_period'] = includedInPeriod ? 1 : 0;
      } else if (adjustedRecord.isPlanned) {
        primaryValues['included_in_period'] =
            adjustedRecord.includedInPeriod ? 1 : 0;
      }
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
          if (includedInPeriod != null) {
            pairValues['included_in_period'] = includedInPeriod ? 1 : 0;
          } else if (adjustedRecord.isPlanned) {
            pairValues['included_in_period'] =
                adjustedRecord.includedInPeriod ? 1 : 0;
          }
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
    TransactionType? type,
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
    if (type != null) {
      where.write(' AND type = ?');
      args.add(_typeToString(type));
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
  Future<List<TransactionListItem>> getOperationItemsByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
    bool aggregateSavingPairs = false,
  }) async {
    final records = await getByPeriod(
      from,
      to,
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      isPlanned: isPlanned,
      includedInPeriod: includedInPeriod,
    );
    if (!aggregateSavingPairs) {
      return [
        for (final record in records)
          TransactionListItem(record: record),
      ];
    }
    final db = await _db;
    final savingsAccountId = await _findSavingsAccountId(db);
    if (savingsAccountId == null) {
      return [
        for (final record in records)
          TransactionListItem(record: record),
      ];
    }
    return _aggregateSavingPairs(records, savingsAccountId);
  }

  @override
  Future<void> update(
    TransactionRecord record, {
    bool? includedInPeriod,
  }) async {
    final id = record.id;
    if (id == null) {
      throw ArgumentError('Transaction id is required for update');
    }
    final db = await _db;
    final values = Map<String, Object?>.from(record.toMap());
    values.remove('id');
    if (record.type == TransactionType.income) {
      values['necessity_id'] = null;
      values['necessity_label'] = null;
      values['reason_id'] = null;
      values['reason_label'] = null;
      values['criticality'] = 0;
    }
    if (includedInPeriod != null) {
      values['included_in_period'] = includedInPeriod ? 1 : 0;
    }
    await db.update(
      'transactions',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<TransactionRecord>> listPlanned({
    TransactionType? type,
    bool onlyIncluded = false,
  }) async {
    final db = await _db;
    final where = StringBuffer('is_planned = 1');
    final args = <Object?>[];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(_typeToString(type));
    }
    if (onlyIncluded) {
      where.write(' AND included_in_period = 1');
    }
    final rows = await db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<int> createPlannedInstance({
    required int plannedId,
    required String type,
    required int accountId,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    String? note,
    int? necessityId,
    String? necessityLabel,
    bool includedInPeriod = false,
    int criticality = 0,
  }) async {
    final db = await _db;
    final values = <String, Object?>{
      'planned_id': plannedId,
      'type': type,
      'account_id': accountId,
      'category_id': categoryId,
      'amount_minor': amountMinor,
      'date': _formatDate(date),
      'time': null,
      'note': note?.trim().isEmpty ?? true ? null : note?.trim(),
      'is_planned': 1,
      'included_in_period': includedInPeriod ? 1 : 0,
      'tags': null,
      'criticality': criticality,
      'necessity_id': necessityId,
      'necessity_label': necessityLabel,
      'reason_id': null,
      'reason_label': null,
      'payout_id': null,
    };
    return db.insert('transactions', values);
  }

  @override
  Future<void> assignMasterToPeriod({
    required int masterId,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required bool included,
    int? necessityId,
    String? note,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final masterRows = await txn.query(
        'planned_master',
        where: 'id = ?',
        whereArgs: [masterId],
        limit: 1,
      );
      if (masterRows.isEmpty) {
        throw StateError('Не найден шаблон с идентификатором $masterId');
      }
      final master = masterRows.first;
      final type = (master['type'] as String? ?? 'expense').toLowerCase();
      final sanitizedNote = note == null || note.trim().isEmpty ? null : note.trim();
      final necessityLabel = await _loadNecessityLabel(txn, necessityId);
      final instanceDate = _resolveInstanceDate(start, endExclusive);
      final values = <String, Object?>{
        'planned_id': masterId,
        'type': type,
        'account_id': 0,
        'category_id': categoryId,
        'amount_minor': amountMinor,
        'date': _formatDate(instanceDate),
        'time': null,
        'note': sanitizedNote,
        'is_planned': 1,
        'included_in_period': included ? 1 : 0,
        'tags': null,
        'criticality': 0,
        'necessity_id': necessityId,
        'necessity_label': necessityLabel,
        'reason_id': null,
        'reason_label': null,
        'payout_id': null,
      };
      await txn.insert('transactions', values);
    });
  }

  @override
  Future<List<TransactionItem>> listPlannedByPeriod({
    required DateTime start,
    required DateTime endExclusive,
    String? type,
    bool? onlyIncluded,
  }) async {
    final db = await _db;
    final where = StringBuffer('is_planned = 1 AND date >= ? AND date < ?');
    final args = <Object?>[_formatDate(start), _formatDate(endExclusive)];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type);
    }
    if (onlyIncluded != null) {
      where.write(' AND included_in_period = ?');
      args.add(onlyIncluded ? 1 : 0);
    }
    final rows = await db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<int> deleteInstancesByPlannedId(int plannedId) async {
    final db = await _db;
    return db.delete(
      'transactions',
      where: 'planned_id = ?',
      whereArgs: [plannedId],
    );
  }

  @override
  Future<void> setPlannedCompletion(int id, bool isCompleted) async {
    final db = await _db;
    await db.update(
      'transactions',
      {'included_in_period': isCompleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setIncludedInPeriod({
    required int transactionId,
    required bool value,
  }) async {
    final db = await _db;
    await db.update(
      'transactions',
      {'included_in_period': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  @override
  Future<int> sumIncludedPlannedExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    assert(start.isBefore(endExclusive), 'Empty period bounds for $period');
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor), 0) AS total '
      'FROM transactions '
      "WHERE is_planned = 1 AND included_in_period = 1 "
      "AND type = 'expense' AND date >= ? AND date < ?",
      [_formatDate(start), _formatDate(endExclusive)],
    );
    if (rows.isEmpty) {
      return 0;
    }
    final value = rows.first['total'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  @override
  Future<void> setPlannedIncluded(int plannedId, bool included) async {
    final db = await _db;
    await db.update(
      'transactions',
      {
        'included_in_period': included ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'is_planned = 1 AND id = ?',
      whereArgs: [plannedId],
    );
  }

  @override
  Future<int> sumUnplannedExpensesOnDate(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return sumUnplannedExpensesInRange(dayStart, dayEnd);
  }

  @override
  Future<int> sumUnplannedExpensesInRange(
    DateTime from,
    DateTime toExclusive,
  ) async {
    final normalizedFrom = DateTime(from.year, from.month, from.day);
    final normalizedTo = DateTime(toExclusive.year, toExclusive.month, toExclusive.day);
    if (!normalizedFrom.isBefore(normalizedTo)) {
      return 0;
    }

    final db = await _db;
    final endInclusive = normalizedTo.subtract(const Duration(days: 1));
    if (endInclusive.isBefore(normalizedFrom)) {
      return 0;
    }

    final rows = await db.rawQuery(
      'SELECT SUM(amount_minor) AS total '
      'FROM transactions '
      "WHERE type = 'expense' AND is_planned = 0 "
      "AND included_in_period = 1 AND date BETWEEN ? AND ?",
      [_formatDate(normalizedFrom), _formatDate(endInclusive)],
    );

    if (rows.isEmpty) {
      return 0;
    }

    final value = rows.first['total'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  @override
  Future<int> sumActualExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    assert(start.isBefore(endExclusive), 'Empty period bounds for $period');

    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor), 0) AS total '
      'FROM transactions '
      "WHERE type = 'expense' AND is_planned = 0 "
      'AND date >= ? AND date < ?',
      [_formatDate(start), _formatDate(endExclusive)],
    );

    if (rows.isEmpty) {
      return 0;
    }

    final value = rows.first['total'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
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

  DateTime _resolveInstanceDate(DateTime start, DateTime endExclusive) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEndExclusive =
        DateTime(endExclusive.year, endExclusive.month, endExclusive.day);
    if (normalizedEndExclusive.isAfter(normalizedStart)) {
      return normalizedStart;
    }
    return normalizedStart;
  }

  Future<String?> _loadNecessityLabel(DatabaseExecutor txn, int? id) async {
    if (id == null) {
      return null;
    }
    final rows = await txn.query(
      'necessity_labels',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['name'] as String?;
  }

  List<TransactionListItem> _aggregateSavingPairs(
    List<TransactionRecord> records,
    int savingsAccountId,
  ) {
    if (records.isEmpty) {
      return const [];
    }
    final usedIds = <int>{};
    final grouped = <String, List<TransactionRecord>>{};
    final pairMap = <int, TransactionRecord>{};
    for (final record in records) {
      final id = record.id;
      if (id == null) {
        continue;
      }
      if (record.type != TransactionType.saving || record.isPlanned) {
        continue;
      }
      final key = _savingPairKey(record);
      grouped.putIfAbsent(key, () => <TransactionRecord>[]).add(record);
    }

    for (final group in grouped.values) {
      if (group.length < 2) {
        continue;
      }
      final sources = <TransactionRecord>[];
      final savings = <TransactionRecord>[];
      for (final record in group) {
        final id = record.id;
        if (id == null) {
          continue;
        }
        if (record.accountId == savingsAccountId) {
          savings.add(record);
        } else {
          sources.add(record);
        }
      }
      if (sources.isEmpty || savings.isEmpty) {
        continue;
      }
      sources.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
      savings.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
      final count = sources.length < savings.length ? sources.length : savings.length;
      for (var i = 0; i < count; i++) {
        final source = sources[i];
        final savingsRecord = savings[i];
        final sourceId = source.id;
        final savingsId = savingsRecord.id;
        if (sourceId == null || savingsId == null) {
          continue;
        }
        pairMap[sourceId] = savingsRecord;
        pairMap[savingsId] = source;
      }
    }

    final result = <TransactionListItem>[];
    for (final record in records) {
      final id = record.id;
      if (id != null && usedIds.contains(id)) {
        continue;
      }

      if (id != null && pairMap.containsKey(id)) {
        final counterpart = pairMap[id]!;
        final counterpartId = counterpart.id;
        if (counterpartId != null && !usedIds.contains(counterpartId)) {
          usedIds.add(id);
          usedIds.add(counterpartId);
          final primary =
              record.accountId == savingsAccountId ? counterpart : record;
          final secondary = primary == record ? counterpart : record;
          final pairId = primary.id! < secondary.id! ? primary.id! : secondary.id!;
          result.add(
            TransactionListItem(
              record: primary,
              savingPairId: pairId,
              savingCounterpart: secondary,
            ),
          );
          continue;
        }
      }

      result.add(TransactionListItem(record: record));
      if (id != null) {
        usedIds.add(id);
      }
    }
    return result;
  }

  String _savingPairKey(TransactionRecord record) {
    final plannedId = record.plannedId?.toString() ?? '';
    final note = record.note ?? '';
    final plannedFlag = record.isPlanned ? '1' : '0';
    return '${record.date.toIso8601String()}|${record.amountMinor}|${record.categoryId}|$note|$plannedId|$plannedFlag';
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

  String _typeToString(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
      case TransactionType.saving:
        return 'saving';
    }
  }
}
