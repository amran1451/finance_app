import 'dart:math' as math;

enum HalfPeriod { first, second }

class PeriodRef {
  final int year;
  final int month;
  final HalfPeriod half;

  const PeriodRef({required this.year, required this.month, required this.half});

  PeriodRef copyWith({int? year, int? month, HalfPeriod? half}) {
    return PeriodRef(
      year: year ?? this.year,
      month: month ?? this.month,
      half: half ?? this.half,
    );
  }

  PeriodRef prevHalf() {
    if (half == HalfPeriod.second) {
      return copyWith(half: HalfPeriod.first);
    }
    final previousMonth = DateTime(year, month - 1, 1);
    return PeriodRef(
      year: previousMonth.year,
      month: previousMonth.month,
      half: HalfPeriod.second,
    );
  }

  PeriodRef nextHalf() {
    if (half == HalfPeriod.first) {
      return copyWith(half: HalfPeriod.second);
    }
    final nextMonth = DateTime(year, month + 1, 1);
    return PeriodRef(
      year: nextMonth.year,
      month: nextMonth.month,
      half: HalfPeriod.first,
    );
  }
}

DateTime normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

({DateTime start, DateTime endExclusive}) periodBoundsFor(
  PeriodRef period,
  int anchor1,
  int anchor2,
) {
  final ascending = anchor1 <= anchor2;
  final start = _anchorDate(
    period.year,
    period.month,
    period.half == HalfPeriod.first ? anchor1 : anchor2,
  );

  DateTime endExclusive;
  if (period.half == HalfPeriod.first) {
    endExclusive = ascending
        ? _anchorDate(period.year, period.month, anchor2)
        : _anchorDate(period.year, period.month + 1, anchor2);
  } else {
    endExclusive = ascending
        ? _anchorDate(period.year, period.month + 1, anchor1)
        : _anchorDate(period.year, period.month, anchor1);
  }

  if (!endExclusive.isAfter(start)) {
    endExclusive = start.add(const Duration(days: 1));
  }

  return (start: start, endExclusive: endExclusive);
}

PeriodRef periodRefForDate(DateTime date, int anchor1, int anchor2) {
  final normalized = normalizeDate(date);
  final ascending = anchor1 <= anchor2;
  if (!ascending) {
    // Нормализуем порядок якорей и пересчитываем.
    return periodRefForDate(normalized, anchor2, anchor1);
  }

  final firstStart = _anchorDate(normalized.year, normalized.month, anchor1);
  final secondStart = _anchorDate(normalized.year, normalized.month, anchor2);
  final secondEndExclusive = _anchorDate(normalized.year, normalized.month + 1, anchor1);

  if (normalized.isBefore(firstStart)) {
    final previousMonth = DateTime(normalized.year, normalized.month - 1, 1);
    return PeriodRef(year: previousMonth.year, month: previousMonth.month, half: HalfPeriod.second);
  }

  if (normalized.isBefore(secondStart)) {
    return PeriodRef(year: normalized.year, month: normalized.month, half: HalfPeriod.first);
  }

  if (normalized.isBefore(secondEndExclusive)) {
    return PeriodRef(year: normalized.year, month: normalized.month, half: HalfPeriod.second);
  }

  final nextMonth = DateTime(normalized.year, normalized.month + 1, 1);
  return PeriodRef(year: nextMonth.year, month: nextMonth.month, half: HalfPeriod.first);
}

DateTime nextAnchorDate(DateTime from, int anchor1, int anchor2) {
  final normalized = normalizeDate(from);
  final smaller = math.min(anchor1, anchor2);
  final larger = math.max(anchor1, anchor2);

  if (normalized.day < larger) {
    return _anchorDate(normalized.year, normalized.month, larger);
  }

  final nextMonth = DateTime(normalized.year, normalized.month + 1, 1);
  return _anchorDate(nextMonth.year, nextMonth.month, smaller);
}

DateTime previousAnchorDate(DateTime from, int anchor1, int anchor2) {
  final normalized = normalizeDate(from);
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
