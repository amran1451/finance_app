import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/bootstrap/app_bootstrapper.dart';
import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/models/category.dart';
import 'package:finance_app/data/repositories/categories_repository.dart';

class _SeedingFailure implements Exception {
  const _SeedingFailure();
}

class _FailingCategoriesRepository implements CategoriesRepository {
  const _FailingCategoriesRepository();

  @override
  Future<void> restoreDefaults() async {
    throw const _SeedingFailure();
  }

  @override
  Future<void> bulkMove(List<int> ids, int? parentId) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(int id) {
    throw UnimplementedError();
  }

  @override
  Future<List<Category>> getAll() {
    throw UnimplementedError();
  }

  @override
  Future<List<Category>> getByType(CategoryType type) {
    throw UnimplementedError();
  }

  @override
  Future<Category?> getById(int id) {
    throw UnimplementedError();
  }

  @override
  Future<List<Category>> groupsByType(CategoryType type) {
    throw UnimplementedError();
  }

  @override
  Future<List<Category>> childrenOf(int groupId) {
    throw UnimplementedError();
  }

  @override
  Future<int> create(Category category) {
    throw UnimplementedError();
  }

  @override
  Future<void> update(Category category) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dbDir;

  setUp(() async {
    dbDir = await Directory.systemTemp.createTemp('finance_app_test');
    final dbPath = p.join(dbDir.path, 'finance_app.db');

    await AppDatabase.instance.close();
    await databaseFactory.setDatabasesPath(dbDir.path);
    await deleteDatabase(dbPath);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final dbPath = p.join(dbDir.path, 'finance_app.db');
    await deleteDatabase(dbPath);
    if (dbDir.existsSync()) {
      await dbDir.delete(recursive: true);
    }
  });

  test(
    'failed category seeding leaves seed flag unset and allows retry',
    () async {
      final bootstrapper = AppBootstrapper(
        categoriesRepository: const _FailingCategoriesRepository(),
      );

      await expectLater(
        bootstrapper.run(),
        throwsA(isA<_SeedingFailure>()),
      );

      final db = await AppDatabase.instance.database;

      final flagRows = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['_initial_seed_completed'],
      );
      expect(flagRows, isEmpty);

      final categoriesAfterFailure = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM categories'),
          ) ??
          0;
      expect(categoriesAfterFailure, 0);

      final retryBootstrapper = AppBootstrapper();
      await retryBootstrapper.run();

      final flagRowsAfterRetry = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['_initial_seed_completed'],
      );
      expect(flagRowsAfterRetry, isNotEmpty);

      final categoriesAfterRetry = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM categories'),
          ) ??
          0;
      expect(categoriesAfterRetry, greaterThan(0));
    },
  );
}
