String shortDowDay(DateTime d) {
  const dows = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  final wd = d.weekday == DateTime.sunday ? 6 : d.weekday - 1;
  return '${dows[wd]} ${d.day}';
}
