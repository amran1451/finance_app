import 'package:sqflite/sqflite.dart';

/// Defines all database migrations for the application.
class AppMigrations {
  AppMigrations._();

  /// Latest schema version supported by the application.
  static const int latestVersion = 4;

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
    2: [
      'ALTER TABLE transactions ADD COLUMN criticality INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE transactions ADD COLUMN necessity_label TEXT NULL',
    ],
    3: [
      'CREATE TABLE IF NOT EXISTS necessity_labels('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, '
          'color TEXT NULL, '
          'sort_order INTEGER NOT NULL, '
          'archived INTEGER NOT NULL DEFAULT 0'
          ')',
      'ALTER TABLE transactions ADD COLUMN necessity_id INTEGER NULL',
      'CREATE INDEX IF NOT EXISTS idx_transactions_necessity_id ON transactions(necessity_id)',
    ],
    4: [
      'CREATE TABLE IF NOT EXISTS reason_labels('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, '
          'color TEXT NULL, '
          'sort_order INTEGER NOT NULL, '
          'archived INTEGER NOT NULL DEFAULT 0'
          ')',
      'ALTER TABLE transactions ADD COLUMN reason_id INTEGER NULL',
      'ALTER TABLE transactions ADD COLUMN reason_label TEXT NULL',
      'CREATE INDEX IF NOT EXISTS idx_transactions_reason_id ON transactions(reason_id)',
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
      if (statements != null) {
        await _executeStatements(db, statements);
      }

      switch (version) {
        case 3:
          await _seedNecessityLabels(db);
          break;
        case 4:
          await _seedReasonLabels(db);
          break;
        default:
          break;
      }
    }
  }

  static Future<void> _executeStatements(Database db, List<String> statements) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  static Future<void> _seedNecessityLabels(Database db) async {
    final existingCountResult =
        await db.rawQuery('SELECT COUNT(*) AS count FROM necessity_labels');
    final existingCount = existingCountResult.isNotEmpty
        ? _readInt(existingCountResult.first['count'])
        : 0;
    if (existingCount > 0) {
      return;
    }

    final existingLabelsResult = await db.rawQuery(
      'SELECT DISTINCT necessity_label '
      'FROM transactions '
      'WHERE necessity_label IS NOT NULL '
      "AND TRIM(necessity_label) <> ''",
    );

    final seen = <String>{};
    final labels = <String>[];

    void addUnique(Iterable<String> source) {
      for (final raw in source) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final key = trimmed.toLowerCase();
        if (seen.add(key)) {
          labels.add(trimmed);
        }
      }
    }

    addUnique(existingLabelsResult
        .map((row) => row['necessity_label'] as String?)
        .whereType<String>());

    if (labels.isEmpty) {
      addUnique(_legacyDefaultNecessityLabels);
    }
    if (labels.isEmpty) {
      addUnique(_fallbackNecessityLabels);
    }

    for (var i = 0; i < labels.length; i++) {
      await db.insert('necessity_labels', {
        'name': labels[i],
        'color': null,
        'sort_order': i,
        'archived': 0,
      });
    }
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static const List<String> _legacyDefaultNecessityLabels = [
    'Необходимо',
    'Вынуждено',
    'Эмоции',
  ];

  static const List<String> _fallbackNecessityLabels = [
    'точно',
    'надо',
    'можно отложить',
  ];

  static Future<void> _seedReasonLabels(Database db) async {
    final existingCountResult =
        await db.rawQuery('SELECT COUNT(*) AS count FROM reason_labels');
    final existingCount = existingCountResult.isNotEmpty
        ? _readInt(existingCountResult.first['count'])
        : 0;
    if (existingCount > 0) {
      return;
    }

    const defaultReasons = [
      'Необходимо',
      'Эмоции',
      'Вынуждено',
      'Социальное',
      'Импульс',
      'Статус',
      'Избегание',
    ];

    for (var i = 0; i < defaultReasons.length; i++) {
      await db.insert('reason_labels', {
        'name': defaultReasons[i],
        'color': null,
        'sort_order': i,
        'archived': 0,
      });
    }
  }
}
