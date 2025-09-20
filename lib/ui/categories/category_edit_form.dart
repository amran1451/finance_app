import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/mock_models.dart';
import '../../state/app_providers.dart';

Future<void> showCategoryEditForm(
  BuildContext context,
  WidgetRef ref, {
  required CategoryType type,
  required bool isGroup,
  Category? initial,
}) {
  final formKey = GlobalKey<FormState>();
  final repository = ref.read(categoriesRepositoryProvider);
  String name = initial?.name ?? '';
  String? parentId = initial?.parentId;

  final availableGroups = repository.groupsByType(type);

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
        child: StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            return Form(
              key: formKey,
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
                    initial == null
                        ? (isGroup ? 'Новая папка' : 'Новая категория')
                        : (isGroup
                            ? 'Редактирование папки'
                            : 'Редактирование категории'),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    initialValue: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                    ),
                    onChanged: (value) => name = value,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Укажите название';
                      }
                      return null;
                    },
                  ),
                  if (!isGroup) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      value: availableGroups.any((group) => group.id == parentId)
                          ? parentId
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Без папки'),
                        ),
                        for (final group in availableGroups)
                          DropdownMenuItem<String?>(
                            value: group.id,
                            child: Text(group.name),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          parentId = value;
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
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Отмена'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          final trimmed = name.trim();
                          if (initial == null) {
                            if (isGroup) {
                              repository.addGroup(type: type, name: trimmed);
                            } else {
                              repository.addCategory(
                                type: type,
                                name: trimmed,
                                parentId: parentId,
                              );
                            }
                          } else {
                            repository.updateCategory(
                              initial.id,
                              name: trimmed,
                              parentId: isGroup ? null : parentId,
                            );
                          }
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
