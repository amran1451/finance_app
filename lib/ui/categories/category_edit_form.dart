import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';

Future<void> showCategoryEditForm(
  BuildContext context, {
  required CategoryType type,
  required bool isGroup,
  Category? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 16 + bottomInset,
        ),
        child: _CategoryEditFormSheet(
          type: type,
          isGroup: isGroup,
          initial: initial,
        ),
      );
    },
  );
}

class _CategoryEditFormSheet extends ConsumerStatefulWidget {
  const _CategoryEditFormSheet({
    required this.type,
    required this.isGroup,
    this.initial,
  });

  final CategoryType type;
  final bool isGroup;
  final Category? initial;

  @override
  ConsumerState<_CategoryEditFormSheet> createState() =>
      _CategoryEditFormSheetState();
}

class _CategoryEditFormSheetState
    extends ConsumerState<_CategoryEditFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  int? _parentId;

  @override
  void initState() {
    super.initState();
    _name = widget.initial?.name ?? '';
    _parentId = widget.initial?.parentId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(categoryGroupsProvider(widget.type));
    final availableGroups = groupsAsync.value ?? const <Category>[];
    final hasParent =
        availableGroups.any((group) => group.id == _parentId);
    final isLoadingGroups = groupsAsync.isLoading && availableGroups.isEmpty;

    return Form(
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
                ? (widget.isGroup ? 'Новая папка' : 'Новая категория')
                : (widget.isGroup
                    ? 'Редактирование папки'
                    : 'Редактирование категории'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            initialValue: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Название',
            ),
            onChanged: (value) => _name = value,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Укажите название';
              }
              return null;
            },
          ),
          if (!widget.isGroup) ...[
            const SizedBox(height: 16),
            if (isLoadingGroups)
              const Center(child: CircularProgressIndicator())
            else if (groupsAsync.hasError && availableGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Не удалось загрузить папки: ${groupsAsync.error}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              )
            else
              DropdownButtonFormField<int?>(
                value: hasParent ? _parentId : null,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Без папки'),
                  ),
                  for (final group in availableGroups)
                    if (group.id != null)
                      DropdownMenuItem<int?>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                ],
                onChanged: (value) {
                  setState(() {
                    _parentId = value;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Папка',
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  if (!mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('Отмена'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  final trimmed = _name.trim();
                  final repo = ref.read(categoriesRepositoryProvider);
                  try {
                    if (widget.initial == null) {
                      if (widget.isGroup) {
                        await repo.create(
                          Category(
                            type: widget.type,
                            name: trimmed,
                            isGroup: true,
                          ),
                        );
                      } else {
                        await repo.create(
                          Category(
                            type: widget.type,
                            name: trimmed,
                            parentId: _parentId,
                          ),
                        );
                      }
                    } else {
                      await repo.update(
                        widget.initial!.copyWith(
                          name: trimmed,
                          parentId: widget.isGroup ? null : _parentId,
                        ),
                      );
                    }
                    bumpDbTick(ref);
                    if (!mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Не удалось сохранить: $error')),
                    );
                  }
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
