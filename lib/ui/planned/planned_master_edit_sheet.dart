import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../data/repositories/planned_master_repository.dart';
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../utils/app_exceptions.dart';
import '../../utils/formatting.dart';
import '../../utils/period_utils.dart';
import '../widgets/necessity_choice_chip.dart';
import 'planned_assign_to_period_sheet.dart';

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
  int? _selectedNecessityId;
  bool _isSaving = false;
  bool _isAmountValid = false;
  bool _isDirty = false;

  bool get _isEditMode => widget.initial != null;
  bool get _isExpense => _type == 'expense';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? 'expense';
    _categoryId = initial?.categoryId;
    _selectedNecessityId = initial?.necessityId;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _noteController = TextEditingController(text: initial?.note ?? '');
    _amountController = TextEditingController(
      text: initial?.defaultAmountMinor != null
          ? _formatAmount(initial!.defaultAmountMinor!)
          : '',
    );
    _isAmountValid = _hasValidAmount(_amountController.text);
    _titleController.addListener(_handleTextChanged);
    _noteController.addListener(_handleTextChanged);
    _amountController.addListener(_handleAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateDirty();
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_handleAmountChanged);
    _titleController.removeListener(_handleTextChanged);
    _noteController.removeListener(_handleTextChanged);
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryType = _categoryTypeForType(_type);
    final categoriesAsync = !_isEditMode && categoryType != null
        ? ref.watch(categoriesByTypeProvider(categoryType))
        : const AsyncValue<List<Category>>.data(<Category>[]);
    final necessityLabelsAsync = _isExpense
        ? ref.watch(necessityLabelsFutureProvider)
        : const AsyncValue<List<necessity_repo.NecessityLabel>>.data(
            <necessity_repo.NecessityLabel>[],
          );
    final masterId = widget.initial?.id;
    final assignmentsAsync = masterId == null
        ? const AsyncValue<List<TransactionRecord>>.data(<TransactionRecord>[])
        : ref.watch(plannedInstancesByMasterProvider(masterId));
    final anchors = ref.watch(anchorDaysProvider);

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
            _isEditMode ? 'Редактирование шаблона' : 'Новый шаблон',
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
                if (!_isEditMode) {
                  _categoryId = null;
                }
                if (_type != 'expense') {
                  _selectedNecessityId = null;
                }
              });
              _updateDirty();
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
          if (!_isEditMode) ...[
            const SizedBox(height: 12),
            categoriesAsync.when(
              data: (categories) {
                if (categories.isEmpty) {
                  return const SizedBox.shrink();
                }
                return DropdownButtonFormField<int?>(
                  value: _categoryId,
                  decoration:
                      const InputDecoration(labelText: 'Категория (опц.)'),
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
                  onChanged: (value) {
                    setState(() => _categoryId = value);
                    _updateDirty();
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Text('Не удалось загрузить категории: $error'),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Сумма ₽',
              prefixText: '₽ ',
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final text = value?.trim();
              if (text == null || text.isEmpty) {
                return 'Введите сумму';
              }
              final parsed = double.tryParse(text.replaceAll(',', '.'));
              if (parsed == null) {
                return 'Некорректная сумма';
              }
              if (parsed <= 0) {
                return 'Сумма должна быть больше 0';
              }
              return null;
            },
          ),
          if (_isExpense) ...[
            const SizedBox(height: 12),
            necessityLabelsAsync.when(
              data: (labels) => _buildNecessitySelector(context, labels),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Text('Не удалось загрузить критичность: $error'),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Заметка'),
            maxLines: 3,
          ),
          if (_isEditMode && masterId != null) ...[
            const SizedBox(height: 24),
            Text(
              'Назначения по периодам',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _buildAssignmentsSection(context, assignmentsAsync, anchors),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving || !_isAmountValid ||
                          (_isEditMode && !_isDirty)
                      ? null
                      : _submit,
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
    final noteText = _noteController.text.trim();
    final sanitizedNote = noteText.isEmpty ? null : noteText;
    final amountText = _amountController.text.trim();
    final amountMinor = (_parseAmount(amountText) * 100).round();
    final necessityId = _isExpense ? _selectedNecessityId : null;

    setState(() => _isSaving = true);
    try {
      final initial = widget.initial;
      if (initial == null) {
        await repo.create(
          type: _type,
          title: title,
          defaultAmountMinor: amountMinor,
          categoryId: _categoryId,
          note: sanitizedNote,
        );
        if (!mounted) {
          return;
        }
        bumpDbTick(ref);
        _showSnack('Сохранено');
        Navigator.of(context).pop(true);
        return;
      }
      final id = initial.id;
      if (id == null) {
        return;
      }
      final rows = await repo.updateMaster(
        id: id,
        title: title,
        amountMinor: amountMinor,
        necessityId: necessityId,
        note: sanitizedNote,
        type: _type != initial.type ? _type : null,
      );
      if (!mounted) {
        return;
      }
      if (rows > 0) {
        bumpDbTick(ref);
        _showSnack('Сохранено');
        Navigator.of(context).pop(true);
      }
    } on ControlledOperationException catch (error) {
      if (!mounted) {
        return;
      }
      final theme = Theme.of(context);
      _showSnack(
        error.message,
        background: theme.colorScheme.surfaceVariant,
        textColor: theme.colorScheme.onSurfaceVariant,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Не удалось сохранить изменения: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _handleAmountChanged() {
    final next = _hasValidAmount(_amountController.text);
    if (next != _isAmountValid) {
      setState(() {
        _isAmountValid = next;
      });
    }
    _updateDirty();
  }

  void _handleTextChanged() {
    _updateDirty();
  }

  Widget _buildNecessitySelector(
    BuildContext context,
    List<necessity_repo.NecessityLabel> labels,
  ) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Критичность/необходимость',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Без метки'),
              selected: _selectedNecessityId == null,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedNecessityId = null);
                  _updateDirty();
                }
              },
            ),
            for (final label in labels)
              NecessityChoiceChip(
                label: label,
                selected: label.id == _selectedNecessityId,
                onSelected: (value) {
                  if (!value) {
                    return;
                  }
                  setState(() => _selectedNecessityId = label.id);
                  _updateDirty();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssignmentsSection(
    BuildContext context,
    AsyncValue<List<TransactionRecord>> assignments,
    (int, int) anchors,
  ) {
    return assignments.when(
      data: (records) {
        if (records.isEmpty) {
          return const Text('Нет назначений для этого шаблона.');
        }
        return Column(
          children: [
            for (var i = 0; i < records.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == records.length - 1 ? 0 : 12),
                child: _buildAssignmentCard(context, records[i], anchors),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Не удалось загрузить назначения: $error'),
    );
  }

  Widget _buildAssignmentCard(
    BuildContext context,
    TransactionRecord record,
    (int, int) anchors,
  ) {
    final period = periodRefForDate(record.date, anchors.$1, anchors.$2);
    final bounds = period.bounds(anchors.$1, anchors.$2);
    final label = _formatPeriodLabel(bounds.start, bounds.endExclusive);
    final amountLabel = formatCurrencyMinor(record.amountMinor);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: record.includedInPeriod,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(label),
            subtitle: Text('Сумма: $amountLabel'),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _handleToggleInstance(record, value, anchors);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _handleChangePeriod(record),
                  icon: const Icon(Icons.event_repeat_outlined),
                  label: const Text('Изменить период'),
                ),
                TextButton.icon(
                  onPressed: () => _handleDeleteInstance(record),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить из периода'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToggleInstance(
    TransactionRecord record,
    bool value,
    (int, int) anchors,
  ) async {
    final masterId = record.plannedId;
    if (masterId == null) {
      return;
    }
    final period = periodRefForDate(record.date, anchors.$1, anchors.$2);
    final bounds = period.bounds(anchors.$1, anchors.$2);
    try {
      await ref.read(plannedInstancesRepoProvider).upsertInstance(
            masterId: masterId,
            start: bounds.start,
            endExclusive: bounds.endExclusive,
            includedInPeriod: value,
            necessityId: record.type == TransactionType.expense
                ? record.necessityId
                : null,
            categoryId: record.categoryId,
            amountMinor: record.amountMinor,
            note: record.note,
          );
      if (!mounted) {
        return;
      }
      bumpDbTick(ref);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Не удалось обновить назначение: $error');
    }
  }

  Future<void> _handleChangePeriod(TransactionRecord record) async {
    final master = widget.initial;
    if (master == null) {
      return;
    }
    final anchors = ref.read(anchorDaysProvider);
    final period = periodRefForDate(record.date, anchors.$1, anchors.$2);
    await showPlannedAssignToPeriodSheet(
      context,
      master: master,
      initialPeriod: period,
      initialRecord: record,
    );
  }

  Future<void> _handleDeleteInstance(TransactionRecord record) async {
    final id = record.id;
    if (id == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить назначение?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    try {
      await ref.read(transactionsRepoProvider).delete(id);
      if (!mounted) {
        return;
      }
      bumpDbTick(ref);
      _showSnack('Удалено');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Не удалось удалить: $error');
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
    return double.parse(normalized);
  }

  bool _hasValidAmount(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return false;
    }
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) {
      return false;
    }
    return parsed > 0;
  }

  int? _parseAmountMinorOrNull(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) {
      return null;
    }
    return (parsed * 100).round();
  }

  void _updateDirty() {
    final amountMinor = _parseAmountMinorOrNull(_amountController.text);
    final title = _titleController.text.trim();
    final noteText = _noteController.text.trim();
    final sanitizedNote = noteText.isEmpty ? null : noteText;
    final necessityId = _isExpense ? _selectedNecessityId : null;

    bool dirty;
    if (!_isAmountValid || amountMinor == null) {
      dirty = false;
    } else if (!_isEditMode) {
      dirty = title.isNotEmpty && amountMinor > 0;
    } else {
      final initial = widget.initial!;
      final initialNote =
          (initial.note?.trim().isEmpty ?? true) ? null : initial.note!.trim();
      dirty = title != initial.title.trim() ||
          amountMinor != (initial.defaultAmountMinor ?? 0) ||
          sanitizedNote != initialNote ||
          necessityId != initial.necessityId ||
          _type != initial.type;
    }

    if (dirty != _isDirty) {
      setState(() => _isDirty = dirty);
    }
  }

  String _formatPeriodLabel(DateTime start, DateTime endExclusive) {
    const months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    final month = months[start.month - 1];
    final endInclusive = endExclusive.subtract(const Duration(days: 1));
    return '$month ${start.day}–${endInclusive.day}';
  }

  void _showSnack(String message, {Color? background, Color? textColor}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: textColor == null
              ? null
              : TextStyle(color: textColor),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
