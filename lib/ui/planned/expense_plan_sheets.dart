import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
import '../../data/repositories/planned_master_repository.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../state/planned_providers.dart';
import '../../utils/color_hex.dart';
import '../../utils/plan_formatting.dart';
import '../../utils/period_utils.dart';
import '../settings/necessity_settings_screen.dart';

enum ExpensePlanResult { none, created, assigned }

enum _ExpensePlanEntryAction { fromMaster, newPlan }

Future<ExpensePlanResult> showPlanExpenseAddEntry(
  BuildContext context,
  PeriodRef period,
) async {
  final action = await showModalBottomSheet<_ExpensePlanEntryAction>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      final theme = Theme.of(modalContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 24),
              Text(
                'Добавление плана',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.folder_shared_outlined),
                label: const Text('Из общего плана'),
                onPressed: () {
                  Navigator.of(modalContext)
                      .pop(_ExpensePlanEntryAction.fromMaster);
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.flash_on_outlined),
                label: const Text('Новый план'),
                onPressed: () {
                  Navigator.of(modalContext)
                      .pop(_ExpensePlanEntryAction.newPlan);
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  if (action == null) {
    return ExpensePlanResult.none;
  }

  switch (action) {
    case _ExpensePlanEntryAction.newPlan:
      final created = await showQuickAddExpensePlanSheet(context, period);
      return created ? ExpensePlanResult.created : ExpensePlanResult.none;
    case _ExpensePlanEntryAction.fromMaster:
      final assigned = await showSelectFromMasterSheet(context, period);
      return assigned ? ExpensePlanResult.assigned : ExpensePlanResult.none;
  }
}

Future<bool> showQuickAddExpensePlanSheet(
  BuildContext context,
  PeriodRef period,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      final viewInsets = MediaQuery.of(modalContext).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: _QuickAddExpensePlanForm(period: period),
      );
    },
  ).then((value) => value ?? false);
}

class _QuickAddExpensePlanForm extends ConsumerStatefulWidget {
  const _QuickAddExpensePlanForm({required this.period});

  final PeriodRef period;

  @override
  ConsumerState<_QuickAddExpensePlanForm> createState() =>
      _QuickAddExpensePlanFormState();
}

class _QuickAddExpensePlanFormState
    extends ConsumerState<_QuickAddExpensePlanForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  int? _categoryId;
  int? _necessityId;
  bool _include = false;
  bool _isSaving = false;
  bool _restoredFromStorage = false;

  static const _storageIdentifier = '_quickAddExpensePlanForm';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _amountController = TextEditingController();
    _noteController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoredFromStorage) {
      _restoredFromStorage = true;
      _restoreFormStateFromPageStorage();
    }
  }

  @override
  void dispose() {
    _clearStoredFormState();
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(
      categoriesByTypeProvider(CategoryType.expense),
    );
    final necessityLabelsAsync = ref.watch(necessityLabelsFutureProvider);

    final categories = categoriesAsync.maybeWhen<List<Category>>(
      data: (items) {
        final filtered = [
          for (final item in items)
            if (!item.isGroup && !item.isArchived && item.id != null) item,
        ];
        filtered
            .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (_categoryId == null && filtered.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _categoryId = filtered.first.id;
            });
          });
        }
        return filtered;
      },
      orElse: () => const <Category>[],
    );

    final canSubmit =
        !_isSaving && _categoryId != null && _necessityId != null && categories.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
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
                  'Новый план расхода',
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
                categoriesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Не удалось загрузить категории: $error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  data: (_) {
                    if (categories.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Добавьте категорию расходов, чтобы создать план.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }
                    return DropdownButtonFormField<int>(
                      value: _categoryId,
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
                              setState(() => _categoryId = value);
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
                    );
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
                    _RublesInputFormatter(),
                  ],
                  validator: (value) {
                    final raw = value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
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
                const SizedBox(height: 12),
                necessityLabelsAsync.when(
                  data: (labels) {
                    if (labels.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Создайте ярлык критичности в настройках.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed:
                                  _isSaving ? null : _openNecessitySettings,
                              icon: const Icon(Icons.add),
                              label: const Text('Создать критичность'),
                            ),
                          ],
                        ),
                      );
                    }
                    final sorted = [...labels]
                      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                    if (_necessityId == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _necessityId = sorted.first.id;
                        });
                      });
                    }
                    return DropdownButtonFormField<int>(
                      value: _necessityId,
                      items: [
                        for (final label in sorted)
                          DropdownMenuItem<int>(
                            value: label.id,
                            child: Row(
                              children: [
                                _NecessityColorBadge(
                                  color: hexToColor(label.color),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(label.name)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() => _necessityId = value);
                            },
                      decoration: const InputDecoration(
                        labelText: 'Критичность/необходимость',
                      ),
                      validator: (value) {
                        if (value == null) {
                          return 'Укажите критичность';
                        }
                        return null;
                      },
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
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _include,
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() => _include = value ?? false);
                        },
                  title: const Text('Учитывать в расчёте'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Заметка (опционально)',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.08),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              TextButton(
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: canSubmit ? _handleSubmit : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openNecessitySettings() async {
    _saveFormStateToPageStorage();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NecessitySettingsScreen(),
      ),
    );
    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }

  void _saveFormStateToPageStorage() {
    final bucket = PageStorage.maybeOf(context);
    if (bucket == null) {
      return;
    }
    bucket.writeState(
      context,
      {
        'title': _titleController.text,
        'amount': _amountController.text,
        'note': _noteController.text,
        'categoryId': _categoryId,
        'necessityId': _necessityId,
        'include': _include,
      },
      identifier: _storageIdentifier,
    );
  }

  void _restoreFormStateFromPageStorage() {
    final bucket = PageStorage.maybeOf(context);
    if (bucket == null) {
      return;
    }
    final stored = bucket.readState(
      context,
      identifier: _storageIdentifier,
    );
    if (stored is! Map) {
      return;
    }
    final restored = Map<String, Object?>.from(stored as Map);
    _titleController.text = (restored['title'] as String?) ?? '';
    _amountController.text = (restored['amount'] as String?) ?? '';
    _noteController.text = (restored['note'] as String?) ?? '';
    _categoryId = restored['categoryId'] as int?;
    _necessityId = restored['necessityId'] as int?;
    _include = restored['include'] as bool? ?? false;
  }

  void _clearStoredFormState() {
    final bucket = PageStorage.maybeOf(context);
    if (bucket == null) {
      return;
    }
    bucket.writeState(
      context,
      null,
      identifier: _storageIdentifier,
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final categoryId = _categoryId;
    final necessityId = _necessityId;
    if (categoryId == null || necessityId == null) {
      return;
    }
    final title = _titleController.text.trim();
    final rawAmount = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amountRub = int.tryParse(rawAmount);
    if (amountRub == null || amountRub <= 0) {
      return;
    }
    final noteText = _noteController.text.trim();
    final note = noteText.isEmpty ? null : noteText;

    setState(() => _isSaving = true);
    try {
      final facade = ref.read(plannedFacadeProvider);
      await facade.createMasterAndAssignToCurrentPeriod(
        type: 'expense',
        title: title,
        categoryId: categoryId,
        amountMinor: amountRub * 100,
        period: widget.period,
        includedInPeriod: _include,
        necessityId: necessityId,
        note: note,
        reuseExisting: true,
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

class _NecessityColorBadge extends StatelessWidget {
  const _NecessityColorBadge({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = color ?? cs.surfaceVariant;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: resolved,
        shape: BoxShape.circle,
        border: Border.all(
          color: color == null ? cs.outlineVariant : Colors.transparent,
        ),
      ),
      child: color == null
          ? Icon(
              Icons.block,
              size: 12,
              color: cs.onSurfaceVariant,
            )
          : null,
    );
  }
}

Future<bool> showSelectFromMasterSheet(
  BuildContext context,
  PeriodRef period,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      final viewInsets = MediaQuery.of(modalContext).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: _SelectFromMasterSheet(period: period),
      );
    },
  ).then((value) => value ?? false);
}

class _SelectFromMasterSheet extends ConsumerStatefulWidget {
  const _SelectFromMasterSheet({required this.period});

  final PeriodRef period;

  @override
  ConsumerState<_SelectFromMasterSheet> createState() =>
      _SelectFromMasterSheetState();
}

class _SelectFromMasterSheetState
    extends ConsumerState<_SelectFromMasterSheet> {
  ExpenseMasterFilters _filters = const ExpenseMasterFilters();
  bool _showSearch = false;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(
      categoriesByTypeProvider(CategoryType.expense),
    );
    final necessityLabelsAsync = ref.watch(necessityLabelsFutureProvider);
    final categoriesMapAsync = ref.watch(categoriesMapProvider);
    final filters = _filters;
    final mastersAsync = ref.watch(
      availableExpenseMastersProvider((widget.period, filters)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                'Выберите план из общего списка',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildFiltersRow(
                context,
                categoriesAsync: categoriesAsync,
                necessityAsync: necessityLabelsAsync,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: mastersAsync.when(
            data: (masters) {
              if (masters.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Нет подходящих планов. Убедитесь, что план не архивирован и не назначен.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final categoriesMap =
                  categoriesMapAsync.value ?? const <int, Category>{};
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  final master = masters[index];
                  final categoryName = master.categoryId != null
                      ? categoriesMap[master.categoryId!]?.name
                      : null;
                  final amountMinor = master.defaultAmountMinor;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      oneLinePlan(
                        master.title,
                        amountMinor,
                        master.necessityName,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      categoryName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: OutlinedButton(
                      onPressed: amountMinor == null || master.categoryId == null
                          ? null
                          : () => _handleAssign(master),
                      child: const Text('Назначить'),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemCount: masters.length,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Не удалось загрузить планы: $error'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersRow(
    BuildContext context, {
    required AsyncValue<List<Category>> categoriesAsync,
    required AsyncValue<List<necessity_repo.NecessityLabel>> necessityAsync,
  }) {
    final theme = Theme.of(context);
    final filters = _filters;
    final isSearchVisible = _showSearch;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: isSearchVisible
          ? Row(
              key: const ValueKey('search'),
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Поиск...',
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          setState(() {
                            _filters = filters.copyWith(search: value.trim());
                          });
                        },
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Закрыть поиск',
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _showSearch = false;
                      _filters = filters.copyWith(search: '');
                    });
                  },
                ),
              ],
            )
          : Row(
              key: const ValueKey('filters'),
              children: [
                Expanded(
                  child: categoriesAsync.maybeWhen<Widget>(
                    data: (categories) {
                      final filtered = [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Все категории'),
                        ),
                        ...categories
                            .where((cat) => !cat.isGroup && !cat.isArchived)
                            .map(
                              (cat) => DropdownMenuItem<int?>(
                                value: cat.id,
                                child: Text(cat.name),
                              ),
                            ),
                      ];
                      return DropdownButton<int?>(
                        value: filters.categoryId,
                        isExpanded: true,
                        onChanged: (value) {
                          setState(() {
                            _filters = filters.copyWith(categoryId: value);
                          });
                        },
                        items: filtered,
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: necessityAsync.maybeWhen<Widget>(
                    data: (labels) {
                      final items = [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Все критичности'),
                        ),
                        ...labels.map(
                          (label) => DropdownMenuItem<int?>(
                            value: label.id,
                            child: Text(label.name),
                          ),
                        ),
                      ];
                      return DropdownButton<int?>(
                        value: filters.necessityId,
                        isExpanded: true,
                        onChanged: (value) {
                          setState(() {
                            _filters =
                                filters.copyWith(necessityId: value as int?);
                          });
                        },
                        items: items,
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
                IconButton(
                  tooltip: filters.sortDesc
                      ? 'Сортировка по сумме (по убыванию)'
                      : 'Сортировка по сумме (по возрастанию)',
                  icon: Icon(
                    filters.sortDesc
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                  ),
                  onPressed: () {
                    setState(() {
                      _filters =
                          filters.copyWith(sortDesc: !filters.sortDesc);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _showSearch = true;
                      _searchController.text = filters.search;
                    });
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _handleAssign(PlannedMasterView master) async {
    final categoryId = master.categoryId;
    final amountMinor = master.defaultAmountMinor;
    if (categoryId == null || amountMinor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У плана не задана сумма или категория')),
      );
      return;
    }
    final result = await showModalBottomSheet<_AssignConfirmationResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        final viewInsets = MediaQuery.of(modalContext).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: _AssignConfirmationSheet(master: master),
        );
      },
    );
    if (result == null) {
      return;
    }
    try {
      final transactionsRepo = ref.read(transactionsRepoProvider);
      final entry = await ref.read(periodEntryProvider(widget.period).future);
      await transactionsRepo.assignMasterToPeriod(
        masterId: master.id,
        period: widget.period,
        start: entry.start,
        endExclusive: entry.endExclusive,
        categoryId: categoryId,
        amountMinor: amountMinor,
        included: result.include,
        necessityId: master.necessityId,
        note: result.note,
        accountId: result.accountId,
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
        SnackBar(content: Text('Не удалось назначить план: $error')),
      );
    }
  }
}

class _AssignConfirmationResult {
  const _AssignConfirmationResult({
    required this.include,
    required this.accountId,
    this.note,
  });

  final bool include;
  final int accountId;
  final String? note;
}

class _AssignConfirmationSheet extends ConsumerStatefulWidget {
  const _AssignConfirmationSheet({required this.master});

  final PlannedMasterView master;

  @override
  ConsumerState<_AssignConfirmationSheet> createState() =>
      _AssignConfirmationSheetState();
}

class _AssignConfirmationSheetState
    extends ConsumerState<_AssignConfirmationSheet> {
  late final TextEditingController _noteController;
  bool _include = false;
  int? _accountId;
  bool _accountInitialized = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AssignConfirmationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.master.id != widget.master.id) {
      _accountInitialized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountsAsync = ref.watch(accountsDbProvider);

    accountsAsync.whenData((accounts) {
      if (_accountInitialized || accounts.isEmpty) {
        return;
      }
      final defaultAccount = accounts.firstWhere(
        (account) => account.name.trim().toLowerCase() == 'карта',
        orElse: () => accounts.first,
      );
      if (defaultAccount.id == null) {
        return;
      }
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            'Назначение плана',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            oneLinePlan(
              widget.master.title,
              widget.master.defaultAmountMinor,
              widget.master.necessityName,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          accountsAsync.when(
            data: (accounts) {
              if (accounts.isEmpty) {
                return const Text(
                  'Нет доступных счетов. Добавьте счёт в настройках.',
                );
              }
              return DropdownButtonFormField<int>(
                key: const Key('assign_plan_account'),
                value: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Счёт',
                ),
                items: [
                  for (final Account account in accounts)
                    if (account.id != null)
                      DropdownMenuItem<int>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Не удалось загрузить счета: $error'),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _include,
            onChanged: (value) {
              setState(() => _include = value ?? false);
            },
            title: const Text('Учитывать в расчёте'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Заметка (опционально)',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _accountId == null
                    ? null
                    : () {
                        final note = _noteController.text.trim();
                        Navigator.of(context).pop(
                          _AssignConfirmationResult(
                            include: _include,
                            accountId: _accountId!,
                            note: note.isEmpty ? null : note,
                          ),
                        );
                      },
                child: const Text('Назначить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RublesInputFormatter extends TextInputFormatter {
  _RublesInputFormatter() : _formatter = NumberFormat.decimalPattern('ru_RU');

  final NumberFormat _formatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = _formatter.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
