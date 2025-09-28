import 'package:intl/intl.dart';

import 'formatting.dart';

String _normalizeTitle(String title) {
  final trimmed = title.trim();
  return trimmed.isEmpty ? '—' : trimmed;
}

String moneyFmt(int? amountMinor) {
  if (amountMinor == null) {
    return '—';
  }
  return formatCurrencyMinorPlain(amountMinor);
}

String necessityLabelOrDash(String? label) {
  if (label == null) {
    return '—';
  }
  final trimmed = label.trim();
  return trimmed.isEmpty ? '—' : trimmed;
}

String oneLinePlan(String title, int? amountMinor, String? necessityLabel) {
  final normalizedTitle = _normalizeTitle(title);
  final amountPart = moneyFmt(amountMinor);
  final amountWithCurrency = amountPart == '—' ? '— ₽' : '$amountPart ₽';
  final necessityPart = necessityLabelOrDash(necessityLabel);
  return '$normalizedTitle — $amountWithCurrency — $necessityPart';
}

String? compactPeriodLabel(
  DateTime? start,
  DateTime? endExclusive,
) {
  if (start == null || endExclusive == null) {
    return null;
  }
  if (!endExclusive.isAfter(start)) {
    return DateFormat.MMMd('ru_RU').format(start);
  }
  final endInclusive = endExclusive.subtract(const Duration(days: 1));
  final sameMonth = start.year == endInclusive.year && start.month == endInclusive.month;
  if (sameMonth) {
    final monthLabel = DateFormat.MMM('ru_RU').format(start);
    return '${start.day}–${endInclusive.day} $monthLabel';
  }
  final startLabel = DateFormat.MMMd('ru_RU').format(start);
  final endLabel = DateFormat.MMMd('ru_RU').format(endInclusive);
  return '$startLabel – $endLabel';
}
