import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payout.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/periods_repository.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
import 'db_refresh.dart';
import '../utils/period_utils.dart';

typedef BudgetPeriodInfo = ({
  DateTime start,
  DateTime end,
  DateTime anchorStart,
  int days,
});

const _earlyPayoutGraceDays = 5;

int calculateMaxDailyLimitMinor({
  required int remainingBudgetMinor,
  required DateTime periodEndExclusive,
  required DateTime today,
}) {
  if (remainingBudgetMinor <= 0) {
    return 0;
  }

  final normalizedToday = DateUtils.dateOnly(today);
  final normalizedEndExclusive = DateUtils.dateOnly(periodEndExclusive);
  final periodEndDate = normalizedEndExclusive.subtract(const Duration(days: 1));
  final rawDaysLeft = periodEndDate.difference(normalizedToday).inDays + 1;
  final daysLeft = math.max(rawDaysLeft, 1);

  if (normalizedToday.isAtSameMomentAs(periodEndDate)) {
    return remainingBudgetMinor;
  }

  final value = remainingBudgetMinor ~/ daysLeft;
  return value;
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

final periodStatusProvider = FutureProvider.family<PeriodStatus, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(periodsRepoProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  await repository.getOrCreate(
    period.year,
    period.month,
    period.half,
    bounds.start,
    bounds.endExclusive,
  );
  return repository.getStatus(period);
});

final plannedIncludedAmountForPeriodProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final items = await repository.listPlannedByPeriod(
    start: bounds.start,
    endExclusive: bounds.endExclusive,
    type: 'expense',
    onlyIncluded: true,
  );
  if (items.isEmpty) {
    return 0;
  }
  return items.fold<int>(0, (sum, item) => sum + item.amountMinor);
});

final spentForPeriodProvider = FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(transactionsRepoProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final unplanned = await repository.sumUnplannedExpensesInRange(
    bounds.start,
    bounds.endExclusive,
  );
  final planned = await ref.watch(plannedIncludedAmountForPeriodProvider(period).future);
  return unplanned + planned;
});

final canCloseCurrentPeriodProvider = Provider<bool>((ref) {
  ref.watch(dbTickProvider);
  final period = ref.watch(selectedPeriodRefProvider);
  final (start, endExclusive) = ref.watch(periodBoundsProvider);
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final normalizedEndExclusive =
      DateTime(endExclusive.year, endExclusive.month, endExclusive.day);
  final statusAsync = ref.watch(periodStatusProvider(period));
  final isClosed = statusAsync.maybeWhen(
    data: (status) => status.closed,
    orElse: () => false,
  );
  final reachedEnd = !normalizedToday.isBefore(normalizedEndExclusive);
  return reachedEnd && !isClosed;
});

final payoutSuggestedTypeProvider = Provider<PayoutType>((ref) {
  final sel = ref.watch(selectedPeriodRefProvider);
  return sel.half == HalfPeriod.first ? PayoutType.salary : PayoutType.advance;
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
  final (a1, a2) = ref.watch(anchorDaysProvider);
  final sel = ref.watch(selectedPeriodRefProvider);
  final bounds = periodBoundsFor(sel, a1, a2);
  return (bounds.start, bounds.endExclusive);
});

@Deprecated('Use periodBoundsProvider')
final halfPeriodBoundsProvider = periodBoundsProvider;

/// Выплата, относящаяся к выбранному на Главной полупериоду (месяц+half)
final payoutForSelectedPeriodProvider = FutureProvider<Payout?>((ref) async {
  ref.watch(dbTickProvider);
  final (start, endEx) = ref.watch(periodBoundsProvider);
  final repo = ref.watch(payoutsRepoProvider);
  try {
    return await repo.findInRange(start, endEx);
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

String _ruMonthShort(int month) {
  const m = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  return m[(month - 1).clamp(0, 11)];
}

/// "сен 1–15" / "сен 15–30(31)" для выбранного месяца и половины периода.
final periodLabelProvider = Provider<String>((ref) {
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final period = ref.watch(selectedPeriodRefProvider);
  final monthShort = _ruMonthShort(period.month);
  final lastDayOfMonth = DateTime(period.year, period.month + 1, 0).day;

  int clampDay(int value) => math.max(1, math.min(value, lastDayOfMonth));

  final startAnchor =
      period.half == HalfPeriod.first ? anchor1 : anchor2;
  final endAnchor = period.half == HalfPeriod.first ? anchor2 : lastDayOfMonth;

  final startDay = clampDay(startAnchor);
  final endDay = math.max(startDay, clampDay(endAnchor));

  return '$monthShort $startDay–$endDay';
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
      const Duration(days: _earlyPayoutGraceDays),
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
    start: bounds.$1,
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

final spentTodayProvider = FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final today = ref.watch(todayDateProvider);
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final repository = ref.watch(transactionsRepoProvider);
  return repository.sumExpensesOnDateWithinPeriod(
    date: today,
    periodStart: DateUtils.dateOnly(bounds.start),
    periodEndExclusive: DateUtils.dateOnly(bounds.endExclusive),
  );
});

final dailyBudgetRemainingProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final limit = ref.watch(periodDailyLimitProvider);
  if (limit <= 0) {
    return 0;
  }
  final spent = await ref.watch(spentTodayProvider(period).future);
  final remaining = limit - spent;
  return remaining > 0 ? remaining : 0;
});

class TodayProgress {
  const TodayProgress._({
    required this.show,
    required this.spent,
    required this.limit,
  });

  final bool show;
  final int spent;
  final int limit;

  factory TodayProgress.hidden() => const TodayProgress._(
        show: false,
        spent: 0,
        limit: 0,
      );

  factory TodayProgress.visible({required int spent, required int limit}) {
    return TodayProgress._(
      show: true,
      spent: spent,
      limit: limit,
    );
  }
}

final todayProgressProvider = Provider<TodayProgress>((ref) {
  final period = ref.watch(selectedPeriodRefProvider);
  final active = ref.watch(isActivePeriodProvider);
  if (!active) {
    return TodayProgress.hidden();
  }

  final spent = ref.watch(spentTodayProvider(period)).maybeWhen(
        data: (value) => value,
        orElse: () => 0,
      );
  final limit = ref.watch(periodDailyLimitProvider);
  if (limit <= 0) {
    return TodayProgress.hidden();
  }

  return TodayProgress.visible(spent: spent, limit: limit);
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
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final repo = ref.watch(transactionsRepoProvider);
  return repo.sumActualExpenses(
    period: period,
    start: bounds.start,
    endExclusive: bounds.endExclusive,
  );
});

final periodBudgetRemainingProvider =
    FutureProvider.family<int, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final base = ref.watch(periodBudgetBaseProvider);
  final spent = await ref.watch(sumActualExpensesProvider(period).future);
  final value = base - spent;
  if (value <= 0) {
    return 0;
  }
  final maxCap = 1 << 31;
  return value > maxCap ? maxCap : value;
});

typedef RemainingBudgetInfo = ({int fromPeriodStart, int fromToday});

final remainingBudgetForPeriodProvider =
    FutureProvider.family<RemainingBudgetInfo, PeriodRef>((ref, period) async {
  ref.watch(dbTickProvider);
  final payout = await ref.watch(payoutForSelectedPeriodProvider.future);
  if (payout == null) {
    return (fromPeriodStart: 0, fromToday: 0);
  }
  final (anchor1, anchor2) = ref.watch(anchorDaysProvider);
  final bounds = period.bounds(anchor1, anchor2);
  final repository = ref.watch(transactionsRepoProvider);
  final periodStart = DateUtils.dateOnly(bounds.start);
  final periodEndExclusive = DateUtils.dateOnly(bounds.endExclusive);
  final spent = await repository.sumActualExpenses(
    period: period,
    start: periodStart,
    endExclusive: periodEndExclusive,
  );
  final today = DateUtils.dateOnly(DateTime.now());
  final truncatedToday = today.isBefore(periodStart)
      ? periodStart
      : today.isAfter(periodEndExclusive)
          ? periodEndExclusive
          : today;
  var spentBeforeToday = 0;
  if (truncatedToday.isAfter(periodStart)) {
    spentBeforeToday = await repository.sumActualExpenses(
      period: period,
      start: periodStart,
      endExclusive: truncatedToday,
    );
  }
  final remainingFromStart = payout.amountMinor - spent;
  final remainingFromToday = payout.amountMinor - spentBeforeToday;
  return (
    fromPeriodStart: remainingFromStart > 0 ? remainingFromStart : 0,
    fromToday: remainingFromToday > 0 ? remainingFromToday : 0,
  );
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
      periodEndExclusive: bounds.endExclusive,
      today: today,
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
