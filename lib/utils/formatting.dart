import 'package:intl/intl.dart';

final NumberFormat currencyFormat = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);

final NumberFormat currencyIntegerFormat = NumberFormat.decimalPattern('ru');

String formatCurrency(double value) {
  return currencyFormat.format(value);
}

String formatCurrencyMinor(int value) {
  return formatCurrency(value / 100);
}

String formatCurrencyMinorToRubles(int value) {
  final rubles = value ~/ 100;
  return '${currencyIntegerFormat.format(rubles)}\u00A0₽';
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
