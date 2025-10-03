const List<String> _ruShortMonths = [
  'янв',
  'фев',
  'мар',
  'апр',
  'май',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];

String ruMonthShort(int month) {
  final index = (month - 1).clamp(0, _ruShortMonths.length - 1);
  return _ruShortMonths[index];
}
