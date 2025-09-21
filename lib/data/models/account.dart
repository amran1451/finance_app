class Account {
  const Account({
    this.id,
    required this.name,
    required this.currency,
    required this.startBalanceMinor,
    this.isArchived = false,
  });

  final int? id;
  final String name;
  final String currency;
  final int startBalanceMinor;
  final bool isArchived;

  Account copyWith({
    int? id,
    String? name,
    String? currency,
    int? startBalanceMinor,
    bool? isArchived,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      startBalanceMinor: startBalanceMinor ?? this.startBalanceMinor,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      currency: map['currency'] as String? ?? '',
      startBalanceMinor: map['start_balance_minor'] as int? ?? 0,
      isArchived: (map['is_archived'] as int? ?? 0) != 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'currency': currency,
      'start_balance_minor': startBalanceMinor,
      'is_archived': isArchived ? 1 : 0,
    };
  }
}
