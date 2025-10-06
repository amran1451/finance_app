import 'package:sqflite/sqflite.dart';

/// Defines all database migrations for the application.
class AppMigrations {
  AppMigrations._();

  /// Latest schema version supported by the application.
  static const int latestVersion = 16;

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
          "updated_at TEXT NOT NULL DEFAULT (datetime('now')), "
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
          'account_id INTEGER NOT NULL, '
          'daily_limit_minor INTEGER NOT NULL DEFAULT 0, '
          'daily_limit_from_today INTEGER NOT NULL DEFAULT 0'
          ')',
      'CREATE INDEX IF NOT EXISTS idx_payouts_date ON payouts(date)',
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
    5: [
      'ALTER TABLE transactions ADD COLUMN payout_id INTEGER NULL',
      'CREATE INDEX IF NOT EXISTS idx_transactions_payout_id ON transactions(payout_id)',
    ],
    6: [
      'CREATE TABLE IF NOT EXISTS planned_master ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          "type TEXT CHECK(type IN ('expense','income','saving')) NOT NULL, "
          'title TEXT NOT NULL, '
          'default_amount_minor INTEGER NULL, '
          'category_id INTEGER NULL, '
          'note TEXT NULL, '
          'archived INTEGER NOT NULL DEFAULT 0, '
          "created_at TEXT NOT NULL DEFAULT (datetime('now')), "
          "updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
          ')',
      'ALTER TABLE transactions ADD COLUMN planned_id INTEGER NULL',
      'CREATE INDEX IF NOT EXISTS idx_transactions_planned_id ON transactions(planned_id)',
    ],
    8: [
      'CREATE TABLE IF NOT EXISTS periods ('
          'id INTEGER PRIMARY KEY, '
          'year INTEGER NOT NULL, '
          'month INTEGER NOT NULL, '
          "half TEXT CHECK(half IN ('H1','H2')) NOT NULL, "
          'start TEXT NOT NULL, '
          'end_exclusive TEXT NOT NULL, '
          'payout_id INTEGER NULL, '
          'daily_limit_minor INTEGER NULL, '
          'spent_minor INTEGER NULL, '
          'planned_included_minor INTEGER NULL, '
          'carryover_minor INTEGER NOT NULL DEFAULT 0, '
          'closed INTEGER NOT NULL DEFAULT 0, '
          'closed_at TEXT NULL, '
          'start_anchor_payout_id INTEGER NULL, '
          'UNIQUE(year, month, half)'
          ')',
    ],
    9: [
      'ALTER TABLE planned_master ADD COLUMN necessity_id INTEGER NULL',
      'CREATE INDEX IF NOT EXISTS idx_planned_master_necessity_id ON planned_master(necessity_id)',
    ],
    10: [],
    11: [
      'CREATE INDEX IF NOT EXISTS idx_payouts_date ON payouts(date)',
    ],
    12: [],
    13: [],
    14: [
      'CREATE INDEX IF NOT EXISTS idx_transactions_is_planned_date '
          'ON transactions(is_planned, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_type_planned_included_date '
          'ON transactions(type, is_planned, included_in_period, date)',
    ],
    15: [
      'CREATE INDEX IF NOT EXISTS idx_transactions_included_date '
          'ON transactions(included_in_period, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_category_date '
          'ON transactions(category_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_planned_date '
          'ON transactions(planned_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_payout_date '
          'ON transactions(payout_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_plan_source '
          'ON transactions(plan_instance_id, source)',
      'CREATE INDEX IF NOT EXISTS idx_payouts_account_date ON payouts(account_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_periods_closed_start ON periods(closed, start)',
    ],
    16: [
      'ALTER TABLE payouts ADD COLUMN assigned_period_id TEXT NULL',
      'ALTER TABLE transactions ADD COLUMN payout_period_id TEXT NULL',
      'CREATE INDEX IF NOT EXISTS idx_payouts_assigned_period ON payouts(assigned_period_id)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_payout_period ON transactions(payout_period_id)',
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
        case 10:
          await _ensureColumnExists(
            db,
            tableName: 'transactions',
            columnName: 'updated_at',
            alterStatement:
                "ALTER TABLE transactions ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'))",
          );
          break;
        case 11:
          await _ensureColumnExists(
            db,
            tableName: 'payouts',
            columnName: 'daily_limit_minor',
            alterStatement:
                'ALTER TABLE payouts ADD COLUMN daily_limit_minor INTEGER NOT NULL DEFAULT 0',
          );
          await _ensureColumnExists(
            db,
            tableName: 'payouts',
            columnName: 'daily_limit_from_today',
            alterStatement:
                'ALTER TABLE payouts ADD COLUMN daily_limit_from_today INTEGER NOT NULL DEFAULT 0',
          );
          break;
        case 12:
          await _ensureColumnExists(
            db,
            tableName: 'transactions',
            columnName: 'plan_instance_id',
            alterStatement:
                'ALTER TABLE transactions ADD COLUMN plan_instance_id INTEGER NULL',
          );
          await _ensureColumnExists(
            db,
            tableName: 'transactions',
            columnName: 'source',
            alterStatement:
                'ALTER TABLE transactions ADD COLUMN source TEXT NULL',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_plan_instance_id ON transactions(plan_instance_id)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_plan_instance_account '
            'ON transactions(plan_instance_id, account_id) '
            'WHERE plan_instance_id IS NOT NULL',
          );
          break;
        case 13:
          await _ensureColumnExists(
            db,
            tableName: 'periods',
            columnName: 'start_anchor_payout_id',
            alterStatement:
                'ALTER TABLE periods ADD COLUMN start_anchor_payout_id INTEGER NULL',
          );
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

  static Future<void> _ensureColumnExists(
    Database db, {
    required String tableName,
    required String columnName,
    required String alterStatement,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final normalizedColumnName = columnName.toLowerCase();
    final hasColumn = columns.any(
      (column) =>
          (column['name'] as String?)?.toLowerCase() == normalizedColumnName,
    );

    if (!hasColumn) {
      await db.execute(alterStatement);
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
