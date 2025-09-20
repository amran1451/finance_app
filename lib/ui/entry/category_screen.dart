import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock/mock_models.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/entry_flow_providers.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final categoriesRepo = ref.watch(categoriesRepositoryProvider);
    final categories = categoriesRepo.getByType(entryState.type);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Категория операции'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed(RouteNames.categoryCreate),
            icon: const Icon(Icons.add),
            tooltip: 'Добавить категорию',
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
              child: ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: category.type.color.withOpacity(0.15),
                        child: Icon(category.icon, color: category.type.color),
                      ),
                      title: Text(category.name),
                      subtitle: category.subcategory != null
                          ? Text(category.subcategory!)
                          : null,
                      onTap: () {
                        controller.setCategory(category);
                        context.pushNamed(RouteNames.entryReview);
                      },
                    ),
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
