import 'package:flutter/material.dart';

import '../data/models/category.dart';

extension CategoryTypeDisplay on CategoryType {
  String get label {
    switch (this) {
      case CategoryType.income:
        return 'Доход';
      case CategoryType.expense:
        return 'Расход';
      case CategoryType.saving:
        return 'Сбережение';
    }
  }

  Color get color {
    switch (this) {
      case CategoryType.income:
        return Colors.green;
      case CategoryType.expense:
        return Colors.redAccent;
      case CategoryType.saving:
        return Colors.blueAccent;
    }
  }
}
