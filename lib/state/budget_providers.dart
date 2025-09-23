import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payout.dart';
import '../data/models/transaction_record.dart';
import '../data/repositories/transactions_repository.dart';
import 'app_providers.dart';
import 'db_refresh.dart';

typedef BudgetPeriodInfo = ({DateTime start, DateTime end, int days});

enum HalfPeriod { first, second }

// TODO: Persist selected period in Settings (ui.selected_period_ref).
class PeriodRef {
  final int year;
  final int month; // 1..12
  final HalfPeriod half;

  const PeriodRef({required this.year, required this.month, required this.half});

  PeriodRef copyWith({int? year, int? month, HalfPeriod? half}) =>
      PeriodRef(year: year ?? this.year, month: month ?? this.month, half: half ?? this.half);
}

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
  final half = (now.day <= a2) ? HalfPeriod.first : HalfPeriod.second;
  return PeriodRef(year: now.year, month: now.month, half: half);
});

/// (start, endExclusive) для выбранного периода (конкретный месяц)
final periodBoundsProvider = Provider<(DateTime start, DateTime endExclusive)>((ref) {
  final (a1, a2) = ref.watch(anchorDaysProvider);
  final sel = ref.watch(selectedPeriodRefProvider);
  // TODO: При смене месяца автоматически создавать новый период, прошлый считать архивным.
  // TODO: Дать экран выбора других месячных периодов (история).
  // TODO: Перенести планы в новый период по правилам (отдельная миграция).
  if (sel.half == HalfPeriod.first) {
    final start = DateTime(sel.year, sel.month, a1);
    final endEx = DateTime(sel.year, sel.month, a2); // [a1; a2)
    return (start, endEx);
  } else {
    final start = DateTime(sel.year, sel.month, a2);
    final endEx = DateTime(sel.year, sel.month + 1, a1); // [a2; nextMonth.a1)
    return (start, endEx);
  }
});

@Deprecated('Use periodBoundsProvider')
final halfPeriodBoundsProvider = periodBoundsProvider;

String _ruMonthShort(int month) {
  const m = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  return m[(month - 1).clamp(0, 11)];
}

/// "сен 1–15" / "сен 15–30/31"
final periodLabelProvider = Provider<String>((ref) {
  final (start, endEx) = ref.watch(periodBoundsProvider);
  final monthShort = _ruMonthShort(start.month);
  final startDay = start.day;
  final endDayInclusive = endEx.subtract(const Duration(days: 1)).day;
  return '$monthShort $startDay–$endDayInclusive';
});

extension PeriodNav on StateController<PeriodRef> {
  void goPrev(int anchor2) {
    final cur = state;
    if (cur.half == HalfPeriod.second) {
      state = cur.copyWith(half: HalfPeriod.first);
    } else {
      final prevMonth = DateTime(cur.year, cur.month - 1, anchor2);
      state = PeriodRef(year: prevMonth.year, month: prevMonth.month, half: HalfPeriod.second);
    }
  }

  void goNext(int anchor1, int anchor2) {
    final cur = state;
    if (cur.half == HalfPeriod.first) {
      state = cur.copyWith(half: HalfPeriod.second);
    } else {
      final nextMonth = DateTime(cur.year, cur.month + 1, anchor1);
      state = PeriodRef(year: nextMonth.year, month: nextMonth.month, half: HalfPeriod.first);
    }
  }
}

/// Удобный notifer с доступом к якорям
final periodNavProvider = Provider((ref) {
  final (a1, a2) = ref.watch(anchorDaysProvider);
  final ctrl = ref.read(selectedPeriodRefProvider.notifier);
  return (
    prev: () => ctrl.goPrev(a2),
    next: () => ctrl.goNext(a1, a2),
  );
});

final currentPayoutProvider = FutureProvider<Payout?>((ref) {
  ref.watch(dbTickProvider);
  final repository = ref.watch(payoutsRepoProvider);
  return repository.getLast();
});

final currentPeriodProvider = FutureProvider<BudgetPeriodInfo>((ref) async {
  final (anchor1, anchor2) = await ref.watch(anchorDaysFutureProvider.future);
  final payout = await ref.watch(currentPayoutProvider.future);
  final now = _normalizeDate(DateTime.now());
  final start = payout != null
      ? _normalizeDate(payout.date)
      : _previousAnchorDate(
          _nextAnchorDate(now, anchor1, anchor2),
          anchor1,
          anchor2,
        );

  var end = _nextAnchorDate(start, anchor1, anchor2);
  if (!end.isAfter(start)) {
    end = _nextAnchorDate(end.add(const Duration(days: 1)), anchor1, anchor2);
  }

  var days = end.difference(start).inDays;
  if (days <= 0) {
    days = 1;
  }

  return (start: start, end: end, days: days);
});

/// Принадлежит ли произвольная дата активному периоду (currentPeriodProvider)
final isInCurrentPeriodProvider = Provider.family<bool, DateTime>((ref, date) {
  final period = ref.watch(currentPeriodProvider).value;
  if (period == null) {
    return false;
  }
  final d0 = DateTime(date.year, date.month, date.day);
  final start0 = DateTime(period.start.year, period.start.month, period.start.day);
  final end0 = DateTime(period.end.year, period.end.month, period.end.day);
  return !d0.isBefore(start0) && d0.isBefore(end0);
});

/// Количество дней до конца активного периода (>=0).
/// Период берём из currentPeriodProvider: [start; endExclusive).
final daysToPeriodEndProvider = Provider<int?>((ref) {
  final period = ref.watch(currentPeriodProvider).value;
  if (period == null) {
    return null;
  }

  final now = DateTime.now();
  final today0 = DateTime(now.year, now.month, now.day);
  final end0 = DateTime(period.end.year, period.end.month, period.end.day);
  final diff = end0.difference(today0).inDays;
  return diff < 0 ? 0 : diff;
});

final dailyLimitProvider = FutureProvider<int?>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(settingsRepoProvider);
  return repository.getDailyLimitMinor();
});

/// Сколько внеплановых расходов сегодня (в пределах активного периода)
final todayUnplannedExpensesMinorProvider = FutureProvider<int>((ref) async {
  ref.watch(dbTickProvider);
  final repo = ref.watch(transactionsRepoProvider);
  final period = await ref.watch(currentPeriodProvider.future);

  final today = DateTime.now();
  final dayStart = DateTime(today.year, today.month, today.day);
  final periodStart =
      DateTime(period.start.year, period.start.month, period.start.day);
  final periodEnd = DateTime(period.end.year, period.end.month, period.end.day);
  final within = !dayStart.isBefore(periodStart) && dayStart.isBefore(periodEnd);
  if (!within) {
    return 0;
  }

  return repo.sumUnplannedExpensesOnDate(dayStart);
});

/// Остаток на день = дневной лимит - расходы сегодня
final leftTodayMinorProvider = FutureProvider<int>((ref) async {
  ref.watch(dbTickProvider);
  final dailyLimit = await ref.watch(dailyLimitProvider.future) ?? 0;
  if (dailyLimit <= 0) {
    return 0;
  }
  final spentToday = await ref.watch(todayUnplannedExpensesMinorProvider.future);
  final left = dailyLimit - spentToday;
  return left > 0 ? left : 0;
});

/// Остаток в бюджете на оставшуюся часть периода
final leftInPeriodMinorProvider = FutureProvider<int>((ref) async {
  ref.watch(dbTickProvider);
  final period = await ref.watch(currentPeriodProvider.future);
  final dailyLimit = await ref.watch(dailyLimitProvider.future) ?? 0;
  if (dailyLimit <= 0) {
    return 0;
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final periodStart =
      DateTime(period.start.year, period.start.month, period.start.day);
  final periodEnd = DateTime(period.end.year, period.end.month, period.end.day);

  if (today.isBefore(periodStart) || !today.isBefore(periodEnd)) {
    return 0;
  }

  final rawRemainingDays = periodEnd.difference(today).inDays;
  var remainingDays = rawRemainingDays;
  if (remainingDays < 0) {
    remainingDays = 0;
  } else if (remainingDays > 365) {
    remainingDays = 365;
  }

  final remainingBudget = remainingDays * dailyLimit;
  if (remainingBudget <= 0) {
    return 0;
  }

  final spentToday = await ref.watch(todayUnplannedExpensesMinorProvider.future);
  final left = remainingBudget - spentToday;
  return left > 0 ? left : 0;
});

final periodBudgetMinorProvider = FutureProvider<int>((ref) async {
  final dailyLimit = await ref.watch(dailyLimitProvider.future) ?? 0;
  if (dailyLimit <= 0) {
    return 0;
  }
  final period = await ref.watch(currentPeriodProvider.future);
  final today = _normalizeDate(DateTime.now());
  final rawRemaining = period.end.difference(today).inDays;
  final remainingDays = _clampRemainingDays(rawRemaining, period.days);
  if (remainingDays <= 0) {
    return 0;
  }
  return dailyLimit * remainingDays;
});

final plannedPoolMinorProvider = FutureProvider<int>((ref) async {
  final payout = await ref.watch(currentPayoutProvider.future);
  if (payout == null) {
    return 0;
  }
  final periodBudget = await ref.watch(periodBudgetMinorProvider.future);
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
  );
});

final dailyLimitManagerProvider = Provider<DailyLimitManager>((ref) {
  return DailyLimitManager(ref);
});

class DailyLimitManager {
  DailyLimitManager(this._ref);

  final Ref _ref;

  Future<String?> saveDailyLimitMinor(int? value) async {
    if (value != null) {
      final payout = await _ref.read(currentPayoutProvider.future);
      if (payout != null) {
        final period = await _ref.read(currentPeriodProvider.future);
        final today = _normalizeDate(DateTime.now());
        final rawRemaining = period.end.difference(today).inDays;
        var remainingDays = _clampRemainingDays(rawRemaining, period.days);
        if (remainingDays <= 0) {
          remainingDays = 1;
        }
        final maxDaily = payout.amountMinor ~/ remainingDays;
        if (value > maxDaily) {
          return 'Лимит не может превышать $maxDaily';
        }
      }
    }

    final repository = _ref.read(settingsRepoProvider);
    await repository.setDailyLimitMinor(value);
    final notifier = _ref.read(dbTickProvider.notifier);
    notifier.state = notifier.state + 1;
    return null;
  }
}

final anchorDaysManagerProvider = Provider<AnchorDaysManager>((ref) {
  return AnchorDaysManager(ref);
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

int _normalizeAnchorDay(int value) {
  if (value < 1) {
    return 1;
  }
  if (value > 31) {
    return 31;
  }
  return value;
}

DateTime _normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime _nextAnchorDate(DateTime from, int anchor1, int anchor2) {
  final normalized = _normalizeDate(from);
  final smaller = math.min(anchor1, anchor2);
  final larger = math.max(anchor1, anchor2);

  if (normalized.day < larger) {
    return _anchorDate(normalized.year, normalized.month, larger);
  }

  final nextMonth = DateTime(normalized.year, normalized.month + 1, 1);
  return _anchorDate(nextMonth.year, nextMonth.month, smaller);
}

DateTime _previousAnchorDate(DateTime from, int anchor1, int anchor2) {
  final normalized = _normalizeDate(from);
  final smaller = math.min(anchor1, anchor2);
  final larger = math.max(anchor1, anchor2);

  if (normalized.day <= smaller) {
    final previousMonth = DateTime(normalized.year, normalized.month - 1, 1);
    return _anchorDate(previousMonth.year, previousMonth.month, larger);
  }

  if (normalized.day <= larger) {
    return _anchorDate(normalized.year, normalized.month, smaller);
  }

  return _anchorDate(normalized.year, normalized.month, larger);
}

DateTime _anchorDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final safeDay = day.clamp(1, lastDay);
  return DateTime(year, month, safeDay);
}

int _clampRemainingDays(int difference, int periodDays) {
  if (difference <= 0) {
    return 0;
  }
  if (difference >= periodDays) {
    return periodDays;
  }
  return difference;
}
