import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../state/app_providers.dart';
import '../../state/planned_providers.dart';

CategoryType _categoryTypeFor(PlannedType type) {
  switch (type) {
    case PlannedType.income:
      return CategoryType.income;
    case PlannedType.expense:
      return CategoryType.expense;
    case PlannedType.saving:
      return CategoryType.saving;
  }
}

TransactionType _transactionTypeFor(PlannedType type) {
  switch (type) {
    case PlannedType.income:
      return TransactionType.income;
    case PlannedType.expense:
      return TransactionType.expense;
    case PlannedType.saving:
      return TransactionType.saving;
  }
}

Future<void> showPlannedAddForm(
  BuildContext context,
  WidgetRef ref, {
  required PlannedType type,
  TransactionRecord? initialRecord,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
    ),
    builder: (modalContext) {
      final bottomInset = MediaQuery.of(modalContext).viewInsets.bottom;
      return SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16 + bottomInset),
          child: Consumer(
            builder: (context, formRef, __) {
              return _PlannedAddForm(
                type: type,
                ref: formRef,
                rootContext: context,
                initialRecord: initialRecord,
              );
            },
          ),
        ),
      );
    },
  );
}

class _PlannedAddForm extends StatefulWidget {
  const _PlannedAddForm({
    required this.type,
    required this.ref,
    required this.rootContext,
    this.initialRecord,
  });

  final PlannedType type;
  final WidgetRef ref;
  final BuildContext rootContext;
  final TransactionRecord? initialRecord;

  @override
  State<_PlannedAddForm> createState() => _PlannedAddFormState();
}

class _PlannedAddFormState extends State<_PlannedAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  int? get _editingId => widget.initialRecord?.id;

  late Future<List<Category>> _categoriesFuture;
  int? _selectedCategoryId;
  int _selectedCriticality = 0;
  String? _categoryError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial != null) {
      _nameController.text = initial.note ?? '';
      final initialAmount = initial.amountMinor / 100;
      _amountController.text = initialAmount == initialAmount.roundToDouble()
          ? initialAmount.toStringAsFixed(0)
          : initialAmount.toString();
      _selectedCategoryId = initial.categoryId;
      _selectedCriticality = initial.criticality;
    }
    final categoriesRepo = widget.ref.read(categoriesRepoProvider);
    _categoriesFuture = categoriesRepo.getByType(_categoryTypeFor(widget.type));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final necessityLabels = widget.ref.watch(necessityLabelsProvider);
    final selectedCriticality = necessityLabels.isEmpty
        ? -1
        : _selectedCriticality.clamp(0, necessityLabels.length - 1);

    return FutureBuilder<List<Category>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? <Category>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && categories.isEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
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
                  _titleForType(widget.type),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Наименование',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите наименование';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Сумма',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final text = value?.trim();
                    if (text == null || text.isEmpty) {
                      return 'Введите сумму';
                    }
                    final normalized = text.replaceAll(',', '.');
                    final parsed = double.tryParse(normalized);
                    if (parsed == null || parsed <= 0) {
                      return 'Сумма должна быть больше 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (categories.isEmpty)
                  const Text(
                    'Нет доступных категорий. Добавьте их в настройках.',
                    style: TextStyle(color: Colors.redAccent),
                  )
                else
                  DropdownButtonFormField<int>(
                    value: _selectedCategoryId,
                    decoration: InputDecoration(
                      labelText: 'Категория',
                      errorText: _categoryError,
                    ),
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategoryId = value;
                        _categoryError = null;
                      });
                    },
                  ),
                const SizedBox(height: 16),
                if (necessityLabels.isNotEmpty) ...[
                  Text(
                    'Критичность/необходимость',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < necessityLabels.length; i++)
                        ChoiceChip(
                          label: Text(necessityLabels[i]),
                          selected: selectedCriticality == i,
                          onSelected: (_) {
                            setState(() {
                              _selectedCriticality = i;
                            });
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: isLoading ? null : _submit,
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      setState(() {
        _categoryError = 'Выберите категорию';
      });
      return;
    }

    final title = _nameController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.parse(amountText);
    final amountMinor = (amount * 100).round();

    final labels = widget.ref.read(necessityLabelsProvider);
    String? necessityLabel;
    if (labels.isNotEmpty) {
      final index = _selectedCriticality.clamp(0, labels.length - 1);
      necessityLabel = labels[index];
      _selectedCriticality = index;
    }
    final accountId = await _resolveAccountId();
    final actions = widget.ref.read(plannedActionsProvider);

    final existing = widget.initialRecord;
    final record = TransactionRecord(
      id: existing?.id,
      accountId: existing?.accountId ?? accountId,
      categoryId: categoryId,
      type: _transactionTypeFor(widget.type),
      amountMinor: amountMinor,
      date: existing?.date ?? DateTime.now(),
      note: title,
      isPlanned: true,
      includedInPeriod: existing?.includedInPeriod ?? false,
      criticality: _selectedCriticality,
      necessityLabel: necessityLabel,
    );

    if (existing == null) {
      await actions.add(record);
    } else {
      await actions.update(record);
    }

    widget.ref.invalidate(plannedItemsByTypeProvider(widget.type));
    widget.ref.invalidate(plannedTotalByTypeProvider(widget.type));

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(widget.rootContext).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Добавлено' : 'Изменено'),
        ),
      );
    }
  }

  Future<int> _resolveAccountId() async {
    final accountsRepo = widget.ref.read(accountsRepoProvider);
    final accounts = await accountsRepo.getAll();
    if (accounts.isEmpty) {
      throw StateError('Нет доступных счетов для сохранения плана');
    }
    final preferred = accounts.firstWhere(
      (account) => account.name.trim().toLowerCase() == 'карта',
      orElse: () => accounts.first,
    );
    return preferred.id ?? accounts.first.id!;
  }

  String _titleForType(PlannedType type) {
    final base = switch (type) {
      PlannedType.income => 'доход',
      PlannedType.expense => 'расход',
      PlannedType.saving => 'сбережение',
    };
    return _editingId == null
        ? 'Добавить $base'
        : 'Редактировать $base';
  }
}
