import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transaction_record.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
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

    return repository.getOperationItemsByPeriod(
      bounds.start,
      endInclusive,
      type: type,
      isPlanned: false,
      aggregateSavingPairs: savingPairEnabled,
    );
  },
);
