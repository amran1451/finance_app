import 'package:sqflite/sqflite.dart';

import '../../utils/period_utils.dart';
import '../db/app_database.dart';

abstract class PlannedInstancesRepository {
  Future<void> assignMasterToPeriod({
    required int masterId,
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required String type,
    bool includedInPeriod = true,
    int? necessityId,
    String? note,
    String? necessityLabel,
    DatabaseExecutor? executor,
  });

  Future<int> upsertInstance({
    required int masterId,
    required DateTime start,
    required DateTime endExclusive,
    required bool includedInPeriod,
    required PeriodRef period,
    int? necessityId,
    int? categoryId,
    int? amountMinor,
    String? note,
    DatabaseExecutor? executor,
  });
}

class SqlitePlannedInstancesRepository implements PlannedInstancesRepository {
  SqlitePlannedInstancesRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  Future<T> _runWrite<T>(
    Future<T> Function(DatabaseExecutor executor) action, {
    DatabaseExecutor? executor,
    String? debugContext,
  }) {
    if (executor != null) {
      return action(executor);
    }
    return _database.runInWriteTransaction<T>(
      (txn) => action(txn),
      debugContext: debugContext,
    );
  }

  @override
  Future<void> assignMasterToPeriod({
    required int masterId,
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required String type,
    bool includedInPeriod = true,
    int? necessityId,
    String? note,
    String? necessityLabel,
    DatabaseExecutor? executor,
  }) async {
    await _runWrite<void>(
      (db) async {
        final normalizedType = type.toLowerCase();
        final sanitizedNote =
            note == null || note.trim().isEmpty ? null : note.trim();
        final instanceDate = _resolveInstanceDate(start, endExclusive);
        final values = <String, Object?>{
          'planned_id': masterId,
          'type': normalizedType,
          'account_id': 0,
          'category_id': categoryId,
          'amount_minor': amountMinor,
          'date': _formatDate(instanceDate),
          'time': null,
          'note': sanitizedNote,
          'is_planned': 1,
          'included_in_period': includedInPeriod ? 1 : 0,
          'tags': null,
          'criticality': 0,
          'necessity_id': necessityId,
          'necessity_label': necessityLabel,
          'reason_id': null,
          'reason_label': null,
          'payout_id': null,
          'period_id': period.id,
        };
        await db.insert('transactions', values);
        await db.insert(
          'plan_period_links',
          {
            'plan_id': masterId,
            'period_id': period.id,
            'included': includedInPeriod ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
      executor: executor,
      debugContext: 'plannedInstances.assignMaster',
    );
  }

  @override
  Future<int> upsertInstance({
    required int masterId,
    required DateTime start,
    required DateTime endExclusive,
    required bool includedInPeriod,
    required PeriodRef period,
    int? necessityId,
    int? categoryId,
    int? amountMinor,
    String? note,
    DatabaseExecutor? executor,
  }) async {
    return _runWrite<int>(
      (db) async {
        final startDate = _formatDate(start);
        final endDate = _formatDate(endExclusive);
        final existing = await db.query(
          'transactions',
          where:
              'COALESCE(is_planned, 0) = 1 AND planned_id = ? AND date >= ? AND date < ?',
          whereArgs: [masterId, startDate, endDate],
          orderBy: 'date ASC, id ASC',
          limit: 1,
        );
        final sanitizedNote =
            note == null || note.trim().isEmpty ? null : note.trim();
        final necessityLabel = await _loadNecessityLabel(db, necessityId);

        if (existing.isNotEmpty) {
          final id = existing.first['id'] as int?;
          if (id == null) {
            return 0;
          }
          final updateValues = <String, Object?>{
            'included_in_period': includedInPeriod ? 1 : 0,
            'necessity_id': necessityId,
            'necessity_label': necessityLabel,
            'note': sanitizedNote,
            'period_id': period.id,
          };
          if (categoryId != null) {
            updateValues['category_id'] = categoryId;
          }
          if (amountMinor != null) {
            updateValues['amount_minor'] = amountMinor;
          }
          final updated = await db.update(
            'transactions',
            updateValues,
            where: 'id = ?',
            whereArgs: [id],
          );
          await db.insert(
            'plan_period_links',
            {
              'plan_id': masterId,
              'period_id': period.id,
              'included': includedInPeriod ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return updated;
        }

        final masterRows = await db.query(
          'planned_master',
          where: 'id = ?',
          whereArgs: [masterId],
          limit: 1,
        );
        if (masterRows.isEmpty) {
          throw StateError('Не найден шаблон с идентификатором $masterId');
        }
        final master = masterRows.first;
        final masterType = (master['type'] as String? ?? 'expense').toLowerCase();
        final resolvedCategoryId =
            categoryId ?? (master['category_id'] as int? ?? 0);
        final resolvedAmountMinor =
            amountMinor ?? (master['default_amount_minor'] as int? ?? 0);
        final instanceDate = _resolveInstanceDate(start, endExclusive);

        final insertValues = <String, Object?>{
          'planned_id': masterId,
          'type': masterType,
          'account_id': 0,
          'category_id': resolvedCategoryId,
          'amount_minor': resolvedAmountMinor,
          'date': _formatDate(instanceDate),
          'time': null,
          'note': sanitizedNote,
          'is_planned': 1,
          'included_in_period': includedInPeriod ? 1 : 0,
          'tags': null,
          'criticality': 0,
          'necessity_id': necessityId,
          'necessity_label': necessityLabel,
          'reason_id': null,
          'reason_label': null,
          'payout_id': null,
          'period_id': period.id,
        };
        await db.insert('transactions', insertValues);
        await db.insert(
          'plan_period_links',
          {
            'plan_id': masterId,
            'period_id': period.id,
            'included': includedInPeriod ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return 1;
      },
      executor: executor,
      debugContext: 'plannedInstances.upsert',
    );
  }

  DateTime _resolveInstanceDate(DateTime start, DateTime endExclusive) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEndExclusive = DateTime(
      endExclusive.year,
      endExclusive.month,
      endExclusive.day,
    );
    if (normalizedEndExclusive.isAfter(normalizedStart)) {
      return normalizedStart;
    }
    return normalizedStart;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  Future<String?> _loadNecessityLabel(DatabaseExecutor executor, int? id) async {
    if (id == null) {
      return null;
    }
    final rows = await executor.query(
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
}
