import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:finance_app/data/models/account.dart';
import 'package:finance_app/data/models/category.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/data/repositories/periods_repository.dart';
import 'package:finance_app/data/repositories/planned_master_repository.dart';
import 'package:finance_app/data/repositories/transactions_repository.dart';
import 'package:finance_app/state/app_providers.dart';
import 'package:finance_app/state/budget_providers.dart';
import 'package:finance_app/state/planned_master_providers.dart';
import 'package:finance_app/ui/planned/expense_plan_sheets.dart';
import 'package:finance_app/utils/period_utils.dart';

class _RecordingTransactionsRepository implements TransactionsRepository {
  int? lastAssignedAccountId;
  bool? lastAssignedIncluded;
  int? lastAssignedMasterId;

  @override
  Future<void> assignMasterToPeriod({
    required int masterId,
    required DateTime start,
    required DateTime endExclusive,
    required int categoryId,
    required int amountMinor,
    required bool included,
    int? necessityId,
    String? note,
    required int accountId,
    DatabaseExecutor? executor,
  }) async {
    lastAssignedAccountId = accountId;
    lastAssignedIncluded = included;
    lastAssignedMasterId = masterId;
  }

  Never _unsupported() => throw UnimplementedError();

  @override
  Future<int> add(
    TransactionRecord record, {
    bool asSavingPair = false,
    bool? includedInPeriod,
    DatabaseExecutor? executor,
  }) => _unsupported();

  @override
  Future<void> delete(int id, {DatabaseExecutor? executor}) => _unsupported();

  @override
  Future<void> deleteInstancesByPlannedId(int plannedId,
          {DatabaseExecutor? executor}) =>
      _unsupported();

  @override
  Future<void> deletePlannedInstance(int plannedId,
          {DatabaseExecutor? executor}) =>
      _unsupported();

  @override
  Future<TransactionRecord?> findByPayoutId(int payoutId) => _unsupported();

  @override
  Future<List<TransactionRecord>> getAll() => _unsupported();

  @override
  Future<TransactionRecord?> getById(int id) => _unsupported();

  @override
  Future<List<TransactionRecord>> getByPeriod(
    DateTime from,
    DateTime to, {
    int? accountId,
    int? categoryId,
    TransactionType? type,
    bool? isPlanned,
    bool? includedInPeriod,
  }) =>
      _unsupported();

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
  }) =>
      _unsupported();

  @override
  Future<List<TransactionRecord>> listPlanned({
    TransactionType? type,
    bool onlyIncluded = false,
  }) =>
      _unsupported();

  @override
  Future<List<TransactionItem>> listPlannedByPeriod({
    required DateTime start,
    required DateTime endExclusive,
    String? type,
    bool? onlyIncluded,
  }) =>
      _unsupported();

  @override
  Future<int> createPlannedInstance({
    required int plannedId,
    required String type,
    required int accountId,
    required int amountMinor,
    required DateTime date,
    required int categoryId,
    String? note,
    int? necessityId,
    String? necessityLabel,
    bool includedInPeriod = false,
    int criticality = 0,
    DatabaseExecutor? executor,
  }) =>
      _unsupported();

  @override
  Future<void> setIncludedInPeriod({
    required int transactionId,
    required bool value,
    DatabaseExecutor? executor,
  }) =>
      _unsupported();

  @override
  Future<void> setPlannedCompletion(int id, bool isCompleted,
          {DatabaseExecutor? executor}) =>
      _unsupported();

  @override
  Future<void> setPlannedIncluded(int plannedId, bool included,
          {DatabaseExecutor? executor}) =>
      _unsupported();

  @override
  Future<int> sumActualExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  }) =>
      _unsupported();

  @override
  Future<int> sumExpensesOnDateWithinPeriod({
    required DateTime date,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
  }) =>
      _unsupported();

  @override
  Future<int> sumIncludedPlannedExpenses({
    required PeriodRef period,
    required DateTime start,
    required DateTime endExclusive,
  }) =>
      _unsupported();

  @override
  Future<int> sumUnplannedExpensesInRange(
          DateTime from, DateTime toExclusive) =>
      _unsupported();

  @override
  Future<int> sumUnplannedExpensesOnDate(DateTime date) => _unsupported();

  @override
  Future<void> update(
    TransactionRecord record, {
    bool? includedInPeriod,
    DatabaseExecutor? executor,
  }) =>
      _unsupported();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assign flow passes selected account to repository',
      (WidgetTester tester) async {
    final period = PeriodRef(year: 2024, month: 1, half: HalfPeriod.first);
    const entry = PeriodEntry(
      id: 1,
      year: 2024,
      month: 1,
      half: HalfPeriod.first,
      start: DateTime(2024, 1, 1),
      endExclusive: DateTime(2024, 2, 1),
      closed: false,
    );
    final master = PlannedMasterView(
      id: 42,
      type: 'expense',
      title: 'План расходов',
      defaultAmountMinor: 1500,
      categoryId: 7,
      note: null,
      archived: false,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      assignedNow: false,
      assignedPeriodStart: null,
      assignedPeriodEndExclusive: null,
      necessityId: null,
      necessityName: null,
      necessityColor: null,
      categoryName: 'Продукты',
    );
    final category = Category(
      id: master.categoryId,
      type: CategoryType.expense,
      name: 'Продукты',
    );
    final accounts = [
      const Account(id: 1, name: 'Карта', currency: 'RUB', startBalanceMinor: 0),
      const Account(
        id: 2,
        name: 'Наличные',
        currency: 'RUB',
        startBalanceMinor: 0,
      ),
    ];
    final fakeRepo = _RecordingTransactionsRepository();
    final assignedCompleter = Completer<bool>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsRepoProvider.overrideWithValue(fakeRepo),
          accountsDbProvider.overrideWith((ref) async => accounts),
          categoriesByTypeProvider.overrideWith(
            (ref, type) async => type == CategoryType.expense
                ? <Category>[category]
                : const <Category>[],
          ),
          categoriesMapProvider.overrideWith(
            (ref) async => {
              if (category.id != null) category.id!: category,
            },
          ),
          availableExpenseMastersProvider.overrideWith(
            (ref, args) async => <PlannedMasterView>[master],
          ),
          periodEntryProvider.overrideWith((ref, _) async => entry),
          necessityLabelsFutureProvider.overrideWith((ref) async => const []),
          selectedPeriodRefProvider.overrideWith((ref) => period),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final assigned =
                        await showSelectFromMasterSheet(context, period);
                    if (!assignedCompleter.isCompleted) {
                      assignedCompleter.complete(assigned);
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Назначить'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Назначить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assign_plan_account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Наличные').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Назначить'));
    await tester.pumpAndSettle();

    expect(await assignedCompleter.future, isTrue);
    expect(fakeRepo.lastAssignedAccountId, 2);
    expect(fakeRepo.lastAssignedIncluded, isTrue);
    expect(fakeRepo.lastAssignedMasterId, master.id);
  });
}
