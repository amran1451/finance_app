import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Provides access to the application database.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  /// Lazily opens the database and returns an instance of [Database].
  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null && existingDatabase.isOpen) {
      return existingDatabase;
    }

    _database = await _openDatabase();
    return _database!;
  }

  /// Closes the database if it has been opened previously.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'finance_app.db');

    return openDatabase(
      path,
      version: AppMigrations.latestVersion,
      onConfigure: (db) async {
        // Enable WAL to allow concurrent readers during write transactions and
        // avoid "database has been locked" warnings that appear when the UI
        // performs multiple queries in parallel.
        await db.execute('PRAGMA journal_mode = WAL');
        // Provide a small grace period for queued queries to wait for the lock
        // instead of failing immediately.
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        await AppMigrations.runMigrations(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await AppMigrations.runMigrations(db, oldVersion, newVersion);
      },
    );
  }
}
