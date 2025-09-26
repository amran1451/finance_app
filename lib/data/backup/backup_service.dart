import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/migrations.dart';
import '../models/manual_backup_entry.dart';

class BackupFile {
  const BackupFile({
    required this.path,
    required this.entry,
  });

  final String path;
  final ManualBackupEntry entry;
}

class BackupService {
  BackupService({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  static const _dbFileName = 'finance_app.db';

  final AppDatabase _database;

  Future<String> _dbPath() async {
    final dbDirectory = await getDatabasesPath();
    return p.join(dbDirectory, _dbFileName);
  }

  Future<int> currentUserVersion() async {
    final db = await _database.database;
    return _readUserVersion(db);
  }

  Future<BackupFile> createBackupFile() async {
    final now = DateTime.now();
    final userVersion = await currentUserVersion();
    final fileName = 'UchetFinansov-${_formatTimestamp(now)}-v$userVersion.db';
    final sourcePath = await _dbPath();
    final temporaryDirectory = await getTemporaryDirectory();
    final destinationPath = p.join(temporaryDirectory.path, fileName);

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Файл базы данных не найден');
    }

    await _database.close();
    try {
      await sourceFile.copy(destinationPath);
    } finally {
      await _database.database;
    }

    return BackupFile(
      path: destinationPath,
      entry: ManualBackupEntry(
        createdAt: now,
        schemaVersion: userVersion,
        fileName: fileName,
      ),
    );
  }

  Future<int> readUserVersionFromFile(String path) async {
    final database = await openDatabase(path, readOnly: true);
    try {
      return _readUserVersion(database);
    } finally {
      await database.close();
    }
  }

  Future<void> importDatabase(String sourcePath) async {
    final destinationPath = await _dbPath();

    final importFile = File(sourcePath);
    if (!await importFile.exists()) {
      throw const FileSystemException('Файл резервной копии не найден');
    }

    await _database.close();
    try {
      await _deleteIfExists(destinationPath);
      await importFile.copy(destinationPath);
    } finally {
      await _database.database;
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final baseFile = File(path);
    if (await baseFile.exists()) {
      await baseFile.delete();
    }

    for (final suffix in const ['-wal', '-shm']) {
      final journalFile = File('$path$suffix');
      if (await journalFile.exists()) {
        await journalFile.delete();
      }
    }
  }

  Future<int> _readUserVersion(Database db) async {
    final result = await db.rawQuery('PRAGMA user_version');
    if (result.isEmpty) {
      return AppMigrations.latestVersion;
    }
    final row = result.first;
    final value = row.values.isEmpty ? null : row.values.first;
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? AppMigrations.latestVersion;
    }
    return AppMigrations.latestVersion;
  }

  String _formatTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year$month$day-$hour$minute';
  }
}
