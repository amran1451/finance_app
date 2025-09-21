import 'package:sqflite/sqflite.dart';

/// Defines all database migrations for the application.
class AppMigrations {
  AppMigrations._();

  /// Latest schema version supported by the application.
  static const int latestVersion = 1;

  static final Map<int, List<String>> _migrationScripts = {
    1: [
      'CREATE TABLE accounts ('
          'id INTEGER PRIMARY KEY, '
          'name TEXT, '
          'currency TEXT, '
          'start_balance_minor INTEGER NOT NULL DEFAULT 0, '
          'is_archived INTEGER NOT NULL DEFAULT 0'
          ')',
      'CREATE TABLE categories ('
          'id INTEGER PRIMARY KEY, '
          "type TEXT CHECK(type IN ('income','expense','saving')), "
          'name TEXT, '
          'is_group INTEGER NOT NULL DEFAULT 0, '
          'parent_id INTEGER NULL, '
          'archived INTEGER NOT NULL DEFAULT 0'
          ')',
      'CREATE TABLE transactions ('
          'id INTEGER PRIMARY KEY, '
          'account_id INTEGER NOT NULL, '
          'category_id INTEGER NOT NULL, '
          "type TEXT CHECK(type IN ('income','expense','saving')), "
          'amount_minor INTEGER NOT NULL, '
          'date TEXT NOT NULL, '
          'time TEXT NULL, '
          'note TEXT NULL, '
          'is_planned INTEGER NOT NULL DEFAULT 0, '
          'included_in_period INTEGER NOT NULL DEFAULT 1, '
          'tags TEXT NULL'
          ')',
      'CREATE INDEX idx_transactions_date ON transactions(date)',
      'CREATE INDEX idx_transactions_category_id ON transactions(category_id)',
      'CREATE INDEX idx_transactions_account_id ON transactions(account_id)',
      'CREATE INDEX idx_transactions_type ON transactions(type)',
      'CREATE TABLE payouts ('
          'id INTEGER PRIMARY KEY, '
          "type TEXT CHECK(type IN ('advance','salary')), "
          'date TEXT NOT NULL, '
          'amount_minor INTEGER NOT NULL, '
          'account_id INTEGER NOT NULL'
          ')',
      'CREATE TABLE settings ('
          'key TEXT PRIMARY KEY, '
          'value TEXT NOT NULL'
          ')',
    ],
  };

  /// Applies migrations from [oldVersion] (exclusive) up to [newVersion] (inclusive).
  static Future<void> runMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      final statements = _migrationScripts[version];
      if (statements == null) {
        continue;
      }
      for (final statement in statements) {
        await db.execute(statement);
      }
    }
  }
}
