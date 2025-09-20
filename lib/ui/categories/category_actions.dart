import 'package:flutter/material.dart';

enum AddCategoryOption { group, category }

enum CategoryAction { rename, delete }

Future<AddCategoryOption?> showAddCategoryOptions(BuildContext context) {
  return showModalBottomSheet<AddCategoryOption>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Папка (группа)'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(AddCategoryOption.group),
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('Категория'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(AddCategoryOption.category),
            ),
          ],
        ),
      );
    },
  );
}

Future<CategoryAction?> showCategoryActions(
  BuildContext context, {
  required bool isGroup,
}) {
  return showModalBottomSheet<CategoryAction>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(isGroup ? 'Переименовать папку' : 'Переименовать категорию'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(CategoryAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(CategoryAction.delete),
            ),
          ],
        ),
      );
    },
  );
}
