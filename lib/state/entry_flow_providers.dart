import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart';
import '../data/models/transaction_record.dart';

const bool kReturnToOperationsAfterSave = true;

const Object _entryFlowUnset = Object();

enum OperationKind { expense, income, saving }

OperationKind operationKindFromType(CategoryType type) {
  switch (type) {
    case CategoryType.expense:
      return OperationKind.expense;
    case CategoryType.income:
      return OperationKind.income;
    case CategoryType.saving:
      return OperationKind.saving;
  }
}

CategoryType operationTypeFromKind(OperationKind kind) {
  switch (kind) {
    case OperationKind.expense:
      return CategoryType.expense;
    case OperationKind.income:
      return CategoryType.income;
    case OperationKind.saving:
      return CategoryType.saving;
  }
}

final lastEntryKindProvider = StateProvider<OperationKind?>((_) => null);

class EntryFlowState {
  EntryFlowState({
    this.expression = '',
    this.result,
    this.previewResult,
    this.type = CategoryType.expense,
    this.category,
    DateTime? selectedDate,
    this.note = '',
    this.attachToPlanned = false,
    this.necessityCriticality = 0,
    this.necessityId,
    this.necessityLabel,
    this.necessityResolved = false,
    this.accountId,
    this.editingRecord,
    this.editingCounterpart,
    this.reasonId,
    this.reasonLabel,
    this.includeInPeriod = false,
  }) : selectedDate = selectedDate ?? _today;

  final String expression;
  final double? result;
  final double? previewResult;
  final CategoryType type;
  final Category? category;
  final DateTime selectedDate;
  final String note;
  final bool attachToPlanned;
  final int necessityCriticality;
  final int? necessityId;
  final String? necessityLabel;
  final bool necessityResolved;
  final int? accountId;
  final TransactionRecord? editingRecord;
  final TransactionRecord? editingCounterpart;
  final int? reasonId;
  final String? reasonLabel;
  final bool includeInPeriod;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  double get amount => result ?? 0;

  bool get canProceedToCategory => result != null && result! > 0;

  bool get canSave => canProceedToCategory && category != null;

  EntryFlowState copyWith({
    Object? expression = _entryFlowUnset,
    CategoryType? type,
    Object? category = _entryFlowUnset,
    DateTime? selectedDate,
    String? note,
    bool? attachToPlanned,
    Object? result = _entryFlowUnset,
    Object? previewResult = _entryFlowUnset,
    Object? necessityCriticality = _entryFlowUnset,
    Object? necessityId = _entryFlowUnset,
    Object? necessityLabel = _entryFlowUnset,
    Object? necessityResolved = _entryFlowUnset,
    Object? accountId = _entryFlowUnset,
    Object? editingRecord = _entryFlowUnset,
    Object? editingCounterpart = _entryFlowUnset,
    Object? reasonId = _entryFlowUnset,
    Object? reasonLabel = _entryFlowUnset,
    Object? includeInPeriod = _entryFlowUnset,
  }) {
    return EntryFlowState(
      expression:
          expression == _entryFlowUnset ? this.expression : expression as String,
      type: type ?? this.type,
      category:
          category == _entryFlowUnset ? this.category : category as Category?,
      selectedDate: selectedDate ?? this.selectedDate,
      note: note ?? this.note,
      attachToPlanned: attachToPlanned ?? this.attachToPlanned,
      result: result == _entryFlowUnset ? this.result : result as double?,
      previewResult: previewResult == _entryFlowUnset
          ? this.previewResult
          : previewResult as double?,
      necessityCriticality: necessityCriticality == _entryFlowUnset
          ? this.necessityCriticality
          : necessityCriticality as int,
      necessityId:
          necessityId == _entryFlowUnset ? this.necessityId : necessityId as int?,
      necessityLabel: necessityLabel == _entryFlowUnset
          ? this.necessityLabel
          : necessityLabel as String?,
      necessityResolved: necessityResolved == _entryFlowUnset
          ? this.necessityResolved
          : necessityResolved as bool,
      accountId:
          accountId == _entryFlowUnset ? this.accountId : accountId as int?,
      editingRecord: editingRecord == _entryFlowUnset
          ? this.editingRecord
          : editingRecord as TransactionRecord?,
      editingCounterpart: editingCounterpart == _entryFlowUnset
          ? this.editingCounterpart
          : editingCounterpart as TransactionRecord?,
      reasonId:
          reasonId == _entryFlowUnset ? this.reasonId : reasonId as int?,
      reasonLabel: reasonLabel == _entryFlowUnset
          ? this.reasonLabel
          : reasonLabel as String?,
      includeInPeriod: includeInPeriod == _entryFlowUnset
          ? this.includeInPeriod
          : includeInPeriod as bool,
    );
  }

  EntryFlowState clearCategory() {
    return copyWith(category: null);
  }
}

class EntryFlowController extends StateNotifier<EntryFlowState> {
  EntryFlowController() : super(EntryFlowState());

  void startNew({
    CategoryType type = CategoryType.expense,
    bool includeInPeriod = false,
  }) {
    state = EntryFlowState(
      type: type,
      includeInPeriod: includeInPeriod,
    );
  }

  void appendDigit(String digit) {
    final expression = state.expression;
    final segment = _currentNumberSegment(expression);

    if (expression == '0') {
      _updateExpression(digit);
      return;
    }

    if (segment == '0' && expression.isNotEmpty) {
      _updateExpression(
        expression.substring(0, expression.length - 1) + digit,
      );
      return;
    }

    if (segment == '-0' && expression.length >= 2) {
      _updateExpression(
        expression.substring(0, expression.length - 1) + digit,
      );
      return;
    }

    _updateExpression(expression + digit);
  }

  void appendDecimal() {
    final expression = state.expression;
    final segment = _currentNumberSegment(expression);

    if (segment.contains('.')) {
      return;
    }

    if (segment.isEmpty) {
      if (expression.isEmpty) {
        _updateExpression('0.');
      } else {
        _updateExpression('${expression}0.');
      }
      return;
    }

    if (segment == '-') {
      _updateExpression('${expression}0.');
      return;
    }

    _updateExpression('$expression.');
  }

  void backspace() {
    if (state.expression.isEmpty) {
      return;
    }
    final updated = state.expression.substring(0, state.expression.length - 1);
    if (updated.isEmpty) {
      state = state.copyWith(
        expression: '',
        previewResult: null,
        result: null,
      );
      return;
    }

    _updateExpression(updated);
  }

  void appendOperator(String operator) {
    final expression = state.expression;
    if (expression.isEmpty) {
      if (operator == '-') {
        _updateExpression('-');
      }
      return;
    }

    final lastChar = expression[expression.length - 1];
    if (_isOperator(lastChar) || lastChar == '.') {
      return;
    }

    _updateExpression('$expression$operator');
  }

  void clear() {
    state = state.copyWith(
      expression: '',
      previewResult: null,
      result: null,
    );
  }

  void addQuickAmount(double value) {
    final base = state.result ??
        state.previewResult ??
        ExpressionEvaluator.tryEvaluate(state.expression) ??
        0;
    final newAmount = base + value;
    final normalized = _formatExpressionValue(newAmount);

    state = state.copyWith(
      expression: normalized,
      result: newAmount,
      previewResult: newAmount,
    );
  }

  bool tryFinalizeExpression() {
    final expression = state.expression;
    if (expression.isEmpty) {
      return false;
    }

    final evaluation = ExpressionEvaluator.tryEvaluate(expression);
    if (evaluation == null) {
      return false;
    }

    final normalized = _formatExpressionValue(evaluation);
    state = state.copyWith(
      expression: normalized,
      result: evaluation,
      previewResult: evaluation,
    );
    return true;
  }

  void evaluateExpression() {
    tryFinalizeExpression();
  }

  void setType(CategoryType type) {
    if (type == state.type) {
      return;
    }
    state = EntryFlowState(
      type: type,
      expression: state.expression,
      result: state.result,
      previewResult: state.previewResult,
      selectedDate: state.selectedDate,
      note: state.note,
      attachToPlanned: state.attachToPlanned,
      necessityCriticality: state.necessityCriticality,
      necessityId: state.necessityId,
      necessityLabel: state.necessityLabel,
      necessityResolved: state.necessityResolved,
      includeInPeriod: state.includeInPeriod,
    );
  }

  void setCategory(Category category) {
    state = state.copyWith(category: category);
  }

  void setDate(DateTime date) {
    state = state.copyWith(selectedDate: DateTime(date.year, date.month, date.day));
  }

  void setAccount(int? accountId) {
    state = state.copyWith(accountId: accountId);
  }

  void setAmountMinor(int amountMinor) {
    final amount = amountMinor / 100;
    state = state.copyWith(
      expression: _formatExpressionValue(amount),
      result: amount,
      previewResult: amount,
    );
  }

  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  void setAttachToPlanned(bool value) {
    state = state.copyWith(attachToPlanned: value);
  }

  void setReason({int? id, String? label}) {
    state = state.copyWith(
      reasonId: id,
      reasonLabel: label,
    );
  }

  void setNecessity({
    int? id,
    String? label,
    int? criticality,
    bool? resolved,
  }) {
    state = state.copyWith(
      necessityId: id,
      necessityLabel: label,
      necessityCriticality:
          criticality ?? state.necessityCriticality,
      necessityResolved: resolved ?? true,
    );
  }

  void loadFromTransaction({
    required TransactionRecord record,
    required Category category,
    TransactionRecord? savingCounterpart,
  }) {
    final amount = record.amountMinor / 100;
    final normalizedExpression = _formatExpressionValue(amount);
    state = EntryFlowState(
      expression: normalizedExpression,
      result: amount,
      previewResult: amount,
      type: category.type,
      category: category,
      selectedDate: DateTime(record.date.year, record.date.month, record.date.day),
      note: record.note ?? '',
      attachToPlanned: record.isPlanned,
      necessityCriticality: record.criticality,
      necessityId: record.necessityId,
      necessityLabel: record.necessityLabel,
      necessityResolved:
          record.necessityId != null || record.necessityLabel != null,
      accountId: record.accountId,
      editingRecord: record,
      editingCounterpart: savingCounterpart,
      reasonId: record.reasonId,
      reasonLabel: record.reasonLabel,
      includeInPeriod: record.includedInPeriod,
    );
  }

  void reset() {
    state = EntryFlowState();
  }

  void _updateExpression(String expression) {
    final preview = ExpressionEvaluator.tryEvaluate(expression);
    state = state.copyWith(
      expression: expression,
      previewResult: preview,
      result: null,
    );
  }
}

extension EntryFlowQuickReset on EntryFlowController {
  void resetForQuickAdd(OperationKind kind) {
    state = EntryFlowState(
      type: operationTypeFromKind(kind),
      includeInPeriod: true,
    );
  }
}

bool _isOperator(String value) {
  return value == '+' || value == '-' || value == '*' || value == '/';
}

String _currentNumberSegment(String expression) {
  if (expression.isEmpty) {
    return '';
  }

  final index = _lastOperatorIndex(expression);
  if (index == -1) {
    return expression;
  }

  return expression.substring(index + 1);
}

int _lastOperatorIndex(String expression) {
  for (var i = expression.length - 1; i >= 0; i--) {
    final char = expression[i];
    if (_isOperator(char)) {
      if (char == '-' && i == 0) {
        continue;
      }
      return i;
    }
  }
  return -1;
}

String _formatExpressionValue(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  var text = value.toStringAsFixed(2);
  text = text.replaceAll(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

class ExpressionEvaluator {
  static double? tryEvaluate(String expression) {
    if (expression.trim().isEmpty) {
      return null;
    }

    final normalized =
        expression.replaceAll('×', '*').replaceAll('÷', '/').replaceAll(' ', '');
    final tokens = _tokenize(normalized);
    if (tokens == null || tokens.isEmpty) {
      return null;
    }

    final rpn = _toRpn(tokens);
    if (rpn == null) {
      return null;
    }

    return _evaluateRpn(rpn);
  }

  static List<_Token>? _tokenize(String expression) {
    final tokens = <_Token>[];
    final buffer = StringBuffer();
    var expectingNumber = true;

    for (var i = 0; i < expression.length; i++) {
      final char = expression[i];
      if (_isDigit(char) || char == '.') {
        buffer.write(char);
        expectingNumber = false;
        continue;
      }

      if (_isOperator(char)) {
        if (char == '-' && expectingNumber) {
          buffer.write(char);
          expectingNumber = true;
          continue;
        }

        if (buffer.isEmpty) {
          return null;
        }

        final number = double.tryParse(buffer.toString());
        if (number == null) {
          return null;
        }

        tokens.add(_Token.number(number));
        buffer.clear();
        tokens.add(_Token.operator(char));
        expectingNumber = true;
        continue;
      }

      return null;
    }

    if (buffer.isEmpty) {
      return null;
    }

    final number = double.tryParse(buffer.toString());
    if (number == null) {
      return null;
    }
    tokens.add(_Token.number(number));
    return tokens;
  }

  static List<_Token>? _toRpn(List<_Token> tokens) {
    final output = <_Token>[];
    final operators = <_Token>[];

    for (final token in tokens) {
      if (token.type == _TokenType.number) {
        output.add(token);
      } else {
        while (operators.isNotEmpty &&
            _precedence(operators.last.operator) >=
                _precedence(token.operator)) {
          output.add(operators.removeLast());
        }
        operators.add(token);
      }
    }

    while (operators.isNotEmpty) {
      output.add(operators.removeLast());
    }

    return output;
  }

  static double? _evaluateRpn(List<_Token> tokens) {
    final stack = <double>[];

    for (final token in tokens) {
      if (token.type == _TokenType.number) {
        stack.add(token.value);
      } else {
        if (stack.length < 2) {
          return null;
        }
        final right = stack.removeLast();
        final left = stack.removeLast();
        switch (token.operator) {
          case '+':
            stack.add(left + right);
            break;
          case '-':
            stack.add(left - right);
            break;
          case '*':
            stack.add(left * right);
            break;
          case '/':
            if (right == 0) {
              return null;
            }
            stack.add(left / right);
            break;
          default:
            return null;
        }
      }
    }

    if (stack.length != 1) {
      return null;
    }

    final result = stack.single;
    if (result.isNaN || result.isInfinite) {
      return null;
    }

    return result;
  }

  static int _precedence(String operator) {
    if (operator == '+' || operator == '-') {
      return 1;
    }
    if (operator == '*' || operator == '/') {
      return 2;
    }
    return 0;
  }

  static bool _isDigit(String char) {
    return char.compareTo('0') >= 0 && char.compareTo('9') <= 0;
  }
}

enum _TokenType { number, operator }

class _Token {
  _Token.number(this.value)
      : type = _TokenType.number,
        operator = '';

  _Token.operator(this.operator)
      : type = _TokenType.operator,
        value = 0;

  final _TokenType type;
  final double value;
  final String operator;
}

final entryFlowControllerProvider =
    StateNotifierProvider<EntryFlowController, EntryFlowState>((ref) {
  return EntryFlowController();
});
