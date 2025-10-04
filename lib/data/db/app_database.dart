import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import 'migrations.dart';

/// Provides access to the application database.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;
  Completer<Database>? _openingCompleter;
  final Lock _writeLock = Lock();

  /// Lazily opens the database and returns an instance of [Database].
  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null && existingDatabase.isOpen) {
      return existingDatabase;
    }

    final pending = _openingCompleter;
    if (pending != null) {
      return pending.future;
    }

    final completer = Completer<Database>();
    _openingCompleter = completer;
    try {
      final db = await _openDatabase();
      _database = db;
      completer.complete(db);
      return db;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _openingCompleter = null;
    }
  }

  /// Closes the database if it has been opened previously.
  Future<void> close() async {
    final pending = _openingCompleter;
    if (pending != null) {
      try {
        await pending.future;
      } catch (_) {
        // Ignore failures from the pending open operation. The next open
        // attempt will surface the error again.
      }
    }
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
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA busy_timeout = 10000;');
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await AppMigrations.runMigrations(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await AppMigrations.runMigrations(db, oldVersion, newVersion);
      },
    );
  }

  /// Executes [action] inside a synchronized write transaction.
  Future<T> runInWriteTransaction<T>(
    Future<T> Function(Transaction txn) action, {
    String? debugContext,
  }) async {
    final db = await database;
    return _writeLock.synchronized(() async {
      final stopwatch = Stopwatch()..start();
      assert(() {
        final label = debugContext == null ? 'write' : 'write:$debugContext';
        debugPrint('[db] BEGIN $label');
        return true;
      }());
      try {
        return await db.transaction<T>((txn) async {
          return action(txn);
        });
      } finally {
        stopwatch.stop();
        assert(() {
          final label = debugContext == null ? 'write' : 'write:$debugContext';
          debugPrint('[db] END $label in ${stopwatch.elapsedMilliseconds}ms');
          return true;
        }());
      }
    });
  }
}
