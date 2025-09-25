import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../categories/category_actions.dart';
import '../categories/category_edit_form.dart';
import '../categories/category_tree_view.dart';
import '../widgets/category_tabs.dart';

class CategoriesManageScreen extends ConsumerStatefulWidget {
  const CategoriesManageScreen({super.key});

  @override
  ConsumerState<CategoriesManageScreen> createState() =>
      _CategoriesManageScreenState();
}

class _CategoriesManageScreenState
    extends ConsumerState<CategoriesManageScreen> {
  CategoryType _selectedType = CategoryType.income;

  Future<void> _showAddMenu() async {
    final option = await showAddCategoryOptions(context);
    if (option == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    await showCategoryEditForm(
      context,
      type: _selectedType,
      isGroup: option == AddCategoryOption.group,
    );
  }

  Future<void> _editCategory(Category category) {
    return showCategoryEditForm(
      context,
      type: category.type,
      isGroup: category.isGroup,
      initial: category,
    );
  }

  Future<void> _onLongPress(Category category) async {
    final action = await showCategoryActions(
      context,
      isGroup: category.isGroup,
    );
    if (action == null) {
      return;
    }
    if (action == CategoryAction.rename) {
      await _editCategory(category);
    } else {
      final id = category.id;
      if (id == null) {
        return;
      }
      try {
        final repository = ref.read(categoriesRepositoryProvider);
        await repository.delete(id);
        bumpDbTick(ref);
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(categoryTreeProvider(_selectedType));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка категорий'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FilledButton.icon(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CategoryTabs(
              selected: _selectedType,
              onChanged: (value) {
                setState(() => _selectedType = value);
              },
            ),
            const SizedBox(height: 24),
            Expanded(
              child: treeAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Не удалось загрузить категории: $error'),
                  ),
                ),
                data: (tree) {
                  final groups = tree.groups;
                  final categories = tree.categories;
                  final ungrouped = categories
                      .where((category) => category.parentId == null)
                      .toList();
                  final childrenByGroup = <int, List<Category>>{
                    for (final group in groups)
                      if (group.id != null)
                        group.id!: categories
                            .where((category) => category.parentId == group.id)
                            .toList(),
                  };

                  return CategoryTreeView(
                    groups: groups,
                    childrenByGroup: childrenByGroup,
                    ungrouped: ungrouped,
                    onCategoryTap: _editCategory,
                    onCategoryLongPress: _onLongPress,
                    onGroupTap: _editCategory,
                    onGroupLongPress: _onLongPress,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
