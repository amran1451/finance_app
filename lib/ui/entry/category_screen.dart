import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/db_refresh.dart';
import '../categories/category_actions.dart';
import '../categories/category_edit_form.dart';
import '../categories/category_tree_view.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final type = entryState.type;
    final treeAsync = ref.watch(categoryTreeProvider(type));

    Future<void> showAddMenu() async {
      final option = await showAddCategoryOptions(context);
      if (option == null) {
        return;
      }
      if (option == AddCategoryOption.group) {
        await showCategoryEditForm(
          context,
          type: type,
          isGroup: true,
        );
      } else {
        await showCategoryEditForm(
          context,
          type: type,
          isGroup: false,
        );
      }
    }

    Future<void> removeCategory(Category category) async {
      final id = category.id;
      if (id == null) {
        return;
      }
      try {
        final repository = ref.read(categoriesRepositoryProvider);
        await repository.delete(id);
        bumpDbTick(ref);
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить категорию: $error')),
        );
      }
    }

    Future<void> handleCategoryLongPress(Category category) async {
      final action = await showCategoryActions(context, isGroup: false);
      if (action == null) {
        return;
      }
      if (action == CategoryAction.rename) {
        await showCategoryEditForm(
          context,
          type: category.type,
          isGroup: false,
          initial: category,
        );
      } else {
        await removeCategory(category);
      }
    }

    Future<void> handleGroupLongPress(Category group) async {
      final action = await showCategoryActions(context, isGroup: true);
      if (action == null) {
        return;
      }
      if (action == CategoryAction.rename) {
        await showCategoryEditForm(
          context,
          type: group.type,
          isGroup: true,
          initial: group,
        );
      } else {
        await removeCategory(group);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Категория операции'),
        actions: [
          IconButton(
            onPressed: showAddMenu,
            icon: const Icon(Icons.add),
            tooltip: 'Добавить',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(
                  value: CategoryType.income,
                  label: Text('Доходы'),
                  icon: Icon(Icons.trending_up),
                ),
                ButtonSegment(
                  value: CategoryType.expense,
                  label: Text('Расходы'),
                  icon: Icon(Icons.trending_down),
                ),
                ButtonSegment(
                  value: CategoryType.saving,
                  label: Text('Сбережения'),
                  icon: Icon(Icons.savings),
                ),
              ],
              selected: {entryState.type},
              onSelectionChanged: (value) {
                controller.setType(value.first);
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
                    onCategoryTap: (category) {
                      if (category.id == null) {
                        return;
                      }
                      controller.setCategory(category);
                      context.pushNamed(RouteNames.entryReview);
                    },
                    onCategoryLongPress: handleCategoryLongPress,
                    onGroupLongPress: handleGroupLongPress,
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
