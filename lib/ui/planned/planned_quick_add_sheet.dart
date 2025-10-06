import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../state/planned_providers.dart';
import '../../utils/period_utils.dart';

Future<bool?> showPlannedQuickAddForm(
  BuildContext context, {
  required WidgetRef ref,
  required String type,
  required PeriodRef period,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PlannedQuickAddSheet(
      type: type,
      period: period,
    ),
  );
}

class _PlannedQuickAddSheet extends ConsumerStatefulWidget {
  const _PlannedQuickAddSheet({
    required this.type,
    required this.period,
  });

  final String type;
  final PeriodRef period;

  @override
  ConsumerState<_PlannedQuickAddSheet> createState() =>
      _PlannedQuickAddSheetState();
}

class _PlannedQuickAddSheetState extends ConsumerState<_PlannedQuickAddSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  int? _selectedCategoryId;
  int? _selectedNecessityId;
  bool _included = false;
  bool _reuseExisting = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _amountController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.9;
    final categoryType = _categoryTypeFor(widget.type);
    final AsyncValue<List<Category>> categoriesAsync;
    if (categoryType != null) {
      categoriesAsync = ref.watch(categoriesByTypeProvider(categoryType));
    } else {
      categoriesAsync = const AsyncValue<List<Category>>.data(<Category>[]);
    }
    final AsyncValue<List<necessity_repo.NecessityLabel>> necessityLabelsAsync;
    if (widget.type == 'expense') {
      necessityLabelsAsync = ref.watch(necessityLabelsFutureProvider);
    } else {
      necessityLabelsAsync =
          const AsyncValue<List<necessity_repo.NecessityLabel>>.data(
        <necessity_repo.NecessityLabel>[],
      );
    }

    final categories = categoriesAsync.maybeWhen<List<Category>>(
      data: (items) {
        final filtered = [
          for (final item in items)
            if (!item.isGroup && !item.isArchived && item.id != null) item,
        ];
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (_selectedCategoryId == null && filtered.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _selectedCategoryId = filtered.first.id;
            });
          });
        }
        return filtered;
      },
      orElse: () => const [],
    );
    final categoriesError =
        categoriesAsync is AsyncError ? categoriesAsync.error : null;
    final canSubmit =
        !_isSaving && categories.isNotEmpty && _selectedCategoryId != null;

    return SizedBox(
      height: sheetHeight + viewInsets,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
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
                        _titleForType(widget.type),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Укажите название';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      if (categoriesAsync.isLoading)
                        const LinearProgressIndicator()
                      else if (categoriesError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Не удалось загрузить категории: $categoriesError',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        )
                      else if (categories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Добавьте категорию, чтобы создать план.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      else
                        DropdownButtonFormField<int>(
                          value: _selectedCategoryId,
                          items: [
                            for (final category in categories)
                              DropdownMenuItem<int>(
                                value: category.id,
                                child: Text(category.name),
                              ),
                          ],
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  setState(() => _selectedCategoryId = value);
                                },
                          decoration: const InputDecoration(
                            labelText: 'Категория',
                          ),
                          validator: (value) {
                            if (value == null) {
                              return 'Выберите категорию';
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: 'Сумма',
                          prefixText: '₽ ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          final raw = value?.trim() ?? '';
                          if (raw.isEmpty) {
                            return 'Укажите сумму';
                          }
                          final parsed = int.tryParse(raw);
                          if (parsed == null || parsed <= 0) {
                            return 'Сумма должна быть больше 0';
                          }
                          return null;
                        },
                      ),
                      if (widget.type == 'expense') ...[
                        const SizedBox(height: 12),
                        necessityLabelsAsync.when(
                          data: (labels) {
                            return DropdownButtonFormField<int?>(
                              value: _selectedNecessityId,
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Без необходимости'),
                                ),
                                for (final label in labels)
                                  DropdownMenuItem<int?>(
                                    value: label.id,
                                    child: Text(label.name),
                                  ),
                              ],
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      setState(() => _selectedNecessityId = value);
                                    },
                              decoration: const InputDecoration(
                                labelText: 'Критичность/необходимость',
                              ),
                            );
                          },
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Не удалось загрузить ярлыки: $error',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _included,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() => _included = value ?? false);
                              },
                        title: const Text('Учитывать в расчёте'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _reuseExisting,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() => _reuseExisting = value ?? true);
                              },
                        title: const Text('Использовать уже существующий, если есть'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          labelText: 'Примечание',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: canSubmit ? _handleSubmit : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  CategoryType? _categoryTypeFor(String type) {
    switch (type) {
      case 'income':
        return CategoryType.income;
      case 'expense':
        return CategoryType.expense;
      case 'saving':
        return CategoryType.saving;
      default:
        return null;
    }
  }

  String _titleForType(String type) {
    switch (type) {
      case 'income':
        return 'Быстрое добавление дохода';
      case 'saving':
        return 'Быстрое добавление сбережения';
      case 'expense':
      default:
        return 'Быстрое добавление расхода';
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      return;
    }
    final amountRub = int.tryParse(_amountController.text.trim());
    if (amountRub == null || amountRub <= 0) {
      return;
    }
    final title = _titleController.text.trim();
    final noteText = _noteController.text.trim();
    final note = noteText.isEmpty ? null : noteText;
    final necessityId = widget.type == 'expense' ? _selectedNecessityId : null;

    setState(() => _isSaving = true);
    try {
      final facade = ref.read(plannedFacadeProvider);
      await facade.createMasterAndAssignToCurrentPeriod(
        type: widget.type,
        title: title,
        categoryId: categoryId,
        amountMinor: amountRub * 100,
        period: widget.period,
        includedInPeriod: _included,
        necessityId: necessityId,
        note: note,
        reuseExisting: _reuseExisting,
      );
      bumpDbTick(ref);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить план: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
