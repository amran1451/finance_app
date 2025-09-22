import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/necessity_repository.dart';
import '../../state/app_providers.dart';

class NecessitySettingsScreen extends ConsumerStatefulWidget {
  const NecessitySettingsScreen({super.key});

  @override
  ConsumerState<NecessitySettingsScreen> createState() =>
      _NecessitySettingsScreenState();
}

class _NecessitySettingsScreenState
    extends ConsumerState<NecessitySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final labelsAsync = ref.watch(necessityLabelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Критичность/Необходимость')),
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
                      'Метки не найдены. Добавьте новую, чтобы использовать их при создании операций.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              itemBuilder: (context, index) {
                final label = labels[index];
                return Card(
                  key: ValueKey(label.id),
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(label.name),
                    subtitle: label.color?.trim().isNotEmpty == true
                        ? Text('Цвет: ${label.color}')
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Переименовать',
                          onPressed: () => _showLabelDialog(label: label),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: 'Скрыть',
                          onPressed: () => _archiveLabel(label),
                          icon: const Icon(Icons.archive),
                        ),
                      ],
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
              'Не удалось загрузить метки: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLabelDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final labels = await ref.read(necessityLabelsProvider.future);
    if (oldIndex < 0 || oldIndex >= labels.length) {
      return;
    }
    final updated = [...labels];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    final repo = ref.read(necessityRepoProvider);
    await repo.reorder([for (final label in updated) label.id]);
    ref.invalidate(necessityLabelsProvider);
  }

  Future<void> _archiveLabel(NecessityLabel label) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Скрыть метку?'),
            content: Text(
              '"${label.name}" больше не будет отображаться при выборе критичности.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Скрыть'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    final repo = ref.read(necessityRepoProvider);
    await repo.archive(label.id);
    ref.invalidate(necessityLabelsProvider);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Метка "${label.name}" скрыта')),
    );
  }

  Future<void> _showLabelDialog({NecessityLabel? label}) async {
    final nameController = TextEditingController(text: label?.name ?? '');
    final colorController = TextEditingController(text: label?.color ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label == null ? 'Добавить метку' : 'Редактировать метку'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: colorController,
                decoration: const InputDecoration(
                  labelText: 'Цвет (#RRGGBB)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) {
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != true) {
      nameController.dispose();
      colorController.dispose();
      return;
    }

    final repo = ref.read(necessityRepoProvider);
    final name = nameController.text.trim();
    final color = colorController.text.trim().isEmpty
        ? null
        : colorController.text.trim();

    if (label == null) {
      final labels = await ref.read(necessityLabelsProvider.future);
      final sortOrder = labels.isEmpty ? 0 : labels.last.sortOrder + 1;
      await repo.create(name: name, color: color, sortOrder: sortOrder);
    } else {
      await repo.update(label.id, name: name, color: color);
    }

    nameController.dispose();
    colorController.dispose();
    ref.invalidate(necessityLabelsProvider);
  }
}
