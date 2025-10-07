import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'seed_criticalities.dart';

/// Seeds default reference data for the application.
class SeedData {
  SeedData._();

  static Future<void> run(Database db) async {
    assert(() {
      debugPrint('[seed] ensuring defaults');
      return true;
    }());

    await seedCategories(db);
    await SeedCriticalities.run(db);
    await seedReasons(db);
  }

  static Future<void> seedCategories(DatabaseExecutor executor) async {
    assert(() {
      debugPrint('[seed] categories');
      return true;
    }());

    final hasSortOrder = await _hasColumn(executor, 'categories', 'sort_order');
    final folders = <String, int>{};

    Future<int?> findCategoryId({
      required String name,
      required bool isGroup,
      int? parentId,
    }) async {
      final whereBuffer = StringBuffer('type = ? AND name = ? AND is_group = ?');
      final args = <Object?>['expense', name, isGroup ? 1 : 0];
      if (parentId == null) {
        whereBuffer.write(' AND parent_id IS NULL');
      } else {
        whereBuffer.write(' AND parent_id = ?');
        args.add(parentId);
      }
      final rows = await executor.query(
        'categories',
        columns: ['id'],
        where: whereBuffer.toString(),
        whereArgs: args,
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first['id'] as int?;
    }

    Future<int> ensureFolder(String name, int sortOrder) async {
      final existingId = await findCategoryId(name: name, isGroup: true);
      if (existingId != null) {
        return existingId;
      }

      final values = <String, Object?>{
        'type': 'expense',
        'name': name,
        'is_group': 1,
        'parent_id': null,
        'archived': 0,
      };
      if (hasSortOrder) {
        values['sort_order'] = sortOrder;
      }

      final insertedId = await executor.insert(
        'categories',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (insertedId != 0) {
        return insertedId;
      }
      final fallbackId = await findCategoryId(name: name, isGroup: true);
      if (fallbackId != null) {
        return fallbackId;
      }
      throw StateError('Failed to ensure folder "$name"');
    }

    Future<void> ensureChild(String folderName, String name, int sortOrder) async {
      final parentId = folders[folderName];
      if (parentId == null) {
        throw StateError('Parent folder "$folderName" has not been created');
      }
      final existingId = await findCategoryId(
        name: name,
        isGroup: false,
        parentId: parentId,
      );
      if (existingId != null) {
        return;
      }

      final values = <String, Object?>{
        'type': 'expense',
        'name': name,
        'is_group': 0,
        'parent_id': parentId,
        'archived': 0,
      };
      if (hasSortOrder) {
        values['sort_order'] = sortOrder;
      }

      await executor.insert(
        'categories',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    const foldersDefinition = <_FolderDefinition>[
      _FolderDefinition('Дом и быт', [
        'Бытовое',
        'ЖКХ и т.д.',
      ]),
      _FolderDefinition('Цифровое', [
        'Игры',
        'Подписки',
        'Связь и интернет',
      ]),
      _FolderDefinition('Одежда', [
        'Одежда и обувь',
      ]),
      _FolderDefinition('Базовые расходы', [
        'Питание',
        'Транспорт',
        'Здоровье',
        'Образование',
      ]),
      _FolderDefinition('Досуг', [
        'Развлечения',
        'Хобби',
        'Путешествия',
      ]),
      _FolderDefinition('Подарки', [
        'Подарки',
      ]),
      _FolderDefinition('Финансы', [
        'Долг',
        'Кредиты',
      ]),
    ];

    for (var i = 0; i < foldersDefinition.length; i++) {
      final folder = foldersDefinition[i];
      final sortBase = (i + 1) * 100;
      final folderId = await ensureFolder(folder.name, sortBase);
      folders[folder.name] = folderId;
      for (var j = 0; j < folder.children.length; j++) {
        await ensureChild(folder.name, folder.children[j], sortBase + j + 1);
      }
    }
  }

  static Future<void> seedReasons(DatabaseExecutor executor) async {
    assert(() {
      debugPrint('[seed] reasons');
      return true;
    }());

    final hasSortOrder = await _hasColumn(executor, 'reason_labels', 'sort_order');

    const reasons = <String>[
      'Необходимо',
      'Эмоции',
      'Вынужденно',
      'Социальное',
      'Импульс',
      'Статус',
      'Избегание',
    ];

    for (var i = 0; i < reasons.length; i++) {
      final name = reasons[i];
      final existingId = await _getSimpleId(
        executor,
        table: 'reason_labels',
        name: name,
      );
      if (existingId != null) {
        continue;
      }

      final values = <String, Object?>{
        'name': name,
        'color': null,
        'archived': 0,
      };
      if (hasSortOrder) {
        values['sort_order'] = (i + 1) * 10;
      }

      await executor.insert(
        'reason_labels',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<int?> _getSimpleId(
    DatabaseExecutor executor, {
    required String table,
    required String name,
  }) async {
    final rows = await executor.query(
      table,
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id'] as int?;
  }

  static Future<bool> _hasColumn(
    DatabaseExecutor executor,
    String table,
    String column,
  ) async {
    final normalized = column.toLowerCase();
    final result = await executor.rawQuery('PRAGMA table_info($table)');
    return result.any((row) => (row['name'] as String?)?.toLowerCase() == normalized);
  }
}

class _FolderDefinition {
  const _FolderDefinition(this.name, this.children);

  final String name;
  final List<String> children;
}
