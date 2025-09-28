import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../data/repositories/planned_master_repository.dart';
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../utils/formatting.dart';
import '../../utils/period_utils.dart';
import '../widgets/necessity_choice_chip.dart';

Future<bool?> showPlannedAssignToPeriodSheet(
  BuildContext context, {
  required PlannedMaster master,
  PeriodRef? initialPeriod,
  TransactionRecord? initialRecord,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      final viewInsets = MediaQuery.of(modalContext).viewInsets;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: viewInsets.bottom,
          ),
          child: _PlannedAssignToPeriodForm(
            master: master,
            initialPeriod: initialPeriod,
            initialRecord: initialRecord,
          ),
        ),
      );
    },
  );
}

class _PlannedAssignToPeriodForm extends ConsumerStatefulWidget {
  const _PlannedAssignToPeriodForm({
    required this.master,
    this.initialPeriod,
    this.initialRecord,
  });

  final PlannedMaster master;
  final PeriodRef? initialPeriod;
  final TransactionRecord? initialRecord;

  @override
  ConsumerState<_PlannedAssignToPeriodForm> createState() =>
      _PlannedAssignToPeriodFormState();
}

class _PlannedAssignToPeriodFormState
    extends ConsumerState<_PlannedAssignToPeriodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late DateTime _selectedDate;
  int? _categoryId;
  int? _accountId;
  int? _necessityId;
  bool _included = false;
  bool _isSaving = false;
  bool _accountInitialized = false;

  @override
  void initState() {
    super.initState();
    final master = widget.master;
    final initialPeriod = widget.initialPeriod;
    if (initialPeriod != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref.read(selectedPeriodRefProvider.notifier).state = initialPeriod;
      });
    }
    final existing = widget.initialRecord;
    if (existing != null) {
      _selectedDate = existing.date;
      _categoryId = existing.categoryId;
      _accountId = existing.accountId;
      _necessityId = existing.necessityId;
      _included = existing.includedInPeriod;
      _accountInitialized = _accountId != null;
      _amountController = TextEditingController(
        text: _formatAmount(existing.amountMinor),
      );
      _noteController = TextEditingController(text: existing.note ?? '');
    } else {
      final bounds = ref.read(periodBoundsProvider);
      final defaultDate = _clampDate(bounds.$1, bounds.$1, bounds.$2);
      _selectedDate = defaultDate;
      _categoryId = master.categoryId;
      _accountId = null;
      _necessityId = null;
      _included = false;
      _accountInitialized = _accountId != null;
      final amountMinor = master.defaultAmountMinor;
      _amountController = TextEditingController(
        text: amountMinor != null ? _formatAmount(amountMinor) : '',
      );
      _noteController = TextEditingController(text: master.note ?? '');
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final master = widget.master;
    final existing = widget.initialRecord;
    ref.listen<(DateTime, DateTime)>(periodBoundsProvider, (previous, next) {
      final start = next.$1;
      final end = next.$2;
      if (!mounted) {
        return;
      }
      if (_selectedDate.isBefore(start) || !_selectedDate.isBefore(end)) {
        setState(() {
          _selectedDate = start;
        });
      }
    });
    final bounds = ref.watch(periodBoundsProvider);
    final periodLabel = ref.watch(periodLabelProvider);
    final nav = ref.watch(periodNavProvider);
    final categoryType = _categoryTypeForType(master.type);
    final categoriesAsync = categoryType != null
        ? ref.watch(categoriesByTypeProvider(categoryType))
        : const AsyncValue<List<Category>>.data(<Category>[]);
    final accountsAsync = ref.watch(accountsDbProvider);
    final necessityLabelsAsync = master.type == 'expense'
        ? ref.watch(necessityLabelsFutureProvider)
        : const AsyncValue<List<necessity_repo.NecessityLabel>>.data(
            <necessity_repo.NecessityLabel>[],
          );

    accountsAsync.whenData((accounts) {
      if (_accountInitialized || accounts.isEmpty) {
        return;
      }
      final defaultAccount = accounts.firstWhere(
        (acc) => acc.name.trim().toLowerCase() == 'карта',
        orElse: () => accounts.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _accountId = defaultAccount.id;
          _accountInitialized = true;
        });
      });
    });

    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: 24 + viewInsets),
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
                        existing == null
                            ? 'Назначить «${master.title}»'
                            : 'Редактировать «${master.title}»',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              nav.prev();
                            },
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Период'),
                                Text(
                                  periodLabel,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              nav.next();
                            },
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Сумма',
              prefixText: '₽ ',
            ),
            validator: (value) {
              final text = value?.trim();
              if (text == null || text.isEmpty) {
                return 'Введите сумму';
              }
              final parsed = double.tryParse(text.replaceAll(',', '.'));
              if (parsed == null || parsed <= 0) {
                return 'Сумма должна быть больше 0';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Заметка',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return const Text(
                  'Нет доступных категорий. Добавьте их в настройках.',
                  style: TextStyle(color: Colors.redAccent),
                );
              }
              final selectedCategoryId = _categoryId;
              final items = <DropdownMenuItem<int>>[
                for (final category in categories)
                  DropdownMenuItem<int>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ];
              final hasSelectedCategory = selectedCategoryId != null &&
                  categories.any((category) => category.id == selectedCategoryId);
              if (selectedCategoryId != null && !hasSelectedCategory) {
                items.insert(
                  0,
                  DropdownMenuItem<int>(
                    value: selectedCategoryId,
                    child: Text('Категория #$selectedCategoryId (удалена)'),
                  ),
                );
              }
              return DropdownButtonFormField<int>(
                value: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: items,
                onChanged: (value) => setState(() => _categoryId = value),
                validator: (value) => value == null ? 'Выберите категорию' : null,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Не удалось загрузить категории: $error'),
          ),
          const SizedBox(height: 12),
          if (master.type == 'expense')
            necessityLabelsAsync.when(
              data: (labels) {
                if (labels.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Критичность/необходимость',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final label in labels)
                          NecessityChoiceChip(
                            label: label,
                            selected: label.id == _necessityId,
                            onSelected: (selected) {
                              setState(() {
                                _necessityId = selected ? label.id : null;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('Не удалось загрузить метки: $error'),
            ),
          const SizedBox(height: 12),
          accountsAsync.when(
            data: (accounts) {
              if (accounts.isEmpty) {
                return const Text('Добавьте счёт, чтобы продолжить.');
              }
              final selectedAccountId = _accountId;
              final items = <DropdownMenuItem<int>>[
                for (final account in accounts)
                  DropdownMenuItem<int>(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ];
              final hasSelectedAccount = selectedAccountId != null &&
                  accounts.any((account) => account.id == selectedAccountId);
              if (selectedAccountId != null && !hasSelectedAccount) {
                items.insert(
                  0,
                  DropdownMenuItem<int>(
                    value: selectedAccountId,
                    child: Text('Счёт #$selectedAccountId (удалён)'),
                  ),
                );
              }
              return DropdownButtonFormField<int>(
                value: selectedAccountId,
                decoration: const InputDecoration(labelText: 'Счёт'),
                items: items,
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) => value == null ? 'Выберите счёт' : null,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Не удалось загрузить счета: $error'),
          ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Дата'),
                        subtitle: Text(formatDate(_selectedDate)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: bounds.$1,
                            lastDate:
                                bounds.$2.subtract(const Duration(days: 1)),
                          );
                          if (picked != null && mounted) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _included,
                        onChanged: (value) =>
                            setState(() => _included = value ?? false),
                        title: const Text('Учитывать в расчётах'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final master = widget.master;
    final existing = widget.initialRecord;
    final repo = ref.read(transactionsRepoProvider);
    final plannedId = master.id;
    if (plannedId == null) {
      return;
    }
    final amountText = _amountController.text.trim();
    final amountMinor = (double.parse(amountText.replaceAll(',', '.')) * 100).round();
    final categoryId = _categoryId;
    final accountId = _accountId;
    if (categoryId == null || accountId == null) {
      return;
    }
    final note = _noteController.text.trim();
    final noteValue = note.isEmpty ? null : note;

    setState(() => _isSaving = true);
    try {
      List<necessity_repo.NecessityLabel> labels = const [];
      if (master.type == 'expense') {
        labels = await ref.read(necessityLabelsFutureProvider.future);
      }
      String? necessityLabel;
      int? necessityId;
      var criticality = existing?.criticality ?? 0;
      if (master.type == 'expense') {
        necessity_repo.NecessityLabel? match;
        for (final label in labels) {
          if (label.id == _necessityId) {
            match = label;
            break;
          }
        }
        if (match != null) {
          necessityLabel = match.name;
          necessityId = match.id;
          criticality = labels.indexOf(match);
        } else if (_necessityId == null) {
          necessityLabel = null;
          necessityId = null;
          criticality = 0;
        } else if (existing != null) {
          necessityLabel = existing.necessityLabel;
          necessityId = existing.necessityId;
          criticality = existing.criticality;
        }
      } else {
        necessityLabel = null;
        necessityId = null;
        criticality = 0;
      }

      if (existing == null) {
        await repo.createPlannedInstance(
          plannedId: plannedId,
          type: master.type,
          accountId: accountId,
          amountMinor: amountMinor,
          date: _selectedDate,
          categoryId: categoryId,
          note: noteValue,
          necessityId: necessityId,
          necessityLabel: necessityLabel,
          includedInPeriod: _included,
          criticality: criticality,
        );
      } else {
        final updated = existing.copyWith(
          accountId: accountId,
          categoryId: categoryId,
          amountMinor: amountMinor,
          date: _selectedDate,
          note: noteValue,
          includedInPeriod: _included,
          necessityId: necessityId,
          necessityLabel: necessityLabel,
          criticality: criticality,
        );
        await repo.update(updated);
      }
      if (!mounted) {
        return;
      }
      bumpDbTick(ref);
      Navigator.of(context).pop(true);
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

  DateTime _clampDate(DateTime value, DateTime start, DateTime endExclusive) {
    if (value.isBefore(start)) {
      return start;
    }
    if (!value.isBefore(endExclusive)) {
      return endExclusive.subtract(const Duration(days: 1));
    }
    return value;
  }

  String _formatAmount(int amountMinor) {
    final value = amountMinor / 100;
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}
