String ruDaysShort(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  final form = (mod10 == 1 && mod100 != 11)
      ? 'день'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
          ? 'дня'
          : 'дней';
  return '$n $form';
}
