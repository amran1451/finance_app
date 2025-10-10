import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transaction_record.dart';
import '../data/repositories/transactions_repository.dart';
import '../utils/period_utils.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

enum OpTypeFilter { all, expense, income, saving }

final opTypeFilterProvider = StateProvider<OpTypeFilter>((_) => OpTypeFilter.all);

typedef PeriodBounds = ({DateTime start, DateTime endExclusive});

final periodOperationsProvider =
    FutureProvider.family<List<TransactionListItem>, PeriodBounds>(
  (ref, bounds) async {
    ref.watch(dbTickProvider);
    final repository = ref.watch(transactionsRepoProvider);
    final filter = ref.watch(opTypeFilterProvider);
    final savingPairEnabled = await ref.watch(savingPairEnabledProvider.future);
    final selectedPeriod = ref.watch(selectedPeriodRefProvider);

    TransactionType? type;
    switch (filter) {
      case OpTypeFilter.all:
        type = null;
        break;
      case OpTypeFilter.expense:
        type = TransactionType.expense;
        break;
      case OpTypeFilter.income:
        type = TransactionType.income;
        break;
      case OpTypeFilter.saving:
        type = TransactionType.saving;
        break;
    }

    var endInclusive = bounds.endExclusive.subtract(const Duration(days: 1));
    if (endInclusive.isBefore(bounds.start)) {
      endInclusive = bounds.start;
    }

    final transactions = await repository.getOperationItemsByPeriod(
      bounds.start,
      endInclusive,
      type: type,
      isPlanned: false,
      aggregateSavingPairs: savingPairEnabled,
      periodId: selectedPeriod.id,
    );

    final result = [...transactions];

    final plannedTransactions = await repository.getOperationItemsByPeriod(
      bounds.start,
      endInclusive,
      type: type,
      isPlanned: true,
      aggregateSavingPairs: false,
      periodId: selectedPeriod.id,
    );

    final plannedIdsWithActual = <int>{
      for (final item in transactions)
        if (item.record.planInstanceId != null)
          item.record.planInstanceId!,
    };

    for (final planned in plannedTransactions) {
      final plannedId = planned.record.id;
      if (plannedId != null && plannedIdsWithActual.contains(plannedId)) {
        continue;
      }
      result.add(planned);
    }

    result.sort((a, b) {
      final cmp = b.record.date.compareTo(a.record.date);
      if (cmp != 0) {
        return cmp;
      }
      final aId = a.record.id ?? 0;
      final bId = b.record.id ?? 0;
      return bId.compareTo(aId);
    });

    if (filter == OpTypeFilter.all || filter == OpTypeFilter.income) {
      final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
      final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
      final payoutId = payout?.id;
      if (payoutId != null) {
        final payoutRecord = await repository.findByPayoutId(payoutId);
        if (payoutRecord != null) {
          final normalizedStart = normalizeDate(bounds.start);
          final normalizedEndExclusive = normalizeDate(bounds.endExclusive);
          final payoutDate = normalizeDate(payoutRecord.date);
          final withinBounds = !payoutDate.isBefore(normalizedStart) &&
              payoutDate.isBefore(normalizedEndExclusive);
          final alreadyIncluded = result.any(
            (item) => item.record.id != null &&
                item.record.id == payoutRecord.id,
          );
          final actualPeriod =
              periodRefForDate(payoutRecord.date, anchor1, anchor2);
          final assignedPeriodId = payoutRecord.payoutPeriodId;
          final isActualPeriodSelected =
              actualPeriod.year == selectedPeriod.year &&
                  actualPeriod.month == selectedPeriod.month &&
                  actualPeriod.half == selectedPeriod.half;
          final matchesAssigned = assignedPeriodId != null
              ? assignedPeriodId == selectedPeriod.id
              : isActualPeriodSelected;
          if (!alreadyIncluded && !withinBounds && matchesAssigned) {
            result.add(TransactionListItem(record: payoutRecord));
            result.sort((a, b) {
              final cmp = b.record.date.compareTo(a.record.date);
              if (cmp != 0) {
                return cmp;
              }
              final aId = a.record.id ?? 0;
              final bId = b.record.id ?? 0;
              return bId.compareTo(aId);
            });
          }
        }
      }
    }

    return result;
  },
);
