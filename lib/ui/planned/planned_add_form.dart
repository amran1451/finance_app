import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../data/repositories/necessity_repository.dart';
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
  int? _selectedNecessityId;
  String? _legacyNecessityLabel;
  bool _legacyLabelResolved = false;
  bool _defaultLabelApplied = false;
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
      _selectedNecessityId = initial.necessityId;
      _legacyNecessityLabel = initial.necessityLabel;
      _legacyLabelResolved =
          _selectedNecessityId != null || _legacyNecessityLabel == null;
      _defaultLabelApplied = _selectedNecessityId != null;
    } else {
      _legacyLabelResolved = true;
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
    final necessityLabelsAsync = widget.ref.watch(necessityLabelsProvider);
    final necessityLabels =
        necessityLabelsAsync.value ?? <NecessityLabel>[];

    if (!_legacyLabelResolved &&
        _legacyNecessityLabel != null &&
        necessityLabels.isNotEmpty) {
      final match = _findLabelByName(necessityLabels, _legacyNecessityLabel!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _legacyLabelResolved = true;
          if (match != null) {
            _selectedNecessityId = match.id;
            _defaultLabelApplied = true;
          }
        });
      });
    }

    if (!_defaultLabelApplied && necessityLabels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          if (_selectedNecessityId == null && _legacyNecessityLabel == null) {
            _selectedNecessityId = necessityLabels.first.id;
            _legacyLabelResolved = true;
          }
          _defaultLabelApplied = true;
        });
      });
    }

    final selectedNecessityId = _selectedNecessityId;

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
                if (necessityLabelsAsync.isLoading && necessityLabels.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (necessityLabels.isNotEmpty) ...[
                  Text(
                    'Критичность/необходимость',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in necessityLabels)
                        ChoiceChip(
                          label: Text(label.name),
                          selected: label.id == selectedNecessityId,
                          onSelected: (_) {
                            setState(() {
                              _selectedNecessityId = label.id;
                              _legacyNecessityLabel = label.name;
                              _legacyLabelResolved = true;
                              _defaultLabelApplied = true;
                            });
                          },
                        ),
                    ],
                  ),
                  if (selectedNecessityId == null &&
                      _legacyLabelResolved &&
                      _legacyNecessityLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Метка "${_legacyNecessityLabel!}" недоступна. Выберите новую.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ]
                else if (necessityLabelsAsync.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Не удалось загрузить метки необходимости',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
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

    final labelsAsync = widget.ref.read(necessityLabelsProvider);
    final labels = labelsAsync.value ?? <NecessityLabel>[];
    NecessityLabel? selectedLabel;
    for (final label in labels) {
      if (label.id == _selectedNecessityId) {
        selectedLabel = label;
        break;
      }
    }
    final necessityLabel = selectedLabel?.name ?? _legacyNecessityLabel;
    final necessityId = selectedLabel?.id;
    final criticality = selectedLabel != null
        ? labels.indexOf(selectedLabel)
        : widget.initialRecord?.criticality ?? 0;

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
      criticality: criticality,
      necessityId: necessityId,
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

  NecessityLabel? _findLabelByName(
    List<NecessityLabel> labels,
    String name,
  ) {
    final normalized = name.trim().toLowerCase();
    for (final label in labels) {
      if (label.name.trim().toLowerCase() == normalized) {
        return label;
      }
    }
    return null;
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
