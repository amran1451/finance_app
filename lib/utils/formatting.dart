import 'package:intl/intl.dart';

final NumberFormat _rublesNumberFormat = NumberFormat.decimalPattern('ru_RU');

String _formatRubles(int rubles) {
  return '${_rublesNumberFormat.format(rubles)}\u00A0₽';
}

String _formatRublesPlain(int rubles) {
  return _rublesNumberFormat.format(rubles);
}

int _roundMinorToRubles(int value) {
  return (value / 100).round();
}

String formatCurrency(double value) {
  return _formatRubles(value.round());
}

String formatCurrencyMinor(int value) {
  final rubles = _roundMinorToRubles(value);
  return _formatRubles(rubles);
}

String formatCurrencyMinorToRubles(int value) {
  final rubles = value ~/ 100;
  return _formatRubles(rubles);
}

String formatCurrencyMinorPlain(int value) {
  final rubles = value ~/ 100;
  return _formatRublesPlain(rubles);
}

String formatCurrencyMinorNullable(int? value, {String placeholder = '—'}) {
  if (value == null) {
    return placeholder;
  }
  return formatCurrencyMinor(value);
}

String formatDate(DateTime date) {
  return DateFormat.yMMMMd('ru_RU').format(date);
}

String formatShortDate(DateTime date) {
  final now = DateTime.now();
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final normalizedNow = DateTime(now.year, now.month, now.day);
  final difference = normalizedDate.difference(normalizedNow).inDays;

  if (difference == 0) {
    return 'Сегодня';
  } else if (difference == 1) {
    return 'Завтра';
  }

  return DateFormat.E('ru_RU').format(date) + ', ' + DateFormat.MMMd('ru_RU').format(date);
}

String formatDayMonth(DateTime date) {
  return DateFormat.MMMd('ru_RU').format(date);
}
