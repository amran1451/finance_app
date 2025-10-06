import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payout.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/periods_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../utils/payout_rules.dart';
import 'app_providers.dart';
import 'db_refresh.dart';
import '../utils/period_utils.dart';
import '../utils/plan_formatting.dart';

typedef BudgetPeriodInfo = ({
  DateTime start,
  DateTime end,
  DateTime anchorStart,
  int days,
});

int calculateMaxDailyLimitMinor({
  required int remainingBudgetMinor,
  required DateTime periodStart,
  required DateTime periodEndExclusive,
  required DateTime today,
  required DateTime payoutDate,
  required bool fromToday,
}) {
  if (remainingBudgetMinor <= 0) {
    return 0;
  }

  final normalizedStart = DateUtils.dateOnly(periodStart);
  final normalizedToday = DateUtils.dateOnly(today);
  final normalizedPayout = DateUtils.dateOnly(payoutDate);
  final normalizedEndExclusive = DateUtils.dateOnly(periodEndExclusive);
  final periodEndDate = normalizedEndExclusive.subtract(const Duration(days: 1));
  var baseDate = fromToday ? normalizedToday : normalizedPayout;

  final earliestAllowed = normalizedStart.subtract(
    const Duration(days: kEarlyPayoutGraceDays),
  );
  if (baseDate.isBefore(earliestAllowed)) {
    baseDate = earliestAllowed;
  }

  if (baseDate.isAfter(periodEndDate)) {
    baseDate = periodEndDate;
  }

  final rawDaysLeft = periodEndDate.difference(baseDate).inDays + 1;
  final daysLeft = math.max(rawDaysLeft, 1);

  if (daysLeft == 1) {
    return remainingBudgetMinor;
  }

  return remainingBudgetMinor ~/ daysLeft;
}

// TODO: Persist selected period in Settings (ui.selected_period_ref).

final anchorDaysFutureProvider = FutureProvider<(int, int)>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(settingsRepoProvider);
  final day1 = await repository.getAnchorDay1();
  final day2 = await repository.getAnchorDay2();
  final anchors = [day1, day2]..sort();
  final first = _normalizeAnchorDay(anchors[0]);
  final second = _normalizeAnchorDay(anchors[1]);
  return (first, second);
});

final anchorDaysProvider = Provider<(int, int)>((ref) {
  final asyncAnchors = ref.watch(anchorDaysFutureProvider);
  return asyncAnchors.when(
    data: (value) => value,
    loading: () => (1, 15),
    error: (_, __) => (1, 15),
  );
});

final selectedPeriodRefProvider = StateProvider<PeriodRef>((ref) {
  final (a1, a2) = ref.watch(anchorDaysProvider);
  final now = DateTime.now();
  return periodRefForDate(now, a1, a2);
});

final periodEntryProvider = FutureProvider.family<PeriodEntry, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(periodsRepoProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  return repository.getOrCreate(
    period.year,
    period.month,
    period.half,
    bounds.start,
    bounds.endExclusive,
  );
});

final selectedPeriodEntryProvider = FutureProvider<PeriodEntry>((ref) async {
  final period = ref.watch(selectedPeriodRefProvider);
  return ref.watch(periodEntryProvider(period).future);
});

final periodStatusProvider = FutureProvider.family<PeriodStatus, PeriodRef>((ref, period) async {
  await ref.watch(periodEntryProvider(period).future);
  final repository = ref.watch(periodsRepoProvider);
  return repository.getStatus(period);
});

final plannedIncludedAmountForEntryProvider =
    FutureProvider.family<int, PeriodEntry>((ref, entry) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final items = await repository.listPlannedByPeriod(
    start: entry.start,
    endExclusive: entry.endExclusive,
    type: 'expense',
    onlyIncluded: true,
  );
  if (items.isEmpty) {
    return 0;
  }
  return items.fold<int>(0, (sum, item) => sum + item.amountMinor);
});

final plannedIncludedAmountForPeriodProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  final entry = await ref.watch(periodEntryProvider(period).future);
  return ref.watch(plannedIncludedAmountForEntryProvider(entry).future);
});

final spentForPeriodProvider = FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final entry = await ref.watch(periodEntryProvider(period).future);
  final unplanned = await repository.sumUnplannedExpensesInRange(
    entry.start,
    entry.endExclusive,
  );
  final planned = await ref.watch(plannedIncludedAmountForEntryProvider(entry).future);
  return unplanned + planned;
});

final canCloseCurrentPeriodProvider = Provider<bool>((ref) {
  return ref.watch(periodToCloseProvider) != null;
});

final payoutSuggestedTypeProvider = Provider<PayoutType>((ref) {
  final sel = ref.watch(selectedPeriodRefProvider);
  return allowedPayoutTypeForHalf(sel.half);
});

String payoutTypeLabel(PayoutType type) =>
    type == PayoutType.salary ? 'Зарплата' : 'Аванс';

final payoutsHistoryProvider = FutureProvider<List<Payout>>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(payoutsRepoProvider);
  return repository.getHistory(30);
});

/// (start, endExclusive) для выбранного периода (конкретный месяц)
final periodBoundsProvider = Provider<(DateTime start, DateTime endExclusive)>((ref) {
  final entryAsync = ref.watch(selectedPeriodEntryProvider);
  return entryAsync.maybeWhen(
    data: (entry) => (entry.start, entry.endExclusive),
    orElse: () {
      final (a1, a2) = ref.watch(anchorDaysProvider);
      final sel = ref.watch(selectedPeriodRefProvider);
      final bounds = periodBoundsFor(sel, a1, a2);
      return (bounds.start, bounds.endExclusive);
    },
  );
});

@Deprecated('Use periodBoundsProvider')
final halfPeriodBoundsProvider = periodBoundsProvider;

/// Выплата, относящаяся к выбранному на Главной полупериоду (месяц+half)
final periodBoundsForProvider =
    Provider.family<(DateTime start, DateTime endExclusive), PeriodRef>(
  (ref, period) {
    final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
    final bounds = period.bounds(anchor1, anchor2);
    return (bounds.start, bounds.endExclusive);
  },
);

final payoutForPeriodProvider =
    FutureProvider.family<Payout?, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final entry = await ref.watch(periodEntryProvider(period).future);
  final start = entry.start;
  final endEx = entry.endExclusive;
  final repo = ref.watch(payoutsRepoProvider);
  try {
    return await repo.findInRange(
      start,
      endEx,
      assignedPeriodId: period.id,
    );
  } catch (error, stackTrace) {
    if (_isMissingRepoMethod(error)) {
      debugPrint(
        'Payout lookup failed for range [$start; $endEx): $error',
      );
      return null;
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
});

final payoutForSelectedPeriodProvider = FutureProvider<Payout?>((ref) async {
  ref.watch(dbTickProvider);
  final period = ref.watch(selectedPeriodRefProvider);
  return ref.watch(payoutForPeriodProvider(period).future);
});

/// Отображаемый заголовок текущего периода в формате «dd MMM – dd MMM».
String _formatPeriodLabel(Ref ref, PeriodRef period) {
  String formatRange(DateTime start, DateTime endExclusive) {
    return compactPeriodLabel(start, endExclusive) ?? '';
  }

  final entryAsync = ref.watch(periodEntryProvider(period));
  return entryAsync.maybeWhen(
    data: (entry) => formatRange(entry.start, entry.endExclusive),
    orElse: () {
      final bounds = ref.watch(periodBoundsForProvider(period));
      return formatRange(bounds.$1, bounds.$2);
    },
  );
}

final periodLabelForRefProvider =
    Provider.family<String, PeriodRef>((ref, period) {
  return _formatPeriodLabel(ref, period);
});

final periodLabelProvider = Provider<String>((ref) {
  final period = ref.watch(selectedPeriodRefProvider);
  final fallback = _formatPeriodLabel(ref, period);
  final periodInfo = ref.watch(currentPeriodProvider);
  return periodInfo.maybeWhen(
    data: (value) =>
        compactPeriodLabel(value.anchorStart, value.end) ?? fallback,
    orElse: () => fallback,
  );
});

final periodCloseBannerHiddenUntilProvider =
    FutureProvider<DateTime?>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(settingsRepoProvider);
  return repository.getPeriodCloseBannerHiddenUntil();
});

final periodToCloseProvider = Provider<PeriodRef?>((ref) {
  ref.watch(dbTickProvider);
  final hiddenUntilAsync = ref.watch(periodCloseBannerHiddenUntilProvider);
  final hiddenUntil = hiddenUntilAsync.maybeWhen(
    data: (value) => value,
    orElse: () => null,
  );
  if (hiddenUntil != null) {
    final now = DateTime.now();
    if (now.isBefore(hiddenUntil)) {
      final duration = hiddenUntil.difference(now);
      if (duration.isPositive) {
        final timer = Timer(duration, ref.invalidateSelf);
        ref.onDispose(timer.cancel);
      }
      return null;
    }
  }
  final selected = ref.watch(selectedPeriodRefProvider);
  if (_canClosePeriodRef(ref, selected)) {
    return selected;
  }
  final previous = selected.prevHalf();
  if (_canClosePeriodRef(ref, previous)) {
    return previous;
  }
  return null;
});

extension PeriodNav on StateController<PeriodRef> {
  void goPrev() {
    state = state.prevHalf();
  }

  void goNext() {
    state = state.nextHalf();
  }

  void goToTodayHalf(int anchor1, int anchor2) {
    final today = DateTime.now();
    state = periodRefForDate(today, anchor1, anchor2);
  }
}

/// Удобный notifer с доступом к якорям
final periodNavProvider = Provider((ref) {
  final (a1, a2) = ref.watch(anchorDaysProvider);
  final ctrl = ref.read(selectedPeriodRefProvider.notifier);
  return (
    prev: ctrl.goPrev,
    next: ctrl.goNext,
    goToToday: () => ctrl.goToTodayHalf(a1, a2),
  );
});

final currentPayoutProvider = Provider<AsyncValue<Payout?>>((ref) {
  return ref.watch(payoutForSelectedPeriodProvider);
});

final currentPeriodProvider = FutureProvider<BudgetPeriodInfo>((ref) async {
  ref.watch(dbTickProvider);
  final bounds = ref.watch(periodBoundsProvider);
  final periodStart = DateUtils.dateOnly(bounds.$1);
  final periodEndExclusive = DateUtils.dateOnly(bounds.$2);
  final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
  final today = DateUtils.dateOnly(DateTime.now());
  var anchorStart = periodStart;
  if (payout != null &&
      !today.isBefore(periodStart) &&
      today.isBefore(periodEndExclusive)) {
    final payoutDate = DateUtils.dateOnly(payout.date);
    final graceStart = periodStart.subtract(
      const Duration(days: kEarlyPayoutGraceDays),
    );
    if (!payoutDate.isBefore(graceStart) && payoutDate.isBefore(periodStart)) {
      anchorStart = payoutDate;
    }
  }
  var days = periodEndExclusive.difference(anchorStart).inDays;
  if (days <= 0) {
    days = 1;
  }
  return (
    start: anchorStart,
    end: bounds.$2,
    anchorStart: anchorStart,
    days: days,
  );
});

/// Является ли текущий выбранный период активным относительно сегодняшнего дня.
final isActivePeriodProvider = Provider<bool>((ref) {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  final periodAsync = ref.watch(currentPeriodProvider);
  return periodAsync.maybeWhen(
    data: (period) {
      final today = normalizeDate(DateTime.now());
      final start = normalizeDate(period.anchorStart);
      final endExclusive = normalizeDate(period.end);
      return !today.isBefore(start) && today.isBefore(endExclusive);
    },
    orElse: () => false,
  );
});

final todayDateProvider = Provider<DateTime>((ref) {
  return DateUtils.dateOnly(DateTime.now());
});

/// Принадлежит ли произвольная дата активному периоду (currentPeriodProvider)
final isInCurrentPeriodProvider = Provider.family<bool, DateTime>((ref, date) {
  final period = ref.watch(currentPeriodProvider).value;
  if (period == null) {
    return false;
  }
  final normalized = normalizeDate(date);
  final start = normalizeDate(period.anchorStart);
  final end = normalizeDate(period.end);
  return !normalized.isBefore(start) && normalized.isBefore(end);
});

/// Количество дней до следующей выплаты от сегодняшней даты.
final daysUntilNextPayoutFromTodayProvider = Provider<int>((ref) {
  ref.watch(dbTickProvider);
  ref.watch(selectedPeriodRefProvider);
  if (!ref.watch(isActivePeriodProvider)) {
    return 0;
  }
  final periodAsync = ref.watch(currentPeriodProvider);
  return periodAsync.maybeWhen(
    data: (period) {
      final today = normalizeDate(DateTime.now());
      final endExclusive = normalizeDate(period.end);
      final diff = endExclusive.difference(today).inDays;
      return math.max(diff, 0);
    },
    orElse: () => 0,
  );
});

final periodDailyLimitProvider = Provider<int>((ref) {
  ref.watch(dbTickProvider);
  final payout = ref.watch(currentPayoutProvider).valueOrNull;
  return payout?.dailyLimitMinor ?? 0;
});

final periodDailyLimitFromTodayFlagProvider = Provider<bool>((ref) {
  ref.watch(dbTickProvider);
  final payout = ref.watch(currentPayoutProvider).valueOrNull;
  return payout?.dailyLimitFromToday ?? false;
});

final periodDaysFromPayoutProvider = Provider<int>((ref) {
  final period = ref.watch(currentPeriodProvider).valueOrNull;
  if (period == null) {
    return 0;
  }
  return math.max(period.days, 0);
});

final remainingDaysFromTodayProvider = Provider<int>((ref) {
  ref.watch(dbTickProvider);
  if (!ref.watch(isActivePeriodProvider)) {
    return 0;
  }
  final period = ref.watch(currentPeriodProvider).valueOrNull;
  if (period == null) {
    return 0;
  }
  final today = DateUtils.dateOnly(DateTime.now());
  final endExclusive = DateUtils.dateOnly(period.end);
  final remaining = endExclusive.difference(today).inDays;
  if (remaining <= 0) {
    return 0;
  }
  return remaining > 9999 ? 9999 : remaining;
});

class MetricsSnapshot {
  const MetricsSnapshot({
    required this.todaySpent,
    required this.dailyLimit,
    required this.dailyLeft,
    required this.periodBudgetLeft,
    required this.todayProgress,
  });

  final int todaySpent;
  final int dailyLimit;
  final int dailyLeft;
  final int periodBudgetLeft;
  final double todayProgress;

  bool get hasDailyLimit => dailyLimit > 0;
}

class MetricsController extends AsyncNotifier<MetricsSnapshot> {
  @override
  Future<MetricsSnapshot> build() {
    return _computeSnapshot();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_computeSnapshot);
  }

  Future<MetricsSnapshot> _computeSnapshot() async {
    ref.watch(dbTickProvider);
    final period = ref.watch(selectedPeriodRefProvider);
    final (start, endExclusive) = ref.watch(periodBoundsProvider);
    final repository = ref.watch(transactionsRepoProvider);
    final today = DateUtils.dateOnly(ref.watch(todayDateProvider));
    final dailyLimit = ref.watch(periodDailyLimitProvider);
    final periodBudgetBase = ref.watch(periodBudgetBaseProvider);

    final normalizedStart = DateUtils.dateOnly(start);
    final normalizedEndExclusive = DateUtils.dateOnly(endExclusive);

    final todaySpent = await repository.sumExpensesOnDateWithinPeriod(
      date: today,
      periodStart: normalizedStart,
      periodEndExclusive: normalizedEndExclusive,
    );

    final dailyLeft = math.max(0, dailyLimit - todaySpent);

    var periodBudgetLeft = math.max(0, periodBudgetBase);
    if (periodBudgetBase > 0) {
      final spent = await repository.sumActualExpenses(
        period: period,
        start: normalizedStart,
        endExclusive: normalizedEndExclusive,
      );
      periodBudgetLeft = math.max(0, periodBudgetBase - spent);
    }

    final todayProgress = dailyLimit > 0
        ? (todaySpent / math.max(1, dailyLimit)).clamp(0.0, 1.0)
        : 0.0;

    return MetricsSnapshot(
      todaySpent: todaySpent,
      dailyLimit: dailyLimit,
      dailyLeft: dailyLeft,
      periodBudgetLeft: periodBudgetLeft,
      todayProgress: todayProgress,
    );
  }
}

final metricsProvider =
    AsyncNotifierProvider<MetricsController, MetricsSnapshot>(
  MetricsController.new,
);

final todaySpentProvider = Provider<int>((ref) {
  final metrics = ref.watch(metricsProvider);
  return metrics.maybeWhen(
    data: (value) => value.todaySpent,
    orElse: () => 0,
  );
});

final dailyLeftProvider = Provider<int>((ref) {
  final metrics = ref.watch(metricsProvider);
  return metrics.maybeWhen(
    data: (value) => value.dailyLeft,
    orElse: () => 0,
  );
});

final periodBudgetLeftProvider = Provider<int>((ref) {
  final metrics = ref.watch(metricsProvider);
  return metrics.maybeWhen(
    data: (value) => value.periodBudgetLeft,
    orElse: () => 0,
  );
});

final todayProgressRatioProvider = Provider<double>((ref) {
  final metrics = ref.watch(metricsProvider);
  return metrics.maybeWhen(
    data: (value) => value.todayProgress,
    orElse: () => 0,
  );
});

final periodBudgetBaseProvider = Provider<int>((ref) {
  final limit = ref.watch(periodDailyLimitProvider);
  if (limit <= 0) {
    return 0;
  }
  final fromToday = ref.watch(periodDailyLimitFromTodayFlagProvider);
  final baseDays = ref.watch(periodDaysFromPayoutProvider);
  final remDays = ref.watch(remainingDaysFromTodayProvider);
  final days = fromToday ? remDays : baseDays;
  if (days <= 0) {
    return 0;
  }
  return limit * days;
});

final sumActualExpensesProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final entry = await ref.watch(periodEntryProvider(period).future);
  final repo = ref.watch(transactionsRepoProvider);
  return repo.sumActualExpenses(
    period: period,
    start: entry.start,
    endExclusive: entry.endExclusive,
  );
});

final remainingBudgetForPeriodProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
  if (payout == null) {
    return 0;
  }
  final entry = await ref.watch(periodEntryProvider(period).future);
  final repository = ref.watch(transactionsRepoProvider);
  final periodStart = DateUtils.dateOnly(entry.start);
  final periodEndExclusive = DateUtils.dateOnly(entry.endExclusive);
  final spent = await repository.sumActualExpenses(
    period: period,
    start: periodStart,
    endExclusive: periodEndExclusive,
  );
  final remaining = payout.amountMinor - spent;
  return remaining > 0 ? remaining : 0;
});

final plannedPoolBaseProvider = FutureProvider<int>((ref) async {
  ref.watch(dbTickProvider);
  final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
  if (payout == null) {
    return 0;
  }
  final periodBudget = ref.watch(periodBudgetBaseProvider);
  final pool = payout.amountMinor - periodBudget;
  return math.max(pool, 0);
});

final halfPeriodTransactionsProvider = FutureProvider<List<TransactionRecord>>((ref) async {
  ref.watch(dbTickProvider);
  final (start, endExclusive) = ref.watch(periodBoundsProvider);
  final period = ref.watch(selectedPeriodRefProvider);
  final repo = ref.watch(transactionsRepoProvider);
  var endInclusive = endExclusive.subtract(const Duration(days: 1));
  if (endInclusive.isBefore(start)) {
    endInclusive = start;
  }
  return repo.getByPeriod(
    start,
    endInclusive,
    isPlanned: false,
    includedInPeriod: true,
    periodId: period.id,
  );
});

final anchorDaysManagerProvider = Provider<AnchorDaysManager>((ref) {
  return AnchorDaysManager(ref);
});

final budgetLimitManagerProvider = Provider<BudgetLimitManager>((ref) {
  return BudgetLimitManager(ref);
});

class AnchorDaysManager {
  AnchorDaysManager(this._ref);

  final Ref _ref;

  Future<void> saveAnchorDay1(int value) async {
    final repository = _ref.read(settingsRepoProvider);
    await repository.setAnchorDay1(value);
    _bumpTick();
  }

  Future<void> saveAnchorDay2(int value) async {
    final repository = _ref.read(settingsRepoProvider);
    await repository.setAnchorDay2(value);
    _bumpTick();
  }

  Future<void> saveAnchorDays(int first, int second) async {
    final repository = _ref.read(settingsRepoProvider);
    await repository.setAnchorDay1(first);
    await repository.setAnchorDay2(second);
    _bumpTick();
  }

  void _bumpTick() {
    final notifier = _ref.read(dbTickProvider.notifier);
    notifier.state = notifier.state + 1;
  }
}

class BudgetLimitManager {
  BudgetLimitManager(this._ref);

  final Ref _ref;

  Future<int?> adjustDailyLimitIfNeeded({
    required Payout payout,
    required PeriodRef period,
  }) async {
    final payoutId = payout.id;
    if (payoutId == null) {
      return null;
    }

    final currentDailyLimit = payout.dailyLimitMinor;
    if (currentDailyLimit <= 0) {
      return null;
    }

    final (anchor1, anchor2) = await _ref.read(anchorDaysFutureProvider.future);
    final bounds = periodBoundsFor(period, anchor1, anchor2);
    final periodDays = bounds.endExclusive.difference(bounds.start).inDays;
    if (periodDays <= 0) {
      return null;
    }

    final repository = _ref.read(transactionsRepoProvider);
    final spent = await repository.sumActualExpenses(
      period: period,
      start: bounds.start,
      endExclusive: bounds.endExclusive,
    );
    final remainingBudget = payout.amountMinor - spent;
    final today = DateUtils.dateOnly(DateTime.now());
    final maxDaily = calculateMaxDailyLimitMinor(
      remainingBudgetMinor: remainingBudget,
      periodStart: bounds.start,
      periodEndExclusive: bounds.endExclusive,
      today: today,
      payoutDate: payout.date,
      fromToday: payout.dailyLimitFromToday,
    );
    if (maxDaily <= 0 || currentDailyLimit <= maxDaily) {
      return null;
    }

    await _ref.read(payoutsRepoProvider).setDailyLimit(
          payoutId: payoutId,
          dailyLimitMinor: maxDaily,
          fromToday: payout.dailyLimitFromToday,
        );
    return maxDaily;
  }
}

int _normalizeAnchorDay(int value) {
  if (value < 1) {
    return 1;
  }
  if (value > 31) {
    return 31;
  }
  return value;
}

bool _isMissingRepoMethod(Object error) {
  return error is NoSuchMethodError ||
      error is UnimplementedError ||
      error is UnsupportedError;
}

bool _canClosePeriodRef(Ref ref, PeriodRef period) {
  final statusAsync = ref.watch(periodStatusProvider(period));
  final isClosed = statusAsync.maybeWhen(
    data: (status) => status.closed,
    orElse: () => false,
  );
  if (isClosed) {
    return false;
  }

  final bounds = ref.watch(periodBoundsForProvider(period));
  final today = DateUtils.dateOnly(DateTime.now());
  final normalizedEndExclusive = DateUtils.dateOnly(bounds.$2);
  return !today.isBefore(normalizedEndExclusive);
}
