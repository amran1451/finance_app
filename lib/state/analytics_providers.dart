import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/analytics.dart';
import '../data/models/transaction_record.dart';
import '../utils/period_utils.dart';
import 'app_providers.dart';
import 'budget_providers.dart';
import 'db_refresh.dart';

enum AnalyticsRangePreset { currentHalf, thisMonth, lastMonth, custom }

enum AnalyticsTab { planned, unplanned }

@immutable
class AnalyticsFilterState {
  const AnalyticsFilterState({
    required this.from,
    required this.to,
    required this.interval,
    required this.preset,
  }) : assert(
          to.millisecondsSinceEpoch >= from.millisecondsSinceEpoch,
          'Invalid analytics range: [$from; $to]',
        );

  final DateTime from;
  final DateTime to;
  final AnalyticsInterval interval;
  final AnalyticsRangePreset preset;

  AnalyticsFilterState copyWith({
    DateTime? from,
    DateTime? to,
    AnalyticsInterval? interval,
    AnalyticsRangePreset? preset,
  }) {
    final nextFrom = from ?? this.from;
    final nextTo = to ?? this.to;
    return AnalyticsFilterState(
      from: nextFrom,
      to: nextTo,
      interval: interval ?? this.interval,
      preset: preset ?? this.preset,
    );
  }

  DateTime get normalizedFrom => DateTime(from.year, from.month, from.day);

  DateTime get normalizedTo => DateTime(to.year, to.month, to.day);
}

class AnalyticsFilterNotifier extends StateNotifier<AnalyticsFilterState> {
  AnalyticsFilterNotifier(
    AnalyticsFilterState initial,
    this._anchor1,
    this._anchor2,
  ) : super(initial);

  final int _anchor1;
  final int _anchor2;

  void setPreset(AnalyticsRangePreset preset) {
    switch (preset) {
      case AnalyticsRangePreset.currentHalf:
        _applyBounds(_currentHalfBounds(), preset);
        break;
      case AnalyticsRangePreset.thisMonth:
        _applyBounds(_monthBounds(DateTime.now()), preset);
        break;
      case AnalyticsRangePreset.lastMonth:
        _applyBounds(_monthBounds(DateTime(DateTime.now().year, DateTime.now().month - 1, 1)), preset);
        break;
      case AnalyticsRangePreset.custom:
        state = state.copyWith(preset: AnalyticsRangePreset.custom);
        break;
    }
  }

  void setCustomRange(DateTimeRange range) {
    final normalizedStart = DateTime(range.start.year, range.start.month, range.start.day);
    final normalizedEnd = DateTime(range.end.year, range.end.month, range.end.day);
    _applyBounds((start: normalizedStart, end: normalizedEnd), AnalyticsRangePreset.custom);
  }

  void setInterval(AnalyticsInterval interval) {
    state = state.copyWith(interval: interval);
  }

  ({DateTime start, DateTime end}) _currentHalfBounds() {
    final now = DateTime.now();
    final period = periodRefForDate(now, _anchor1, _anchor2);
    final bounds = period.bounds(_anchor1, _anchor2);
    final endInclusive = bounds.endExclusive.subtract(const Duration(days: 1));
    return (
      start: bounds.start,
      end: endInclusive.isBefore(bounds.start) ? bounds.start : endInclusive,
    );
  }

  ({DateTime start, DateTime end}) _monthBounds(DateTime monthSeed) {
    final normalized = DateTime(monthSeed.year, monthSeed.month, 1);
    final start = normalized;
    final endExclusive = DateTime(normalized.year, normalized.month + 1, 1);
    final endInclusive = endExclusive.subtract(const Duration(days: 1));
    return (start: start, end: endInclusive);
  }

  void _applyBounds(
    ({DateTime start, DateTime end}) bounds,
    AnalyticsRangePreset preset,
  ) {
    state = state.copyWith(
      from: bounds.start,
      to: bounds.end,
      preset: preset,
    );
  }
}

final analyticsFilterProvider =
    StateNotifierProvider<AnalyticsFilterNotifier, AnalyticsFilterState>((ref) {
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final notifier = AnalyticsFilterNotifier(
    AnalyticsFilterState(
      from: DateTime.now(),
      to: DateTime.now(),
      interval: AnalyticsInterval.days,
      preset: AnalyticsRangePreset.currentHalf,
    ),
    anchor1,
    anchor2,
  );
  notifier.setPreset(AnalyticsRangePreset.currentHalf);
  return notifier;
});

final analyticsPieProvider = FutureProvider.family<
    List<AnalyticsPieSlice>, ({AnalyticsBreakdown breakdown, AnalyticsTab tab})>((ref, request) async {
  ref.watch(dbTickProvider);
  final repo = ref.watch(analyticsRepoProvider);
  final filters = ref.watch(analyticsFilterProvider);
  final from = filters.normalizedFrom;
  final to = filters.normalizedTo;
  final plannedOnly = request.tab == AnalyticsTab.planned;
  final unplannedOnly = request.tab == AnalyticsTab.unplanned;
  return repo.loadExpenseBreakdown(
    breakdown: request.breakdown,
    from: from,
    to: to,
    type: TransactionType.expense,
    plannedOnly: plannedOnly,
    unplannedOnly: unplannedOnly,
  );
});

final analyticsSeriesProvider = FutureProvider.family<
    List<AnalyticsTimePoint>, AnalyticsTab>((ref, tab) async {
  ref.watch(dbTickProvider);
  final repo = ref.watch(analyticsRepoProvider);
  final filters = ref.watch(analyticsFilterProvider);
  final from = filters.normalizedFrom;
  final to = filters.normalizedTo;
  return repo.loadExpenseSeries(
    interval: filters.interval,
    from: from,
    to: to,
    type: TransactionType.expense,
    plannedOnly: tab == AnalyticsTab.planned,
    unplannedOnly: tab == AnalyticsTab.unplanned,
  );
});
