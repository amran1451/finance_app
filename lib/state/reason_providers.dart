import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/reason_repository.dart';
import 'app_providers.dart';
import 'db_refresh.dart';

final reasonLabelsProvider = FutureProvider<List<ReasonLabel>>((ref) {
  ref.watch(dbTickProvider);
  final repo = ref.watch(reasonRepoProvider);
  return repo.list();
});

final reasonMapProvider = FutureProvider<Map<int, ReasonLabel>>((ref) async {
  final list = await ref.watch(reasonLabelsProvider.future);
  return {for (final label in list) label.id: label};
});
