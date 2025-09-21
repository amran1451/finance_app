import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../repositories/categories_repository.dart';

/// Seeds initial data required for the application on first launch.
class AppBootstrapper {
  AppBootstrapper({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  static const String _seedFlagKey = '_initial_seed_completed';

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  /// Ensures that the essential data is present in the database.
  Future<void> run() async {
    final db = await _db;
    final alreadySeeded = await _isSeedCompleted(db);
    if (alreadySeeded) {
      return;
    }

    await db.transaction((txn) async {
      await _seedAccounts(txn);
      await _seedSettings(txn);
      await _markSeedCompleted(txn);
    });

    // Seed categories separately to reuse repository helpers.
    final categoriesRepository =
        SqliteCategoriesRepository(database: _database);
    await categoriesRepository.restoreDefaults();
  }

  Future<bool> _isSeedCompleted(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_seedFlagKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _markSeedCompleted(DatabaseExecutor executor) async {
    await executor.insert(
      'settings',
      {
        'key': _seedFlagKey,
        'value': '1',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _seedAccounts(DatabaseExecutor executor) async {
    final count = Sqflite.firstIntValue(
          await executor.rawQuery('SELECT COUNT(*) FROM accounts'),
        ) ??
        0;
    if (count > 0) {
      return;
    }

    final accounts = const [
      ('Нал', 'RUB'),
      ('Карта', 'RUB'),
      ('Сберегательный', 'RUB'),
    ];

    for (final (name, currency) in accounts) {
      await executor.insert(
        'accounts',
        {
          'name': name,
          'currency': currency,
          'start_balance_minor': 0,
          'is_archived': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _seedSettings(DatabaseExecutor executor) async {
    final defaults = <String, String>{
      'anchor_day_1': '1',
      'anchor_day_2': '15',
      'daily_limit_minor': '0',
      'saving_pair_enabled': '1',
    };

    for (final entry in defaults.entries) {
      await executor.insert(
        'settings',
        {
          'key': entry.key,
          'value': entry.value,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
