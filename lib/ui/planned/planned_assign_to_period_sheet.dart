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

Future<bool?> showPlannedAssignToPeriodSheet(
  BuildContext context, {
  required PlannedMaster master,
  TransactionRecord? initial,
}) {
  return showModalBottomSheet<bool>(
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
        child: _PlannedAssignToPeriodForm(
          master: master,
          initial: initial,
        ),
      );
    },
  );
}

class _PlannedAssignToPeriodForm extends ConsumerStatefulWidget {
  const _PlannedAssignToPeriodForm({
    required this.master,
    this.initial,
  });

  final PlannedMaster master;
  final TransactionRecord? initial;

  @override
  ConsumerState<_PlannedAssignToPeriodForm> createState() =>
      _PlannedAssignToPeriodFormState();
}

class _PlannedAssignToPeriodFormState
    extends ConsumerState<_PlannedAssignToPeriodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
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
    final initial = widget.initial;
    final master = widget.master;
    final bounds = ref.read(periodBoundsProvider);
    final defaultDate = _clampDate(initial?.date ?? bounds.$1, bounds.$1, bounds.$2);
    _selectedDate = defaultDate;
    _categoryId = initial?.categoryId ?? master.categoryId;
    _accountId = initial?.accountId;
    _necessityId = initial?.necessityId;
    _included = initial?.includedInPeriod ?? false;
    if (_accountId != null) {
      _accountInitialized = true;
    }
    final amountMinor = initial?.amountMinor ?? master.defaultAmountMinor;
    _amountController = TextEditingController(
      text: amountMinor != null ? _formatAmount(amountMinor) : '',
    );

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
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final master = widget.master;
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
            'Назначить «${master.title}»',
            style: Theme.of(context).textTheme.titleMedium,
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
                      style: Theme.of(context).textTheme.titleMedium,
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
          categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return const Text(
                  'Нет доступных категорий. Добавьте их в настройках.',
                  style: TextStyle(color: Colors.redAccent),
                );
              }
              return DropdownButtonFormField<int>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: [
                  for (final category in categories)
                    DropdownMenuItem<int>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
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
                          ChoiceChip(
                            label: Text(label.name),
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
              return DropdownButtonFormField<int>(
                value: _accountId,
                decoration: const InputDecoration(labelText: 'Счёт'),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem<int>(
                      value: account.id,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) => value == null ? 'Выберите счёт' : null,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Не удалось загрузить счета: $error'),
          ),
          const SizedBox(height: 12),
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
                lastDate: bounds.$2.subtract(const Duration(days: 1)),
              );
              if (picked != null && mounted) {
                setState(() => _selectedDate = picked);
              }
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _included,
            onChanged: (value) => setState(() => _included = value ?? false),
            title: const Text('Показать на Главной'),
          ),
          const SizedBox(height: 16),
          Row(
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

    final master = widget.master;
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

    setState(() => _isSaving = true);
    try {
      final initial = widget.initial;
      if (initial == null) {
        String? necessityLabel;
        int? necessityId;
        if (master.type == 'expense' && _necessityId != null) {
          final labels =
              ref.read(necessityLabelsFutureProvider).value ?? const [];
          for (final label in labels) {
            if (label.id == _necessityId) {
              necessityLabel = label.name;
              necessityId = label.id;
              break;
            }
          }
        }
        await repo.createPlannedInstance(
          plannedId: plannedId,
          type: master.type,
          accountId: accountId,
          amountMinor: amountMinor,
          date: _selectedDate,
          categoryId: categoryId,
          necessityId: necessityId,
          necessityLabel: necessityLabel,
          includedInPeriod: _included,
        );
      } else {
        final updated = initial.copyWith(
          amountMinor: amountMinor,
          categoryId: categoryId,
          accountId: accountId,
          date: _selectedDate,
          includedInPeriod: _included,
          necessityId: master.type == 'expense' ? _necessityId : null,
          necessityLabel: master.type == 'expense'
              ? _resolveNecessityLabel(_necessityId)
              : null,
        );
        await repo.update(updated, includedInPeriod: _included);
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

  String? _resolveNecessityLabel(int? id) {
    if (id == null) {
      return null;
    }
    final labels = ref.read(necessityLabelsFutureProvider).value ?? const [];
    for (final label in labels) {
      if (label.id == id) {
        return label.name;
      }
    }
    return null;
  }
}
