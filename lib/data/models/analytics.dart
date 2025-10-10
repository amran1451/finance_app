import 'package:meta/meta.dart';

@immutable
class AnalyticsPieSlice {
  const AnalyticsPieSlice({
    required this.label,
    required this.valueMinor,
    required this.operationCount,
    this.colorHex,
  });

  final String label;
  final int valueMinor;
  final int operationCount;
  final String? colorHex;
}

@immutable
class AnalyticsTimePoint {
  const AnalyticsTimePoint({
    required this.bucket,
    required this.valueMinor,
    required this.sortKey,
  });

  final String bucket;
  final int valueMinor;
  final String sortKey;
}

enum AnalyticsInterval {
  days,
  weekdays,
  months,
  halfPeriods,
}

enum AnalyticsBreakdown {
  plannedCriticality,
  plannedCategory,
  unplannedReason,
  unplannedCategory,
}
