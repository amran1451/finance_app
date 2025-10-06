import 'package:meta/meta.dart';

import '../../utils/period_utils.dart';

@immutable
class PlanMaster {
  const PlanMaster({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    this.criticalityId,
    this.note,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int amount;
  final int categoryId;
  final int? criticalityId;
  final String? note;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlanMaster copyWith({
    String? name,
    int? amount,
    int? categoryId,
    Object? criticalityId = _sentinel,
    Object? note = _sentinel,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlanMaster(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      criticalityId: criticalityId == _sentinel
          ? this.criticalityId
          : criticalityId as int?,
      note: note == _sentinel ? this.note : note as String?,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        amount,
        categoryId,
        criticalityId,
        note,
        isActive,
        createdAt,
        updatedAt,
      );

  @override
  bool operator ==(Object other) {
    return other is PlanMaster &&
        other.id == id &&
        other.name == name &&
        other.amount == amount &&
        other.categoryId == categoryId &&
        other.criticalityId == criticalityId &&
        other.note == note &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  static const Object _sentinel = Object();
}

@immutable
class PlanInstance {
  const PlanInstance({
    required this.id,
    required this.masterId,
    required this.period,
    this.overrideAmount,
    this.accountId,
    required this.includedInPeriod,
    this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int masterId;
  final PeriodRef period;
  final int? overrideAmount;
  final int? accountId;
  final bool includedInPeriod;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  int resolveAmount(PlanMaster master) => overrideAmount ?? master.amount;

  PlanInstance copyWith({
    int? masterId,
    PeriodRef? period,
    Object? overrideAmount = _sentinel,
    Object? accountId = _sentinel,
    bool? includedInPeriod,
    Object? scheduledAt = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlanInstance(
      id: id,
      masterId: masterId ?? this.masterId,
      period: period ?? this.period,
      overrideAmount: overrideAmount == _sentinel
          ? this.overrideAmount
          : overrideAmount as int?,
      accountId: accountId == _sentinel ? this.accountId : accountId as int?,
      includedInPeriod: includedInPeriod ?? this.includedInPeriod,
      scheduledAt:
          scheduledAt == _sentinel ? this.scheduledAt : scheduledAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  int get hashCode => Object.hash(
        id,
        masterId,
        period,
        overrideAmount,
        accountId,
        includedInPeriod,
        scheduledAt,
        createdAt,
        updatedAt,
      );

  @override
  bool operator ==(Object other) {
    return other is PlanInstance &&
        other.id == id &&
        other.masterId == masterId &&
        other.period == period &&
        other.overrideAmount == overrideAmount &&
        other.accountId == accountId &&
        other.includedInPeriod == includedInPeriod &&
        other.scheduledAt == scheduledAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  static const Object _sentinel = Object();
}
