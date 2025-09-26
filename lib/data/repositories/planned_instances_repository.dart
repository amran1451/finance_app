import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

abstract class PlannedInstancesRepository {
  Future<void> assignMasterToPeriod({
    required int masterId,
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
}

class SqlitePlannedInstancesRepository implements PlannedInstancesRepository {
  SqlitePlannedInstancesRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<void> assignMasterToPeriod({
    required int masterId,
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
    final db = executor ?? await _db;
    final normalizedType = type.toLowerCase();
    final sanitizedNote = note == null || note.trim().isEmpty ? null : note.trim();
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
    };
    await db.insert('transactions', values);
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
}
