import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/utils/period_utils.dart';

void main() {
  group('clampDateToPeriod', () {
    final start = DateTime(2024, 5, 10);
    final endExclusive = DateTime(2024, 5, 15);

    test('keeps value within inclusive start and exclusive end', () {
      expect(
        clampDateToPeriod(DateTime(2024, 5, 10), start, endExclusive),
        DateTime(2024, 5, 10),
      );
      expect(
        clampDateToPeriod(DateTime(2024, 5, 14), start, endExclusive),
        DateTime(2024, 5, 14),
      );
    });

    test('clamps values before start to start', () {
      expect(
        clampDateToPeriod(DateTime(2024, 5, 9), start, endExclusive),
        DateTime(2024, 5, 10),
      );
    });

    test('clamps values on or after end exclusive to last allowed day', () {
      expect(
        clampDateToPeriod(DateTime(2024, 5, 15), start, endExclusive),
        DateTime(2024, 5, 14),
      );
      expect(
        clampDateToPeriod(DateTime(2024, 5, 16), start, endExclusive),
        DateTime(2024, 5, 14),
      );
    });

    test('handles degenerate periods by returning start', () {
      final sameDayEnd = DateTime(2024, 5, 10);
      expect(
        clampDateToPeriod(DateTime(2024, 5, 12), start, sameDayEnd),
        DateTime(2024, 5, 10),
      );
    });

    test('normalizes time components', () {
      final withTime = DateTime(2024, 5, 12, 23, 59);
      expect(
        clampDateToPeriod(withTime, start, endExclusive),
        DateTime(2024, 5, 12),
      );
    });
  });
}
