import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/payout.dart';
import 'app_providers.dart';

typedef BudgetPeriodInfo = ({DateTime start, DateTime end, int days});

final anchorDaysProvider = FutureProvider<(int, int)>((ref) async {
  final repository = ref.watch(settingsRepoProvider);
  final day1 = await repository.getAnchorDay1();
  final day2 = await repository.getAnchorDay2();
  final anchors = [day1, day2]..sort();
  final first = _normalizeAnchorDay(anchors[0]);
  final second = _normalizeAnchorDay(anchors[1]);
  return (first, second);
});

final currentPayoutProvider = FutureProvider<Payout?>((ref) {
  final repository = ref.watch(payoutsRepoProvider);
  return repository.getLast();
});

final currentPeriodProvider = FutureProvider<BudgetPeriodInfo>((ref) async {
  final (anchor1, anchor2) = await ref.watch(anchorDaysProvider.future);
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

final dailyLimitProvider = FutureProvider<int?>((ref) async {
  final repository = ref.watch(settingsRepoProvider);
  return repository.getDailyLimitMinor();
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
    _refreshPeriod();
  }

  Future<void> saveAnchorDay2(int value) async {
    final repository = _ref.read(settingsRepoProvider);
    await repository.setAnchorDay2(value);
    _refreshPeriod();
  }

  Future<void> saveAnchorDays(int first, int second) async {
    final repository = _ref.read(settingsRepoProvider);
    await repository.setAnchorDay1(first);
    await repository.setAnchorDay2(second);
    _refreshPeriod();
  }

  void _refreshPeriod() {
    _ref.invalidate(anchorDaysProvider);
    _ref.invalidate(currentPeriodProvider);
    _ref.invalidate(periodBudgetMinorProvider);
    _ref.invalidate(plannedPoolMinorProvider);
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
