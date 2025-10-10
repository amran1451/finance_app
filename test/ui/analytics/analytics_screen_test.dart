import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finance_app/data/db/app_database.dart';
import 'package:finance_app/data/models/analytics.dart';
import 'package:finance_app/data/models/transaction_record.dart';
import 'package:finance_app/data/repositories/analytics_repository.dart';
import 'package:finance_app/state/analytics_providers.dart';
import 'package:finance_app/state/budget_providers.dart';
import 'package:finance_app/state/app_providers.dart';
import 'package:finance_app/ui/analytics/analytics_screen.dart';

class _FakeAnalyticsRepository extends AnalyticsRepository {
  _FakeAnalyticsRepository({
    required this.plannedCriticality,
    required this.plannedCategories,
    required this.unplannedReasons,
    required this.unplannedCategories,
    required this.series,
  }) : super(database: AppDatabase.instance);

  final List<AnalyticsPieSlice> plannedCriticality;
  final List<AnalyticsPieSlice> plannedCategories;
  final List<AnalyticsPieSlice> unplannedReasons;
  final List<AnalyticsPieSlice> unplannedCategories;
  final List<AnalyticsTimePoint> series;

  @override
  Future<List<AnalyticsPieSlice>> loadExpenseBreakdown({
    required AnalyticsBreakdown breakdown,
    required DateTime from,
    required DateTime to,
    TransactionType type = TransactionType.expense,
    bool plannedOnly = false,
    bool unplannedOnly = false,
  }) async {
    switch (breakdown) {
      case AnalyticsBreakdown.plannedCriticality:
        return plannedCriticality;
      case AnalyticsBreakdown.plannedCategory:
        return plannedCategories;
      case AnalyticsBreakdown.unplannedReason:
        return unplannedReasons;
      case AnalyticsBreakdown.unplannedCategory:
        return unplannedCategories;
    }
  }

  @override
  Future<List<AnalyticsTimePoint>> loadExpenseSeries({
    required AnalyticsInterval interval,
    required DateTime from,
    required DateTime to,
    TransactionType type = TransactionType.expense,
    bool plannedOnly = false,
    bool unplannedOnly = false,
  }) async {
    return series;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final plannedSlices = [
    const AnalyticsPieSlice(
      label: 'Коммуналка',
      valueMinor: 5400,
      operationCount: 2,
    ),
    const AnalyticsPieSlice(
      label: 'Еда',
      valueMinor: 3200,
      operationCount: 1,
    ),
  ];

  final unplannedSlices = [
    const AnalyticsPieSlice(
      label: 'Эмоции',
      valueMinor: 4100,
      operationCount: 3,
    ),
  ];

  final series = [
    const AnalyticsTimePoint(bucket: '2024-01-10', valueMinor: 4200, sortKey: '2024-01-10'),
    const AnalyticsTimePoint(bucket: '2024-01-12', valueMinor: 2500, sortKey: '2024-01-12'),
  ];

  testWidgets('renders analytics charts and switches tabs', (tester) async {
    final fakeRepo = _FakeAnalyticsRepository(
      plannedCriticality: plannedSlices,
      plannedCategories: plannedSlices.reversed.toList(),
      unplannedReasons: unplannedSlices,
      unplannedCategories: unplannedSlices,
      series: series,
    );

    final analyticsFilterOverride = analyticsFilterProvider.overrideWith((ref) {
      return AnalyticsFilterNotifier(
        AnalyticsFilterState(
          from: DateTime(2024, 1, 1),
          to: DateTime(2024, 1, 31),
          interval: AnalyticsInterval.days,
          preset: AnalyticsRangePreset.custom,
        ),
        1,
        15,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepoProvider.overrideWithValue(fakeRepo),
          anchorDaysProvider.overrideWithValue((1, 15)),
          analyticsFilterOverride,
        ],
        child: const MaterialApp(
          home: AnalyticsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('По критичности'), findsOneWidget);
    expect(find.text('По категориям'), findsOneWidget);
    expect(find.textContaining('Коммуналка'), findsOneWidget);

    await tester.tap(find.text('Месяцы'));
    await tester.pumpAndSettle();
    expect(find.text('Месяцы'), findsWidgets);

    await tester.tap(find.text('Внеплановые'));
    await tester.pumpAndSettle();
    expect(find.text('По причинам'), findsOneWidget);
    expect(find.textContaining('Эмоции'), findsWidgets);
  });
}
