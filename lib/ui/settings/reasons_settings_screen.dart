import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/reason_repository.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/reason_providers.dart';
import '../../utils/color_hex.dart';
import '../widgets/color_picker.dart';

Future<void> showReasonEditSheet(
  BuildContext context, {
  ReasonLabel? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReasonEditSheet(initial: initial),
  );
}

class _ReasonEditSheet extends ConsumerStatefulWidget {
  const _ReasonEditSheet({
    this.initial,
    super.key,
  });

  final ReasonLabel? initial;

  @override
  ConsumerState<_ReasonEditSheet> createState() => _ReasonEditSheetState();
}

class _ReasonEditSheetState extends ConsumerState<_ReasonEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _name = widget.initial?.name ?? '';
    _color = hexToColor(widget.initial?.color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: 16 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.initial == null
                  ? 'Добавить причину'
                  : 'Редактировать причину',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (value) => _name = value,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Укажите название';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _colorRow(context),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (!mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) {
                        return;
                      }
                      final repo = ref.read(reasonRepoProvider);
                      final name = _name.trim();
                      final color = colorToHex(_color);
                      if (widget.initial == null) {
                        final labels = await ref.read(reasonLabelsProvider.future);
                        final sortOrder =
                            labels.isEmpty ? 0 : labels.last.sortOrder + 1;
                        await repo.create(
                          name: name,
                          color: color,
                          sortOrder: sortOrder,
                        );
                      } else {
                        await repo.update(
                          widget.initial!.id,
                          name: name,
                          color: color,
                        );
                      }
                      bumpDbTick(ref);
                      ref.invalidate(reasonLabelsProvider);
                      if (!mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: _color ?? cs.surfaceVariant,
          radius: 12,
          child: _color == null
              ? Icon(
                  Icons.block,
                  size: 14,
                  color: cs.onSurfaceVariant,
                )
              : null,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: const Icon(Icons.palette_outlined),
          label: const Text('Выбрать цвет'),
          onPressed: () => showColorPickerSheet(
            context,
            initial: _color,
            onPicked: (c) => setState(() => _color = c),
          ),
        ),
        const Spacer(),
        if (_color != null)
          TextButton(
            onPressed: () => setState(() => _color = null),
            child: const Text('Сбросить'),
          ),
      ],
    );
  }
}

class ReasonsSettingsScreen extends ConsumerStatefulWidget {
  const ReasonsSettingsScreen({super.key});

  @override
  ConsumerState<ReasonsSettingsScreen> createState() =>
      _ReasonsSettingsScreenState();
}

class _ReasonsSettingsScreenState extends ConsumerState<ReasonsSettingsScreen> {
  static const double _itemHeight = 76;

  @override
  Widget build(BuildContext context) {
    final labelsAsync = ref.watch(reasonLabelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Причины расходов')),
      body: labelsAsync.when(
        data: (labels) {
          if (labels.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Причины не найдены. Добавьте новую, чтобы использовать их при создании расходов.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ReorderableListView.builder(
              itemCount: labels.length,
              onReorder: _handleReorder,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => child,
              itemBuilder: (context, index) {
                final label = labels[index];
                final hasColor = label.color?.trim().isNotEmpty == true;
                final color = hexToColor(label.color);
                return SizedBox(
                  key: ValueKey(label.id),
                  height: _itemHeight,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            color ?? Theme.of(context).colorScheme.surfaceVariant,
                        child: hasColor ? null : const Icon(Icons.block, size: 16),
                      ),
                      title: Text(label.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle),
                          ),
                          IconButton(
                            tooltip: 'Переименовать',
                            onPressed: () =>
                                showReasonEditSheet(context, initial: label),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            onPressed: () => _deleteLabel(label),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось загрузить причины: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showReasonEditSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final labels = await ref.read(reasonLabelsProvider.future);
    if (oldIndex < 0 || oldIndex >= labels.length) {
      return;
    }
    final updated = [...labels];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    final repo = ref.read(reasonRepoProvider);
    await repo.reorder([for (final label in updated) label.id]);
    bumpDbTick(ref);
    ref.invalidate(reasonLabelsProvider);
  }

  Future<void> _deleteLabel(ReasonLabel label) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить причину?'),
            content: Text(
              '"${label.name}" будет удалена и больше не появится при выборе причин расходов.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    final repo = ref.read(reasonRepoProvider);
    await repo.archive(label.id);
    bumpDbTick(ref);
    ref.invalidate(reasonLabelsProvider);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Причина "${label.name}" удалена')),
    );
  }
}
