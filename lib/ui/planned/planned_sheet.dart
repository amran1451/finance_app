import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/planned_providers.dart';
import '../../utils/formatting.dart';
import 'planned_add_form.dart';

Future<void> showPlannedSheet(
  BuildContext context,
  WidgetRef ref, {
  required PlannedType type,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Consumer(
      builder: (sheetContext, sheetRef, __) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scroll) {
            final items = sheetRef
                .watch(plannedProvider)
                .where((item) => item.type == type)
                .toList(growable: false);
            final notifier = sheetRef.read(plannedProvider.notifier);

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SheetHeader(
                        type: type,
                        onClose: () => Navigator.of(ctx).pop(),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет запланированных записей',
                                  style: Theme.of(ctx).textTheme.bodyMedium,
                                ),
                              )
                            : ListView.separated(
                                controller: scroll,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return _PlannedItemTile(
                                    item: item,
                                    onToggle: (value) => notifier.toggle(
                                      item.id,
                                      value ?? false,
                                    ),
                                    onRemove: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Удалить запись?'),
                                          content: const Text(
                                              'Это действие нельзя отменить.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dialogContext)
                                                      .pop(false),
                                              child: const Text('Отмена'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dialogContext)
                                                      .pop(true),
                                              child: const Text('Удалить'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        notifier.remove(item.id);
                                      }
                                    },
                                  );
                                },
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemCount: items.length,
                              ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    minimum: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: () =>
                          showPlannedAddForm(ctx, ref, type: type),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить'),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.type,
    required this.onClose,
  });

  final PlannedType type;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      PlannedType.income => 'Запланированные доходы',
      PlannedType.expense => 'Запланированные расходы',
      PlannedType.saving => 'Запланированные сбережения',
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: onClose,
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _PlannedItemTile extends StatelessWidget {
  const _PlannedItemTile({
    required this.item,
    required this.onToggle,
    required this.onRemove,
  });

  final PlannedItem item;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onLongPress: onRemove,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: item.isDone,
                  onChanged: onToggle,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCurrency(item.amount),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: item.isDone ? 1 : 0,
            ),
          ],
        ),
      ),
    );
  }
}
