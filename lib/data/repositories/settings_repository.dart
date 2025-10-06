import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/manual_backup_entry.dart';

abstract class SettingsRepository {
  Future<int> getAnchorDay1();

  Future<void> setAnchorDay1(int value);

  Future<int> getAnchorDay2();

  Future<void> setAnchorDay2(int value);

  Future<int?> getDailyLimitMinor();

  Future<void> setDailyLimitMinor(int? value);

  Future<bool> getDailyLimitFromToday();

  Future<void> setDailyLimitFromToday(bool value);

  Future<bool> getSavingPairEnabled();

  Future<void> setSavingPairEnabled(bool value);

  Future<List<ManualBackupEntry>> getManualBackupHistory();

  Future<void> addManualBackupEntry(ManualBackupEntry entry);

  Future<DateTime?> getPeriodCloseBannerHiddenUntil();

  Future<void> setPeriodCloseBannerHiddenUntil(DateTime? value);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  static const String _anchorDay1Key = 'anchor_day_1';
  static const String _anchorDay2Key = 'anchor_day_2';
  static const String _dailyLimitKey = 'daily_limit_minor';
  static const String _dailyLimitFromTodayKey = 'daily_limit_from_today';
  static const String _savingPairKey = 'saving_pair_enabled';
  static const String _manualBackupHistoryKey = 'manual_backup_history';
  static const String _periodCloseBannerHiddenUntilKey =
      'period_close_banner_hidden_until';

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  @override
  Future<int> getAnchorDay1() => _getInt(_anchorDay1Key, defaultValue: 1);

  @override
  Future<int> getAnchorDay2() => _getInt(_anchorDay2Key, defaultValue: 15);

  @override
  Future<int?> getDailyLimitMinor() async {
    final value = await _getNullableInt(_dailyLimitKey);
    if (value != null) {
      return value;
    }
    await _setInt(_dailyLimitKey, 0);
    return 0;
  }

  @override
  Future<bool> getSavingPairEnabled() =>
      _getBool(_savingPairKey, defaultValue: true);

  @override
  Future<void> setAnchorDay1(int value) => _setInt(_anchorDay1Key, value);

  @override
  Future<void> setAnchorDay2(int value) => _setInt(_anchorDay2Key, value);

  @override
  Future<void> setDailyLimitMinor(int? value) => _setNullableInt(_dailyLimitKey, value);

  @override
  Future<bool> getDailyLimitFromToday() =>
      _getBool(_dailyLimitFromTodayKey, defaultValue: false);

  @override
  Future<void> setDailyLimitFromToday(bool value) =>
      _setBool(_dailyLimitFromTodayKey, value);

  @override
  Future<void> setSavingPairEnabled(bool value) => _setBool(_savingPairKey, value);

  @override
  Future<List<ManualBackupEntry>> getManualBackupHistory() async {
    final raw = await _getString(_manualBackupHistoryKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return ManualBackupEntry.decodeList(raw);
  }

  @override
  Future<void> addManualBackupEntry(ManualBackupEntry entry) async {
    final history = await getManualBackupHistory();
    final updated = <ManualBackupEntry>[entry, ...history];
    // keep latest 10 entries
    final limited = updated.take(10).toList();
    await _setString(
      _manualBackupHistoryKey,
      ManualBackupEntry.encodeList(limited),
    );
  }

  @override
  Future<DateTime?> getPeriodCloseBannerHiddenUntil() async {
    final raw = await _getString(_periodCloseBannerHiddenUntilKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> setPeriodCloseBannerHiddenUntil(DateTime? value) async {
    if (value == null) {
      await _deleteKey(_periodCloseBannerHiddenUntilKey);
      return;
    }
    await _setString(
      _periodCloseBannerHiddenUntilKey,
      value.toIso8601String(),
    );
  }

  Future<int> _getInt(String key, {required int defaultValue}) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _setInt(key, defaultValue);
      return defaultValue;
    }
    return int.tryParse(rows.first['value'] as String? ?? '') ?? defaultValue;
  }

  Future<int?> _getNullableInt(String key) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return int.tryParse(rows.first['value'] as String? ?? '');
  }

  Future<bool> _getBool(String key, {required bool defaultValue}) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _setBool(key, defaultValue);
      return defaultValue;
    }
    final raw = rows.first['value'] as String?;
    if (raw == null) {
      return defaultValue;
    }
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  Future<void> _setInt(String key, int value) async {
    final db = await _db;
    await db.insert(
      'settings',
      {'key': key, 'value': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getString(String key) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> _setString(String key, String value) async {
    final db = await _db;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _setNullableInt(String key, int? value) async {
    final db = await _db;
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _setInt(key, value);
    }
  }

  Future<void> _setBool(String key, bool value) async {
    final db = await _db;
    await db.insert(
      'settings',
      {'key': key, 'value': value ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _deleteKey(String key) async {
    final db = await _db;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
