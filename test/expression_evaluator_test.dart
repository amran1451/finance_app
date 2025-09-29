import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/state/entry_flow_providers.dart';

void main() {
  group('ExpressionEvaluator', () {
    test('applies multiplication before addition', () {
      final result = ExpressionEvaluator.tryEvaluate('1000+500*2');
      expect(result, 2000);
    });

    test('supports multiplication symbol variants', () {
      final result = ExpressionEvaluator.tryEvaluate('1000+500×2');
      expect(result, 2000);
    });

    test('applies division before subtraction', () {
      final result = ExpressionEvaluator.tryEvaluate('10-2/2');
      expect(result, 9);
    });
  });
}
