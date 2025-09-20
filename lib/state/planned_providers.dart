import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PlannedType { income, expense, saving }

class PlannedItem {
  final String id;
  final PlannedType type;
  final String title;
  final double amount;
  final bool isDone;

  const PlannedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    this.isDone = false,
  });

  PlannedItem copyWith({
    String? id,
    PlannedType? type,
    String? title,
    double? amount,
    bool? isDone,
  }) {
    return PlannedItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      isDone: isDone ?? this.isDone,
    );
  }
}

class PlannedController extends StateNotifier<List<PlannedItem>> {
  PlannedController() : super(const []);

  void add({
    required PlannedType type,
    required String title,
    required double amount,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    state = [
      ...state,
      PlannedItem(id: id, type: type, title: title, amount: amount),
    ];
  }

  void toggle(String id, bool value) {
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(isDone: value)
        else
          item,
    ];
  }

  void remove(String id) {
    state = state.where((item) => item.id != id).toList(growable: false);
  }
}

final plannedProvider =
    StateNotifierProvider<PlannedController, List<PlannedItem>>((ref) {
  return PlannedController();
});

final plannedTotalByTypeProvider =
    Provider.family<double, PlannedType>((ref, type) {
  final items = ref.watch(plannedProvider).where((item) => item.type == type);
  return items.fold<double>(0, (sum, item) => sum + item.amount);
});
