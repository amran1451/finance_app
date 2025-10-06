import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/data/models/payout.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/data/repositories/transactions_repository.dart';
import 'package:finance_app/state/app_providers.dart';
import 'package:finance_app/state/budget_providers.dart';
import 'package:finance_app/state/operations_filters.dart';
import 'package:finance_app/utils/period_utils.dart';

class _FakeTransactionsRepository implements TransactionsRepository {
  _FakeTransactionsRepository({
    required this.responses,
    required this.payoutRecords,
  });

  final Map<String, List<TransactionListItem>> responses;
  final Map<int, TransactionRecord> payoutRecords;

  static String requestKey(DateTime start, DateTime endInclusive) {
    return '${start.toIso8601String()}|${endInclusive.toIso8601String()}';
  }

  static DateTime requestEnd(DateTime start, DateTime endExclusive) {
    final candidate = endExclusive.subtract(const Duration(days: 1));
    return candidate.isBefore(start) ? start : candidate;
  }

  @override
  Future<List<TransactionListItem>> getOperationItemsByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
    bool aggregateSavingPairs = false,
    String? periodId,
  }) async {
    final key = requestKey(from, to);
    return responses[key] ?? const [];
  }

  @override
  Future<TransactionRecord?> findByPayoutId(int payoutId) async {
    return payoutRecords[payoutId];
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

void main() {
  test('payout stays only in its actual period', () async {
    const anchors = (5, 20);
    const selectedPeriod =
        PeriodRef(year: 2024, month: 4, half: HalfPeriod.first);
    final actualPeriod = selectedPeriod.nextHalf();
    final selectedBounds = selectedPeriod.bounds(anchors.$1, anchors.$2);
    final actualBounds = actualPeriod.bounds(anchors.$1, anchors.$2);

    const payoutId = 1;
    final payout = Payout(
      id: payoutId,
      type: PayoutType.salary,
      date: DateTime(2024, 4, 18),
      amountMinor: 10000,
    );

    final payoutRecord = TransactionRecord(
      id: 10,
      accountId: 1,
      categoryId: 1,
      type: TransactionType.income,
      amountMinor: 10000,
      date: DateTime(2024, 4, 22),
    );

    final repository = _FakeTransactionsRepository(
      responses: {
        _FakeTransactionsRepository.requestKey(
          actualBounds.start,
          _FakeTransactionsRepository.requestEnd(
            actualBounds.start,
            actualBounds.endExclusive,
          ),
        ): [TransactionListItem(record: payoutRecord)],
      },
      payoutRecords: {payoutId: payoutRecord},
    );

    final container = ProviderContainer(
      overrides: [
        anchorDaysProvider.overrideWithValue(anchors),
        selectedPeriodRefProvider.overrideWith(
          (ref) => StateController<PeriodRef>(selectedPeriod),
        ),
        transactionsRepoProvider.overrideWithValue(repository),
        savingPairEnabledProvider.overrideWith((ref) async => false),
        payoutForSelectedPeriodProvider.overrideWith((ref) async => payout),
      ],
    );
    addTearDown(container.dispose);

    final firstPeriodResult = await container.read(
      periodOperationsProvider(
        (start: selectedBounds.start, endExclusive: selectedBounds.endExclusive),
      ).future,
    );
    expect(firstPeriodResult, isEmpty);

    container.read(selectedPeriodRefProvider.notifier).state = actualPeriod;

    final actualPeriodResult = await container.read(
      periodOperationsProvider(
        (start: actualBounds.start, endExclusive: actualBounds.endExclusive),
      ).future,
    );

    expect(actualPeriodResult, hasLength(1));
    expect(actualPeriodResult.first.record.id, payoutRecord.id);
  });
}
