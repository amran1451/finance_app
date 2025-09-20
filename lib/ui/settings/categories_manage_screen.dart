import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock/mock_models.dart';
import '../../state/app_providers.dart';
import '../categories/category_edit_form.dart';

class CategoriesManageScreen extends ConsumerStatefulWidget {
  const CategoriesManageScreen({super.key});

  @override
  ConsumerState<CategoriesManageScreen> createState() =>
      _CategoriesManageScreenState();
}

class _CategoriesManageScreenState
    extends ConsumerState<CategoriesManageScreen> {
  OperationType _selectedType = OperationType.income;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(categoriesRepositoryProvider);
    final categories = repository.getByType(_selectedType);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка категорий'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FilledButton.icon(
        onPressed: () => showCategoryEditForm(
          context,
          ref,
          type: _selectedType,
        ),
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
              child: categories.isEmpty
                  ? Center(
                      child: Text(
                        'Категории не найдены',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  category.type.color.withOpacity(0.15),
                              child: Icon(
                                category.icon,
                                color: category.type.color,
                              ),
                            ),
                            title: Text(category.name),
                            subtitle: category.subcategory != null
                                ? Text(category.subcategory!)
                                : null,
                            onTap: () => showCategoryEditForm(
                              context,
                              ref,
                              type: category.type,
                              initial: category,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Редактировать',
                                  onPressed: () => showCategoryEditForm(
                                    context,
                                    ref,
                                    type: category.type,
                                    initial: category,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                PopupMenuButton<_CategoryAction>(
                                  onSelected: (action) {
                                    if (action == _CategoryAction.delete) {
                                      ref
                                          .read(categoriesRepositoryProvider)
                                          .removeCategory(category.id);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _CategoryAction.delete,
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                  icon: const Icon(Icons.more_vert),
                                ),
                              ],
                            ),
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

enum _CategoryAction { delete }
