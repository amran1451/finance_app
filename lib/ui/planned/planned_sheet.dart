import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction_record.dart';
import '../../state/app_providers.dart';
import '../../state/planned_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';
import 'planned_add_form.dart';

Future<void> showPlannedSheet(
  BuildContext context, {
  required PlannedType type,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
    ),
    builder: (modalContext) {
      final bottomInset = MediaQuery.of(modalContext).viewInsets.bottom;
      return SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16 + bottomInset),
          child: _PlannedSheetContent(type: type),
        ),
      );
    },
  );
}

class _PlannedSheetContent extends ConsumerStatefulWidget {
  const _PlannedSheetContent({
    required this.type,
  });

  final PlannedType type;

  @override
  ConsumerState<_PlannedSheetContent> createState() =>
      _PlannedSheetContentState();
}

class _PlannedSheetContentState extends ConsumerState<_PlannedSheetContent> {
  @override
  void initState() {
    super.initState();
    ref.read(isSheetOpenProvider.notifier).state = true;
  }

  @override
  void dispose() {
    ref.read(isSheetOpenProvider.notifier).state = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (ctx, scroll) {
        final itemsAsync = ref.watch(plannedItemsByTypeProvider(widget.type));
        final actions = ref.read(plannedActionsProvider);

        Future<void> handleLongPress(PlannedItemView item) async {
          final action = await showModalBottomSheet<_PlannedItemAction>(
            context: ctx,
            useSafeArea: true,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            builder: (actionContext) {
              final scheme = Theme.of(actionContext).colorScheme;
              return SafeArea(
                bottom: true,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 12,
                    left: 24,
                    right: 24,
                    bottom: 16 + MediaQuery.of(actionContext).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Редактировать'),
                        onTap: () =>
                            Navigator.of(actionContext).pop(_PlannedItemAction.edit),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Удалить'),
                        onTap: () =>
                            Navigator.of(actionContext).pop(_PlannedItemAction.delete),
                      ),
                      ListTile(
                        leading: const Icon(Icons.close),
                        title: const Text('Отмена'),
                        onTap: () => Navigator.of(actionContext).pop(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

          if (action == _PlannedItemAction.delete) {
            final confirm = await showDialog<bool>(
              context: ctx,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Удалить запись?'),
                content: const Text('Это действие нельзя отменить.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              final id = item.record.id;
              if (id != null) {
                await actions.remove(id);
                bumpDbTick(ref);
              }
            }
          } else if (action == _PlannedItemAction.edit) {
            await showPlannedAddForm(
              ctx,
              type: widget.type,
              initialRecord: item.record,
            );
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                type: widget.type,
                onClose: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: itemsAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return ListView(
                        controller: scroll,
                        children: [
                          const SizedBox(height: 48),
                          Center(
                            child: Text(
                              'Нет запланированных записей',
                              style: Theme.of(ctx).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _PlannedItemTile(
                          item: item,
                          onToggle: (value) async {
                            final id = item.record.id;
                            if (id == null) {
                              return;
                            }
                            await actions.toggle(id, value ?? false);
                            bumpDbTick(ref);
                          },
                          onLongPress: () => handleLongPress(item),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: items.length,
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => ListView(
                    controller: scroll,
                    children: [
                      const SizedBox(height: 48),
                      Center(
                        child: Text(
                          'Ошибка загрузки: $error',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showPlannedAddForm(
                  ctx,
                  type: widget.type,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
            ],
          ),
        );
      },
    );
  }
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
    required this.onLongPress,
  });

  final PlannedItemView item;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onLongPress: onLongPress,
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

enum _PlannedItemAction { edit, delete }
