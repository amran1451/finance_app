import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import '../models/analytics.dart';
import '../models/transaction_record.dart';

class AnalyticsRepository {
  AnalyticsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  Future<List<AnalyticsPieSlice>> loadExpenseBreakdown({
    required AnalyticsBreakdown breakdown,
    required DateTime from,
    required DateTime to,
    TransactionType type = TransactionType.expense,
    bool plannedOnly = false,
    bool unplannedOnly = false,
  }) async {
    assert(!plannedOnly || !unplannedOnly,
        'plannedOnly and unplannedOnly cannot be true at the same time');

    final db = await _db;
    final where = StringBuffer(
        't.type = ? AND t.is_planned = 0 AND t.plan_instance_id IS NULL AND t.deleted = 0');
    final args = <Object?>[_typeToString(type)];
    where.write(' AND date(t.date) >= ? AND date(t.date) <= ?');
    args..add(_formatDate(from))..add(_formatDate(to));
    if (plannedOnly) {
      where.write(' AND t.planned_id IS NOT NULL');
    } else if (unplannedOnly) {
      where.write(' AND t.planned_id IS NULL');
    }
    late final String groupBy;
    late final String selectLabel;
    late final String selectColor;
    late final String joins;

    switch (breakdown) {
      case AnalyticsBreakdown.plannedCriticality:
        joins =
            ' LEFT JOIN planned_master pm ON pm.id = t.planned_id LEFT JOIN necessity_labels nl ON nl.id = pm.necessity_id';
        groupBy = 'nl.id';
        selectLabel =
            "COALESCE(NULLIF(nl.name, ''), 'Без критичности') AS label";
        selectColor = 'nl.color AS color';
        break;
      case AnalyticsBreakdown.plannedCategory:
        joins =
            ' LEFT JOIN planned_master pm ON pm.id = t.planned_id LEFT JOIN categories cat ON cat.id = COALESCE(t.category_id, pm.category_id)';
        groupBy = 'cat.id';
        selectLabel =
            "COALESCE(NULLIF(cat.name, ''), 'Без категории') AS label";
        selectColor = 'NULL AS color';
        break;
      case AnalyticsBreakdown.unplannedReason:
        joins = ' LEFT JOIN reason_labels rl ON rl.id = t.reason_id';
        groupBy = 'rl.id';
        selectLabel =
            "COALESCE(NULLIF(rl.name, ''), 'Без причины') AS label";
        selectColor = 'rl.color AS color';
        where.write(' AND t.planned_id IS NULL');
        break;
      case AnalyticsBreakdown.unplannedCategory:
        joins = ' LEFT JOIN categories cat ON cat.id = t.category_id';
        groupBy = 'cat.id';
        selectLabel =
            "COALESCE(NULLIF(cat.name, ''), 'Без категории') AS label";
        selectColor = 'NULL AS color';
        where.write(' AND t.planned_id IS NULL');
        break;
    }

    final rows = await db.rawQuery('''
      SELECT
        $selectLabel,
        $selectColor,
        COALESCE(SUM(t.amount_minor), 0) AS total_minor,
        COUNT(t.id) AS op_count
      FROM transactions t
      $joins
      WHERE ${where.toString()}
      GROUP BY $groupBy
      HAVING total_minor <> 0
      ORDER BY total_minor DESC
    ''', args);

    return rows
        .map(
          (row) => AnalyticsPieSlice(
            label: row['label'] as String? ?? '—',
            colorHex: row['color'] as String?,
            valueMinor: _readInt(row['total_minor']),
            operationCount: _readInt(row['op_count']),
          ),
        )
        .toList();
  }

  Future<List<AnalyticsTimePoint>> loadExpenseSeries({
    required AnalyticsInterval interval,
    required DateTime from,
    required DateTime to,
    TransactionType type = TransactionType.expense,
    bool plannedOnly = false,
    bool unplannedOnly = false,
  }) async {
    assert(!plannedOnly || !unplannedOnly,
        'plannedOnly and unplannedOnly cannot be true at the same time');
    final db = await _db;
    final args = <Object?>[_typeToString(type)];
    final where = StringBuffer(
        't.type = ? AND t.is_planned = 0 AND t.plan_instance_id IS NULL AND t.deleted = 0');
    where.write(' AND date(t.date) >= ? AND date(t.date) <= ?');
    args..add(_formatDate(from))..add(_formatDate(to));
    if (plannedOnly) {
      where.write(' AND t.planned_id IS NOT NULL');
    } else if (unplannedOnly) {
      where.write(' AND t.planned_id IS NULL');
    }
    late final String bucketExpr;
    late final String orderExpr;

    switch (interval) {
      case AnalyticsInterval.days:
        bucketExpr = "date(t.date)";
        orderExpr = 'bucket';
        break;
      case AnalyticsInterval.weekdays:
        bucketExpr =
            '(((CAST(strftime(\'%w\', t.date) AS INTEGER) + 6) % 7) + 1)';
        orderExpr = 'bucket';
        break;
      case AnalyticsInterval.months:
        bucketExpr = "strftime('%Y-%m', t.date)";
        orderExpr = 'bucket';
        break;
      case AnalyticsInterval.halfPeriods:
        bucketExpr =
            "COALESCE(t.period_id, strftime('%Y-%m', t.date) || '-H' || CASE WHEN CAST(strftime('%d', t.date) AS INTEGER) <= 15 THEN '1' ELSE '2' END)";
        orderExpr = 'bucket';
        break;
    }

    final rows = await db.rawQuery('''
      SELECT
        $bucketExpr AS bucket,
        COALESCE(SUM(t.amount_minor), 0) AS total_minor
      FROM transactions t
      WHERE ${where.toString()}
      GROUP BY bucket
      HAVING total_minor <> 0
      ORDER BY $orderExpr ASC
    ''', args);

    return rows
        .map(
          (row) => AnalyticsTimePoint(
            bucket: _formatBucket(interval, row['bucket']),
            sortKey: '${row['bucket']}',
            valueMinor: _readInt(row['total_minor']),
          ),
        )
        .toList();
  }

  String _formatBucket(AnalyticsInterval interval, Object? raw) {
    switch (interval) {
      case AnalyticsInterval.days:
        return (raw as String?) ?? '';
      case AnalyticsInterval.weekdays:
        final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
        if (value == null) {
          return '—';
        }
        const labels = [
          'Пн',
          'Вт',
          'Ср',
          'Чт',
          'Пт',
          'Сб',
          'Вс',
        ];
        if (value >= 1 && value <= 7) {
          return labels[value - 1];
        }
        return value.toString();
      case AnalyticsInterval.months:
        return (raw as String?) ?? '';
      case AnalyticsInterval.halfPeriods:
        final bucket = raw as String?;
        if (bucket == null) {
          return '—';
        }
        final parts = bucket.split('-');
        if (parts.length == 3) {
          final year = parts[0];
          final month = parts[1];
          final half = parts[2] == 'H1' ? '1' : '2';
          return '$year-$month H$half';
        }
        return bucket;
    }
  }

  int _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw) ?? 0;
    }
    return 0;
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

  String _formatDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year.toString().padLeft(4, '0')}-$month-$day';
  }
}
