import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_models.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../categories/category_actions.dart';
import '../categories/category_edit_form.dart';
import '../categories/category_tree_view.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final categoriesRepo = ref.watch(categoriesRepositoryProvider);
    final type = entryState.type;
    final groups = categoriesRepo.groupsByType(type);
    final categories = categoriesRepo.getByType(type);
    final ungrouped =
        categories.where((category) => category.parentId == null).toList();
    final childrenByGroup = {
      for (final group in groups) group.id: categoriesRepo.childrenOf(group.id)
    };

    Future<void> showAddMenu() async {
      final option = await showAddCategoryOptions(context);
      if (option == null) {
        return;
      }
      if (option == AddCategoryOption.group) {
        await showCategoryEditForm(
          context,
          ref,
          type: type,
          isGroup: true,
        );
      } else {
        await showCategoryEditForm(
          context,
          ref,
          type: type,
          isGroup: false,
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
          ref,
          type: category.type,
          isGroup: false,
          initial: category,
        );
      } else {
        ref.read(categoriesRepositoryProvider).removeCategory(category.id);
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
          ref,
          type: group.type,
          isGroup: true,
          initial: group,
        );
      } else {
        ref.read(categoriesRepositoryProvider).removeCategory(group.id);
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
              selected: {entryState.type},
              onSelectionChanged: (value) {
                controller.setType(value.first);
              },
            ),
            const SizedBox(height: 24),
            Expanded(
              child: CategoryTreeView(
                groups: groups,
                childrenByGroup: childrenByGroup,
                ungrouped: ungrouped,
                onCategoryTap: (category) {
                  controller.setCategory(category);
                  context.pushNamed(RouteNames.entryReview);
                },
                onCategoryLongPress: handleCategoryLongPress,
                onGroupLongPress: handleGroupLongPress,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
