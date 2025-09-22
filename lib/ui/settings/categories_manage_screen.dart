import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/mock_models.dart';
import '../../state/app_providers.dart';
import '../categories/category_actions.dart';
import '../categories/category_edit_form.dart';
import '../categories/category_tree_view.dart';

class CategoriesManageScreen extends ConsumerStatefulWidget {
  const CategoriesManageScreen({super.key});

  @override
  ConsumerState<CategoriesManageScreen> createState() =>
      _CategoriesManageScreenState();
}

class _CategoriesManageScreenState
    extends ConsumerState<CategoriesManageScreen> {
  OperationType _selectedType = OperationType.income;

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
      ref.read(categoriesRepositoryProvider).removeCategory(category.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(categoriesRepositoryProvider);
    final groups = repository.groupsByType(_selectedType);
    final categories = repository.getByType(_selectedType);
    final ungrouped =
        categories.where((category) => category.parentId == null).toList();
    final childrenByGroup = {
      for (final group in groups) group.id: repository.childrenOf(group.id)
    };

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
            SegmentedButton<OperationType>(
              segments: const [
                ButtonSegment(
                  value: OperationType.income,
                  label: Text('Доходы'),
                  icon: Icon(Icons.trending_up),
                ),
                ButtonSegment(
                  value: OperationType.expense,
                  label: Text('Расходы'),
                  icon: Icon(Icons.trending_down),
                ),
                ButtonSegment(
                  value: OperationType.savings,
                  label: Text('Сбережения'),
                  icon: Icon(Icons.savings),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (value) {
                setState(() => _selectedType = value.first);
              },
            ),
            const SizedBox(height: 24),
            Expanded(
              child: CategoryTreeView(
                groups: groups,
                childrenByGroup: childrenByGroup,
                ungrouped: ungrouped,
                onCategoryTap: _editCategory,
                onCategoryLongPress: _onLongPress,
                onGroupTap: _editCategory,
                onGroupLongPress: _onLongPress,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
