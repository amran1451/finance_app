import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Тик, увеличивается после любой записи в БД
final dbTickProvider = StateProvider<int>((_) => 0);

/// Удобный хелпер
void bumpDbTick(WidgetRef ref) {
  final n = ref.read(dbTickProvider.notifier);
  n.state = n.state + 1;
}
