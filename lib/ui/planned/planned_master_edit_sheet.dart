import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/repositories/planned_master_repository.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';

Future<void> showPlannedMasterEditSheet(
  BuildContext context, {
  PlannedMaster? initial,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: 16 + MediaQuery.of(modalContext).viewInsets.bottom,
        ),
        child: _PlannedMasterEditForm(initial: initial),
      );
    },
  );
}

class _PlannedMasterEditForm extends ConsumerStatefulWidget {
  const _PlannedMasterEditForm({this.initial});

  final PlannedMaster? initial;

  @override
  ConsumerState<_PlannedMasterEditForm> createState() =>
      _PlannedMasterEditFormState();
}

class _PlannedMasterEditFormState
    extends ConsumerState<_PlannedMasterEditForm> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final _formKey = GlobalKey<FormState>();

  String _type = 'expense';
  int? _categoryId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? 'expense';
    _categoryId = initial?.categoryId;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _noteController = TextEditingController(text: initial?.note ?? '');
    _amountController = TextEditingController(
      text: initial?.defaultAmountMinor != null
          ? _formatAmount(initial!.defaultAmountMinor!)
          : '',
    );
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
    final categoryType = _categoryTypeForType(_type);
    final categoriesAsync = categoryType != null
        ? ref.watch(categoriesByTypeProvider(categoryType))
        : const AsyncValue<List<Category>>.data(<Category>[]);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.initial == null ? 'Новый шаблон' : 'Редактирование шаблона',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Расход')),
              ButtonSegment(value: 'income', label: Text('Доход')),
              ButtonSegment(value: 'saving', label: Text('Сбережение')),
            ],
            selected: {_type},
            onSelectionChanged: (values) {
              if (values.isEmpty) {
                return;
              }
              setState(() {
                _type = values.first;
                _categoryId = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите название';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return const SizedBox.shrink();
              }
              return DropdownButtonFormField<int?>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Категория (опц.)'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Без категории'),
                  ),
                  for (final category in categories)
                    DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Не удалось загрузить категории: $error'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Сумма по умолчанию (опц.)',
              prefixText: '₽ ',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Примечание'),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    final repo = ref.read(plannedMasterRepoProvider);
    final title = _titleController.text.trim();
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final amountText = _amountController.text.trim();
    final amountMinor = amountText.isEmpty
        ? null
        : (_parseAmount(amountText) * 100).round();

    setState(() => _isSaving = true);
    try {
      final initial = widget.initial;
      var changed = false;
      if (initial == null) {
        await repo.create(
          type: _type,
          title: title,
          defaultAmountMinor: amountMinor,
          categoryId: _categoryId,
          note: note,
        );
        changed = true;
      } else {
        final id = initial.id;
        if (id != null) {
          changed = await repo.update(
            id,
            type: _type,
            title: title,
            defaultAmountMinor: amountMinor,
            categoryId: _categoryId,
            note: note,
          );
        }
      }
      if (!mounted) {
        return;
      }
      if (changed) {
        bumpDbTick(ref);
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  CategoryType? _categoryTypeForType(String type) {
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

  String _formatAmount(int amountMinor) {
    final value = amountMinor / 100;
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  double _parseAmount(String text) {
    final normalized = text.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }
}
