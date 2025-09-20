import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/mock_models.dart';
import '../../state/app_providers.dart';

Future<void> showCategoryEditForm(
  BuildContext context,
  WidgetRef ref, {
  required OperationType type,
  Category? initial,
}) async {
  final formKey = GlobalKey<FormState>();
  final controller = TextEditingController(text: initial?.name ?? '');

  try {
    await showModalBottomSheet<void>(
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
          child: Form(
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
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  initial == null
                      ? 'Новая категория'
                      : 'Редактирование категории',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Укажите название';
                    }
                    return null;
                  },
                ),
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
                        final name = controller.text.trim();
                        final repository =
                            ref.read(categoriesRepositoryProvider);
                        if (initial == null) {
                          repository.addCategory(type: type, name: name);
                        } else {
                          repository.updateCategory(initial.id, name: name);
                        }
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Сохранить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
