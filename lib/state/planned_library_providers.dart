import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/necessity_repository.dart' as necessity_repo;
import '../data/repositories/planned_master_repository.dart';
import 'db_refresh.dart';
import 'planned_master_providers.dart';

class PlannedLibraryFilters {
  PlannedLibraryFilters({
    this.type,
    Set<int>? necessityIds,
    this.assignedInPeriod,
    this.archived = false,
    this.search = '',
    this.sort = 'title',
    this.desc = false,
  }) : necessityIds = Set<int>.unmodifiable(necessityIds ?? const <int>{});

  final String? type;
  final Set<int> necessityIds;
  final bool? assignedInPeriod;
  final bool archived;
  final String search;
  final String sort;
  final bool desc;

  static const _unset = Object();

  PlannedLibraryFilters copyWith({
    Object? type = _unset,
    Set<int>? necessityIds,
    Object? assignedInPeriod = _unset,
    bool? archived,
    String? search,
    String? sort,
    bool? desc,
  }) {
    return PlannedLibraryFilters(
      type: type == _unset ? this.type : type as String?,
      necessityIds: necessityIds == null
          ? this.necessityIds
          : Set<int>.unmodifiable(necessityIds),
      assignedInPeriod: assignedInPeriod == _unset
          ? this.assignedInPeriod
          : assignedInPeriod as bool?,
      archived: archived ?? this.archived,
      search: search ?? this.search,
      sort: sort ?? this.sort,
      desc: desc ?? this.desc,
    );
  }
}

final plannedLibraryFiltersProvider =
    StateProvider<PlannedLibraryFilters>((ref) {
  return PlannedLibraryFilters();
});

final plannedLibraryListProvider = FutureProvider.family<
    List<PlannedMasterView>, (DateTime start, DateTime endExclusive)>(
  (ref, bounds) async {
    ref.watch(dbTickProvider);
    final filters = ref.watch(plannedLibraryFiltersProvider);
    final repository = ref.watch(plannedMasterRepoProvider);
    final necessityIds = filters.necessityIds.isEmpty
        ? null
        : (filters.necessityIds.toList()..sort());
    final search = filters.search.trim().isEmpty ? null : filters.search.trim();
    return repository.query(
      type: filters.type,
      necessityIds: necessityIds,
      assignedInPeriod: filters.assignedInPeriod,
      archived: filters.archived,
      search: search,
      sort: filters.sort,
      desc: filters.desc,
      periodStart: bounds.$1,
      periodEndEx: bounds.$2,
    );
  },
);

final necessityLabelsProvider = FutureProvider<
    Map<int, necessity_repo.NecessityLabel>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(plannedMasterRepoProvider);
  return repository.listNecessityLabels();
});
