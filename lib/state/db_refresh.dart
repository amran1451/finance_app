import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Тик, увеличивается после любой записи в БД
final dbTickProvider = StateProvider<int>((_) => 0);

/// Тик, увеличивается после синхронизации или импорта БД
final syncTickProvider = StateProvider<int>((_) => 0);

final _dbTickControllerProvider = Provider<StreamController<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

/// Поток, рассылающий уведомления об изменениях в БД.
final dbTickStreamProvider = Provider<Stream<void>>((ref) {
  return ref.watch(_dbTickControllerProvider).stream;
});

/// Удобный хелпер
void bumpDbTick(dynamic ref) {
  final n = ref.read(dbTickProvider.notifier);
  n.state = n.state + 1;
  ref.read(_dbTickControllerProvider).add(null);
}

/// Удобный хелпер для обновления синхронизационного тика.
void bumpSyncTick(dynamic ref) {
  final notifier = ref.read(syncTickProvider.notifier);
  notifier.state = notifier.state + 1;
}
