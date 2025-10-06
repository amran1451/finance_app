import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/plan.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/planned_master_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../data/repositories/necessity_repository.dart' as necessity_repo;
import '../utils/period_utils.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

PlanMaster _mapMaster(PlannedMaster source) {
  final id = source.id;
  if (id == null) {
    throw StateError('Master without id cannot be mapped');
  }
  return PlanMaster(
    id: id,
    name: source.title.trim(),
    amount: source.defaultAmountMinor ?? 0,
    categoryId: source.categoryId ?? 0,
    criticalityId: source.necessityId,
    note: source.note,
    isActive: !source.archived,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
  );
}

PlanInstance _mapInstance({
  required TransactionRecord record,
  required PlanMaster master,
  required PeriodRef period,
}) {
  final override = record.amountMinor == master.amount ? null : record.amountMinor;
  final scheduledAt = record.date;
  return PlanInstance(
    id: record.id ?? 0,
    masterId: master.id,
    period: period,
    overrideAmount: override,
    accountId: record.accountId,
    includedInPeriod: record.includedInPeriod,
    scheduledAt: scheduledAt,
    createdAt: scheduledAt,
    updatedAt: scheduledAt,
  );
}

final planMasterProvider = FutureProvider.family<PlanMaster, int>((ref, id) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(plannedMasterRepoProvider);
  final master = await repository.getById(id);
  if (master == null) {
    throw StateError('Не найден план с идентификатором $id');
  }
  return _mapMaster(master);
});

typedef PlanInstanceKey = ({int masterId, PeriodRef period});

final planInstanceProvider =
    FutureProvider.family<PlanInstance?, PlanInstanceKey>((ref, key) async {
  ref.watch(dbTickProvider);
  final master = await ref.watch(planMasterProvider(key.masterId).future);
  final entry = await ref.watch(periodEntryProvider(key.period).future);
  final transactionsRepo = ref.watch(transactionsRepoProvider);
  final records = await transactionsRepo.listPlannedByPeriod(
    start: entry.start,
    endExclusive: entry.endExclusive,
    type: 'expense',
  );
  for (final record in records) {
    if (record.plannedId == master.id) {
      return _mapInstance(record: record, master: master, period: key.period);
    }
  }
  return null;
});

class PlanRowVm {
  const PlanRowVm({
    required this.masterId,
    required this.title,
    required this.amount,
    required this.criticalityLabel,
    required this.included,
  });

  final int masterId;
  final String title;
  final int amount;
  final String? criticalityLabel;
  final bool included;
}

final _necessityLabelsProvider = FutureProvider<Map<int, necessity_repo.NecessityLabel>>((ref) async {
  final repository = ref.watch(necessityRepoProvider);
  final labels = await repository.list(includeArchived: true);
  return {
    for (final label in labels) label.id: label,
  };
});

final planRowsForPeriodProvider =
    FutureProvider.family<List<PlanRowVm>, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final entry = await ref.watch(periodEntryProvider(period).future);
  final transactionsRepo = ref.watch(transactionsRepoProvider);
  final masterRepo = ref.watch(plannedMasterRepoProvider);
  final necessityLabels = await ref.watch(_necessityLabelsProvider.future);
  final masters = await masterRepo.list(includeArchived: true);
  if (masters.isEmpty) {
    return const [];
  }
  final masterMap = {
    for (final master in masters)
      if (master.id != null) master.id!: _mapMaster(master),
  };
  if (masterMap.isEmpty) {
    return const [];
  }
  final records = await transactionsRepo.listPlannedByPeriod(
    start: entry.start,
    endExclusive: entry.endExclusive,
    type: 'expense',
  );
  if (records.isEmpty) {
    return const [];
  }
  final rows = <PlanRowVm>[];
  for (final record in records) {
    final plannedId = record.plannedId;
    if (plannedId == null) {
      continue;
    }
    final master = masterMap[plannedId];
    if (master == null) {
      continue;
    }
    final necessityId = master.criticalityId;
    final label =
        necessityId != null ? necessityLabels[necessityId]?.name : null;
    rows.add(
      PlanRowVm(
        masterId: master.id,
        title: master.name,
        amount: record.amountMinor,
        criticalityLabel: label,
        included: record.includedInPeriod,
      ),
    );
  }
  rows.sort((a, b) {
    final titleCompare = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (titleCompare != 0) {
      return titleCompare;
    }
    return a.masterId.compareTo(b.masterId);
  });
  return rows;
});
