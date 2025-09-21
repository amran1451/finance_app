enum PayoutType { advance, salary }

class Payout {
  const Payout({
    this.id,
    required this.type,
    required this.date,
    required this.amountMinor,
    this.accountId,
  });

  final int? id;
  final PayoutType type;
  final DateTime date;
  final int amountMinor;
  final int? accountId;

  Payout copyWith({
    int? id,
    PayoutType? type,
    DateTime? date,
    int? amountMinor,
    int? accountId,
  }) {
    return Payout(
      id: id ?? this.id,
      type: type ?? this.type,
      date: date ?? this.date,
      amountMinor: amountMinor ?? this.amountMinor,
      accountId: accountId ?? this.accountId,
    );
  }

  factory Payout.fromMap(Map<String, Object?> map) {
    return Payout(
      id: map['id'] as int?,
      type: _typeFromString(map['type'] as String?),
      date: _parseDate(map['date'] as String?),
      amountMinor: map['amount_minor'] as int? ?? 0,
      accountId: map['account_id'] as int?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': _typeToString(type),
      'date': _formatDate(date),
      'amount_minor': amountMinor,
      'account_id': accountId,
    };
  }

  static PayoutType _typeFromString(String? raw) {
    switch (raw) {
      case 'advance':
        return PayoutType.advance;
      case 'salary':
        return PayoutType.salary;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown payout type');
    }
  }

  static String _typeToString(PayoutType type) {
    switch (type) {
      case PayoutType.advance:
        return 'advance';
      case PayoutType.salary:
        return 'salary';
    }
  }

  static DateTime _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime.parse(raw);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}
