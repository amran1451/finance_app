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
    this.plannedId,
    this.planInstanceId,
    this.isPlanned = false,
    this.includedInPeriod = true,
    this.tags = const <String>[],
    this.criticality = 0,
    this.necessityId,
    this.necessityLabel,
    this.reasonId,
    this.reasonLabel,
    this.source,
    this.payoutPeriodId,
    this.periodId,
    this.deleted = false,
  });

  final int? id;
  final int accountId;
  final int categoryId;
  final TransactionType type;
  final int amountMinor;
  final DateTime date;
  final String? time;
  final String? note;
  final int? plannedId;
  final int? planInstanceId;
  final bool isPlanned;
  final bool includedInPeriod;
  final List<String> tags;
  final int criticality;
  final int? necessityId;
  final String? necessityLabel;
  final int? reasonId;
  final String? reasonLabel;
  final String? source;
  final String? payoutPeriodId;
  final String? periodId;
  final bool deleted;

  TransactionRecord copyWith({
    int? id,
    int? accountId,
    int? categoryId,
    TransactionType? type,
    int? amountMinor,
    DateTime? date,
    String? time,
    String? note,
    Object? plannedId = _unset,
    Object? planInstanceId = _unset,
    bool? isPlanned,
    bool? includedInPeriod,
    List<String>? tags,
    int? criticality,
    Object? necessityId = _unset,
    Object? necessityLabel = _unset,
    Object? reasonId = _unset,
    Object? reasonLabel = _unset,
    Object? source = _unset,
    Object? payoutPeriodId = _unset,
    Object? periodId = _unset,
    bool? deleted,
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
      plannedId:
          plannedId == _unset ? this.plannedId : plannedId as int?,
      planInstanceId: planInstanceId == _unset
          ? this.planInstanceId
          : planInstanceId as int?,
      isPlanned: isPlanned ?? this.isPlanned,
      includedInPeriod: includedInPeriod ?? this.includedInPeriod,
      tags: tags ?? this.tags,
      criticality: criticality ?? this.criticality,
      necessityId: necessityId == _unset
          ? this.necessityId
          : necessityId as int?,
      necessityLabel: necessityLabel == _unset
          ? this.necessityLabel
          : necessityLabel as String?,
      reasonId:
          reasonId == _unset ? this.reasonId : reasonId as int?,
      reasonLabel: reasonLabel == _unset
          ? this.reasonLabel
          : reasonLabel as String?,
      source: source == _unset ? this.source : source as String?,
      payoutPeriodId: payoutPeriodId == _unset
          ? this.payoutPeriodId
          : payoutPeriodId as String?,
      periodId: periodId == _unset ? this.periodId : periodId as String?,
      deleted: deleted ?? this.deleted,
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
      plannedId: map['planned_id'] as int?,
      planInstanceId: map['plan_instance_id'] as int?,
      isPlanned: (map['is_planned'] as int? ?? 0) != 0,
      includedInPeriod: (map['included_in_period'] as int? ?? 0) != 0,
      tags: _decodeTags(map['tags'] as String?),
      criticality: map['criticality'] as int? ?? 0,
      necessityId: map['necessity_id'] as int?,
      necessityLabel: map['necessity_label'] as String?,
      reasonId: map['reason_id'] as int?,
      reasonLabel: map['reason_label'] as String?,
      source: map['source'] as String?,
      payoutPeriodId: map['payout_period_id'] as String?,
      periodId: map['period_id'] as String?,
      deleted: (map['deleted'] as int? ?? 0) != 0,
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
      'planned_id': plannedId,
      'plan_instance_id': planInstanceId,
      'is_planned': isPlanned ? 1 : 0,
      'included_in_period': includedInPeriod ? 1 : 0,
      'tags': tags.isEmpty ? null : jsonEncode(tags),
      'criticality': criticality,
      'necessity_id': necessityId,
      'necessity_label': necessityLabel,
      'reason_id': reasonId,
      'reason_label': reasonLabel,
      'source': source,
      'payout_period_id': payoutPeriodId,
      'period_id': periodId,
      'deleted': deleted ? 1 : 0,
    };
  }

  static const Object _unset = Object();

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
