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
