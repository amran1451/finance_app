import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock/mock_models.dart';

const bool kReturnToOperationsAfterSave = true;

class EntryFlowState {
  const EntryFlowState({
    this.amountInput = '',
    this.type = OperationType.expense,
    this.category,
    DateTime? selectedDate,
    this.note = '',
    this.attachToPlanned = false,
  }) : selectedDate = selectedDate ?? _today;

  final String amountInput;
  final OperationType type;
  final Category? category;
  final DateTime selectedDate;
  final String note;
  final bool attachToPlanned;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  double get amount {
    if (amountInput.isEmpty) {
      return 0;
    }
    return double.tryParse(amountInput.replaceAll(',', '.')) ?? 0;
  }

  bool get canProceedToCategory => amount > 0;

  bool get canSave => amount > 0 && category != null;

  EntryFlowState copyWith({
    String? amountInput,
    OperationType? type,
    Category? category,
    DateTime? selectedDate,
    String? note,
    bool? attachToPlanned,
  }) {
    return EntryFlowState(
      amountInput: amountInput ?? this.amountInput,
      type: type ?? this.type,
      category: category ?? this.category,
      selectedDate: selectedDate ?? this.selectedDate,
      note: note ?? this.note,
      attachToPlanned: attachToPlanned ?? this.attachToPlanned,
    );
  }

  EntryFlowState clearCategory() {
    return copyWith(category: null);
  }
}

class EntryFlowController extends StateNotifier<EntryFlowState> {
  EntryFlowController() : super(const EntryFlowState());

  void startNew({OperationType type = OperationType.expense}) {
    state = EntryFlowState(type: type);
  }

  void appendDigit(String digit) {
    if (digit == '.' && state.amountInput.contains('.')) {
      return;
    }
    state = state.copyWith(amountInput: state.amountInput + digit);
  }

  void appendSeparator() {
    if (state.amountInput.contains('.')) {
      return;
    }
    if (state.amountInput.isEmpty) {
      state = state.copyWith(amountInput: '0.');
    } else {
      state = state.copyWith(amountInput: state.amountInput + '.');
    }
  }

  void backspace() {
    if (state.amountInput.isEmpty) {
      return;
    }
    state = state.copyWith(
      amountInput: state.amountInput.substring(0, state.amountInput.length - 1),
    );
  }

  void clear() {
    state = state.copyWith(amountInput: '');
  }

  void addQuickAmount(double value) {
    final current = state.amount;
    final newAmount = current + value;
    state = state.copyWith(amountInput: newAmount.toStringAsFixed(0));
  }

  void setType(OperationType type) {
    if (type == state.type) {
      return;
    }
    state = EntryFlowState(
      type: type,
      amountInput: state.amountInput,
      selectedDate: state.selectedDate,
      note: state.note,
    );
  }

  void setCategory(Category category) {
    state = state.copyWith(category: category);
  }

  void setDate(DateTime date) {
    state = state.copyWith(selectedDate: DateTime(date.year, date.month, date.day));
  }

  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  void setAttachToPlanned(bool value) {
    state = state.copyWith(attachToPlanned: value);
  }

  void reset() {
    state = const EntryFlowState();
  }
}

final entryFlowControllerProvider =
    StateNotifierProvider<EntryFlowController, EntryFlowState>((ref) {
  return EntryFlowController();
});
