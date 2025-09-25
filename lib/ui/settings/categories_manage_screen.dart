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
  bool _selectionMode = false;
  final Set<int> _selectedCategoryIds = <int>{};

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedCategoryIds.clear();
    });
  }

  void _toggleCategorySelection(Category category) {
    final id = category.id;
    if (id == null) {
      return;
    }
    setState(() {
      if (!_selectedCategoryIds.remove(id)) {
        _selectedCategoryIds.add(id);
      }
    });
  }

  void _startSelectionMode() {
    if (_selectionMode) {
      return;
    }
    setState(() {
      _selectionMode = true;
    });
  }

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

  void _onCategoryTap(Category category) {
    if (_selectionMode) {
      _toggleCategorySelection(category);
      return;
    }
    _editCategory(category);
  }

  Future<void> _editCategory(Category category) {
    return showCategoryEditForm(
      context,
      type: category.type,
      isGroup: category.isGroup,
      initial: category,
    );
  }

  Future<void> _showCategoryActionsSheet(Category category) async {
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

  Future<void> _onCategoryLongPress(Category category) async {
    if (_selectionMode) {
      _toggleCategorySelection(category);
      return;
    }
    await _showCategoryActionsSheet(category);
  }

  Future<void> _onGroupLongPress(Category category) {
    return _showCategoryActionsSheet(category);
  }

  Future<void> _moveSelectedCategories() async {
    if (_selectedCategoryIds.isEmpty) {
      return;
    }
    final tree = await ref.read(categoryTreeProvider(_selectedType).future);
    if (!mounted) {
      return;
    }
    final choice = await showModalBottomSheet<({int? parentId, String name})>(
      context: context,
      builder: (context) {
        return _MoveCategoriesSheet(groups: tree.groups);
      },
    );
    if (choice == null) {
      return;
    }
    try {
      final repository = ref.read(categoriesRepositoryProvider);
      await repository.bulkMove(
        _selectedCategoryIds.toList(),
        choice.parentId,
      );
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Категории перенесены в "${choice.name}"')),
      );
      _clearSelection();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось перенести: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(categoryTreeProvider(_selectedType));

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('Выбрано ${_selectedCategoryIds.length}')
            : const Text('Настройка категорий'),
        leading: _selectionMode
            ? IconButton(
                tooltip: 'Отмена',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        actions: [
          if (_selectionMode)
            TextButton.icon(
              onPressed:
                  _selectedCategoryIds.isEmpty ? null : _moveSelectedCategories,
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('Переместить'),
            )
          else
            IconButton(
              tooltip: 'Выбрать категории',
              onPressed: _startSelectionMode,
              icon: const Icon(Icons.playlist_add_check),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selectionMode
          ? null
          : FilledButton.icon(
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
                setState(() {
                  _selectedType = value;
                  _selectionMode = false;
                  _selectedCategoryIds.clear();
                });
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
                    onCategoryTap: _onCategoryTap,
                    onCategoryLongPress: _onCategoryLongPress,
                    onGroupTap: _editCategory,
                    onGroupLongPress: _onGroupLongPress,
                    selectionMode: _selectionMode,
                    selectedCategoryIds: _selectedCategoryIds,
                    onCategorySelectionToggle: _toggleCategorySelection,
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

class _MoveCategoriesSheet extends StatelessWidget {
  const _MoveCategoriesSheet({required this.groups});

  final List<Category> groups;

  @override
  Widget build(BuildContext context) {
    final validGroups =
        groups.where((group) => group.id != null).toList(growable: false);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Переместить в папку',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Без папки'),
              onTap: () => Navigator.of(context)
                  .pop<({int? parentId, String name})>((parentId: null, name: 'Без папки')),
            ),
            if (validGroups.isNotEmpty)
              ...[for (final group in validGroups)
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(group.name),
                  onTap: () => Navigator.of(context).pop<({int? parentId, String name})>((
                    parentId: group.id!,
                    name: group.name,
                  )),
                ),
              ]
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Доступных папок нет'),
              ),
          ],
        ),
      ),
    );
  }
}
