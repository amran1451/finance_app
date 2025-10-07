import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class SeedCriticalities {
  const SeedCriticalities._();

  static const _table = 'necessity_labels';

  static const _defaults = <_CriticalityDefinition>[
    _CriticalityDefinition('Точно', '#546E7A'),
    _CriticalityDefinition('Надо', '#607D8B'),
    _CriticalityDefinition('Можно отложить', '#78909C'),
    _CriticalityDefinition('Заморожено', '#90A4AE'),
    _CriticalityDefinition('Уже не надо', '#B0BEC5'),
    _CriticalityDefinition('Хочу', '#CFD8DC'),
  ];

  static Future<void> run(DatabaseExecutor executor) async {
    assert(() {
      debugPrint('[seed] criticalities');
      return true;
    }());

    final hasColor = await _hasColumn(executor, _table, 'color');
    final hasSortOrder = await _hasColumn(executor, _table, 'sort_order');

    for (var i = 0; i < _defaults.length; i++) {
      final definition = _defaults[i];
      final existing = await executor.query(
        _table,
        columns: const ['id'],
        where: 'name = ?',
        whereArgs: [definition.name],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        continue;
      }

      final values = <String, Object?>{
        'name': definition.name,
        'archived': 0,
      };
      if (hasColor && definition.color != null) {
        values['color'] = definition.color;
      }
      if (hasSortOrder) {
        values['sort_order'] = (i + 1) * 10;
      }

      await executor.insert(
        _table,
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<bool> _hasColumn(
    DatabaseExecutor executor,
    String table,
    String column,
  ) async {
    final normalized = column.toLowerCase();
    final result = await executor.rawQuery('PRAGMA table_info($table)');
    return result.any(
      (row) => (row['name'] as String?)?.toLowerCase() == normalized,
    );
  }
}

class _CriticalityDefinition {
  const _CriticalityDefinition(this.name, this.color);

  final String name;
  final String? color;
}
