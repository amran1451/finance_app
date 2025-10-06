import '../data/models/payout.dart';
import 'period_utils.dart';

/// Количество дней, на которое можно сдвинуться назад при учёте ранней выплаты.
const int kEarlyPayoutGraceDays = 5;

/// Допустимый тип выплаты для указанного полупериода.
PayoutType allowedPayoutTypeForHalf(HalfPeriod half) {
  switch (half) {
    case HalfPeriod.first:
      return PayoutType.advance;
    case HalfPeriod.second:
      return PayoutType.salary;
  }
}
