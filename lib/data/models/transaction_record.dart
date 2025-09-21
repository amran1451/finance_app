import 'dart:convert';

enum TransactionType { income, expense, saving }

class TransactionRecord {
  const TransactionRecord({
    this.id,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amountMinor,
    required this.date,
    this.time,
    this.note,
    this.isPlanned = false,
    this.includedInPeriod = true,
    this.tags = const <String>[],
  });

  final int? id;
  final int accountId;
  final int categoryId;
  final TransactionType type;
  final int amountMinor;
  final DateTime date;
  final String? time;
  final String? note;
  final bool isPlanned;
  final bool includedInPeriod;
  final List<String> tags;

  TransactionRecord copyWith({
    int? id,
    int? accountId,
    int? categoryId,
    TransactionType? type,
    int? amountMinor,
    DateTime? date,
    String? time,
    String? note,
    bool? isPlanned,
    bool? includedInPeriod,
    List<String>? tags,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      date: date ?? this.date,
      time: time ?? this.time,
      note: note ?? this.note,
      isPlanned: isPlanned ?? this.isPlanned,
      includedInPeriod: includedInPeriod ?? this.includedInPeriod,
      tags: tags ?? this.tags,
    );
  }

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    return TransactionRecord(
      id: map['id'] as int?,
      accountId: map['account_id'] as int? ?? 0,
      categoryId: map['category_id'] as int? ?? 0,
      type: _typeFromString(map['type'] as String?),
      amountMinor: map['amount_minor'] as int? ?? 0,
      date: _parseDate(map['date'] as String?),
      time: map['time'] as String?,
      note: map['note'] as String?,
      isPlanned: (map['is_planned'] as int? ?? 0) != 0,
      includedInPeriod: (map['included_in_period'] as int? ?? 0) != 0,
      tags: _decodeTags(map['tags'] as String?),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'type': _typeToString(type),
      'amount_minor': amountMinor,
      'date': _formatDate(date),
      'time': time,
      'note': note,
      'is_planned': isPlanned ? 1 : 0,
      'included_in_period': includedInPeriod ? 1 : 0,
      'tags': tags.isEmpty ? null : jsonEncode(tags),
    };
  }

  static TransactionType _typeFromString(String? raw) {
    switch (raw) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      case 'saving':
        return TransactionType.saving;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown transaction type');
    }
  }

  static String _typeToString(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
      case TransactionType.saving:
        return 'saving';
    }
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  static DateTime _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime.parse(raw);
  }

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
