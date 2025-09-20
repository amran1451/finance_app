import 'package:flutter/material.dart';

enum OperationType {
  income,
  expense,
  savings,
}

extension OperationTypeX on OperationType {
  String get label {
    switch (this) {
      case OperationType.income:
        return 'Доход';
      case OperationType.expense:
        return 'Расход';
      case OperationType.savings:
        return 'Сбережение';
    }
  }

  Color get color {
    switch (this) {
      case OperationType.income:
        return Colors.green;
      case OperationType.expense:
        return Colors.redAccent;
      case OperationType.savings:
        return Colors.blueAccent;
    }
  }
}

class BudgetPeriod {
  BudgetPeriod({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    return !normalized.isBefore(normalizedStart) && !normalized.isAfter(normalizedEnd);
  }
}

class Account {
  Account({
    required this.id,
    required this.name,
    required this.balance,
    required this.color,
  });

  final String id;
  final String name;
  final double balance;
  final Color color;
}

class Category {
  Category({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    this.subcategory,
  });

  final String id;
  final String name;
  final OperationType type;
  final IconData icon;
  final String? subcategory;
}

class Operation {
  Operation({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.note,
    this.accountId,
    this.plannedId,
  });

  final String id;
  final double amount;
  final OperationType type;
  final Category category;
  final DateTime date;
  final String? note;
  final String? accountId;
  final String? plannedId;
}
