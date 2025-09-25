import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/models/transaction_record.dart';
import '../../data/repositories/necessity_repository.dart';
import '../../data/repositories/reason_repository.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/reason_providers.dart';
import '../../utils/category_type_extensions.dart';
import '../../utils/formatting.dart';
import '../../utils/color_hex.dart';
import '../../utils/date_format_short.dart';
import '../widgets/add_another_snack.dart';
import '../widgets/necessity_choice_chip.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  bool _asPlanned = false;
  bool _forcePlanned = false;
  int? _reasonId;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final entryState = ref.read(entryFlowControllerProvider);
    _forcePlanned = _shouldForcePlanned(entryState);
    _asPlanned = _forcePlanned && entryState.type == CategoryType.expense;
    _selectedDate = entryState.selectedDate;
  }

  bool _shouldForcePlanned(EntryFlowState state) {
    if (state.type != CategoryType.expense) {
      return false;
    }
    return state.attachToPlanned;
  }

  @override
  Widget build(BuildContext context) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final entrySelectedDate = entryState.selectedDate;
    if (_selectedDate == null || !_isSameDay(_selectedDate!, entrySelectedDate)) {
      _selectedDate = entrySelectedDate;
    }

    final operationKind = operationKindFromType(entryState.type);
    final isIncome = operationKind == OperationKind.income;
    final isExpense = operationKind == OperationKind.expense;
    final isSaving = operationKind == OperationKind.saving;
    final isQuickAddKind = isExpense || isIncome || isSaving;
    final isPlannedExpense = isExpense && (_forcePlanned || _asPlanned);
    final showPlanToggle = isExpense && !_forcePlanned;
    final showNecessitySection = isSaving || isPlannedExpense;
    final showReasonSection = isExpense && !isPlannedExpense;

    final AsyncValue<List<NecessityLabel>> necessityLabelsAsync =
        showNecessitySection
            ? ref.watch(necessityLabelsFutureProvider)
            : const AsyncValue<List<NecessityLabel>>.data(
                <NecessityLabel>[],
              );
    final necessityLabels =
        necessityLabelsAsync.value ?? <NecessityLabel>[];

    final AsyncValue<List<ReasonLabel>> reasonLabelsAsync = showReasonSection
        ? ref.watch(reasonLabelsProvider)
        : const AsyncValue<List<ReasonLabel>>.data(
            <ReasonLabel>[],
          );
    final reasonLabels = reasonLabelsAsync.value ?? <ReasonLabel>[];

    if (showReasonSection &&
        _reasonId != null &&
        reasonLabels.where((label) => label.id == _reasonId).isEmpty) {
      _reasonId = null;
    }

    if (showNecessitySection &&
        !entryState.necessityResolved &&
        necessityLabels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        final fallbackLabel = entryState.necessityLabel;
        if (fallbackLabel != null) {
          final match = _findLabelByName(necessityLabels, fallbackLabel);
          if (match != null) {
            controller.setNecessity(
              id: match.id,
              label: match.name,
              criticality: necessityLabels.indexOf(match),
              resolved: true,
            );
          } else {
            controller.setNecessity(
              id: null,
              label: fallbackLabel,
              criticality: entryState.necessityCriticality,
              resolved: true,
            );
          }
          return;
        }
        final first = necessityLabels.first;
        controller.setNecessity(
          id: first.id,
          label: first.name,
          criticality: 0,
          resolved: true,
        );
      });
    }

    NecessityLabel? selectedNecessityLabel;
    if (showNecessitySection) {
      for (final label in necessityLabels) {
        if (label.id == entryState.necessityId) {
          selectedNecessityLabel = label;
          break;
        }
      }
    }

    ReasonLabel? selectedReasonLabel;
    if (showReasonSection && _reasonId != null) {
      for (final label in reasonLabels) {
        if (label.id == _reasonId) {
          selectedReasonLabel = label;
          break;
        }
      }
    }

    Future<void> saveOperation() async {
      if (!entryState.canSave || entryState.category == null) {
        return;
      }

      final category = entryState.category!;
      final categoryId = category.id;
      if (categoryId == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось определить категорию')), 
        );
        return;
      }
      final accountId = await _defaultAccountId(ref);
      final transactionType = _mapTransactionType(entryState.type);
      final amountMinor = (entryState.amount * 100).round();
      final note = entryState.note.trim().isEmpty
          ? null
          : entryState.note.trim();
      final fallbackNecessityLabel = entryState.necessityLabel;
      final applyNecessity = showNecessitySection;
      final necessityId = applyNecessity ? selectedNecessityLabel?.id : null;
      final necessityLabel = applyNecessity
          ? selectedNecessityLabel?.name ?? fallbackNecessityLabel
          : null;
      final necessityCriticality = applyNecessity
          ? (selectedNecessityLabel != null
              ? necessityLabels.indexOf(selectedNecessityLabel)
              : entryState.necessityCriticality)
          : 0;

      int? reasonId;
      String? reasonLabel;
      if (showReasonSection && _reasonId != null) {
        final reasonRepo = ref.read(reasonRepoProvider);
        final resolved = await reasonRepo.findById(_reasonId!);
        if (resolved != null) {
          reasonId = resolved.id;
          reasonLabel = resolved.name;
        } else {
          reasonId = _reasonId;
          reasonLabel = selectedReasonLabel?.name;
        }
      }

      final operationDate = _selectedDate ?? entryState.selectedDate;
      final normalizedDate =
          DateTime(operationDate.year, operationDate.month, operationDate.day);
      final inCurrent = ref.read(isInCurrentPeriodProvider(normalizedDate));

      final record = TransactionRecord(
        accountId: accountId,
        categoryId: categoryId,
        type: transactionType,
        amountMinor: amountMinor,
        date: normalizedDate,
        note: note,
        isPlanned: isPlannedExpense,
        includedInPeriod: isPlannedExpense ? false : inCurrent,
        criticality: necessityCriticality,
        necessityId: necessityId,
        necessityLabel: necessityLabel,
        reasonId: reasonId,
        reasonLabel: reasonLabel,
      );

      final transactionsRepository = ref.read(transactionsRepoProvider);
      await transactionsRepository.add(
        record,
        asSavingPair: entryState.type == CategoryType.saving,
        includedInPeriod: isPlannedExpense ? null : inCurrent,
      );
      bumpDbTick(ref);
      controller.reset();
      if (!mounted) {
        return;
      }
      final newState = ref.read(entryFlowControllerProvider);
      setState(() {
        _forcePlanned = _shouldForcePlanned(newState);
        _asPlanned =
            _forcePlanned && newState.type == CategoryType.expense;
        _reasonId = null;
      });
      if (isQuickAddKind) {
        ref.read(lastEntryKindProvider.notifier).state = operationKind;
      }
      ProviderContainer? containerForSnack;
      if (kReturnToOperationsAfterSave && isQuickAddKind) {
        containerForSnack = ProviderScope.containerOf(
          context,
          listen: false,
        );
      }
      if (kReturnToOperationsAfterSave) {
        context.goNamed(RouteNames.operations);
        if (isQuickAddKind) {
          final container = containerForSnack ??
              ProviderScope.containerOf(
                context,
                listen: false,
              );
          showAddAnotherSnackGlobal(
            seconds: 5,
            onTap: (ctx) {
              container
                  .read(entryFlowControllerProvider.notifier)
                  .resetForQuickAdd(operationKind);
              GoRouter.of(ctx).goNamed(RouteNames.entryAmount);
            },
          );
        }
      } else {
        context.goNamed(RouteNames.home);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Предпросмотр'),
        actions: [
          TextButton(
            onPressed: () {
              controller.reset();
              context.goNamed(RouteNames.home);
            },
            child: const Text('Закрыть'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SummaryRow(
                                label: 'Категория',
                                value: entryState.category?.name ?? 'Не выбрано',
                              ),
                              const SizedBox(height: 12),
                              _SummaryRow(
                                label: 'Сумма',
                                value: formatCurrency(entryState.amount),
                              ),
                              const SizedBox(height: 12),
                              _SummaryRow(
                                label: 'Тип операции',
                                value: entryState.type.label,
                              ),
                              const SizedBox(height: 16),
                              if (showPlanToggle) ...[
                                Text(
                                  'Добавить как:',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                      value: false,
                                      label: Text('Расход'),
                                    ),
                                    ButtonSegment(
                                      value: true,
                                      label: Text('План'),
                                    ),
                                  ],
                                  selected: {_asPlanned},
                                  showSelectedIcon: false,
                                  onSelectionChanged: (selection) {
                                    if (selection.isEmpty) {
                                      return;
                                    }
                                    setState(() {
                                      _asPlanned = selection.first;
                                      if (_asPlanned) {
                                        _reasonId = null;
                                      }
                                    });
                                  },
                                ),
                              ],
                              if (showNecessitySection) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Критичность/необходимость',
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                if (necessityLabelsAsync.isLoading &&
                                    necessityLabels.isEmpty)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (necessityLabels.isEmpty)
                                  Text(
                                    'Нет доступных меток. Добавьте их в настройках.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  )
                                else ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (var i = 0;
                                          i < necessityLabels.length;
                                          i++)
                                        NecessityChoiceChip(
                                          label: necessityLabels[i],
                                          selected: necessityLabels[i].id ==
                                              selectedNecessityLabel?.id,
                                          onSelected: (_) => controller
                                              .setNecessity(
                                            id: necessityLabels[i].id,
                                            label: necessityLabels[i].name,
                                            criticality: i,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (selectedNecessityLabel == null &&
                                      entryState.necessityLabel != null &&
                                      entryState.necessityResolved)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Метка "${entryState.necessityLabel!}" недоступна. Выберите новую.',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                              if (showReasonSection) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Причина',
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                if (reasonLabelsAsync.isLoading &&
                                    reasonLabels.isEmpty)
                                  const SizedBox(
                                    height: 32,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (reasonLabels.isEmpty)
                                  Text(
                                    'Нет доступных причин. Добавьте их в настройках.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final reason in reasonLabels)
                                        ChoiceChip(
                                          label: Text(reason.name),
                                          selected: _reasonId == reason.id,
                                          onSelected: (selected) {
                                            setState(() {
                                              _reasonId = selected
                                                  ? reason.id
                                                  : null;
                                            });
                                          },
                                          avatar: CircleAvatar(
                                            radius: 6,
                                            backgroundColor:
                                                hexToColor(reason.color) ??
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .surfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Дата',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _QuickDatePicker(
                        selectedDate: _selectedDate,
                        onSelected: (date) {
                          setState(() {
                            _selectedDate = date;
                          });
                          controller.setDate(date);
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Комментарий',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: entryState.note,
                        minLines: 2,
                        maxLines: 3,
                        onChanged: controller.setNote,
                        decoration: const InputDecoration(
                          hintText: 'Например: покупки к ужину',
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: entryState.canSave ? saveOperation : null,
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuickDatePicker extends StatelessWidget {
  const _QuickDatePicker({required this.selectedDate, required this.onSelected});

  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final offsets = List.generate(7, (index) => index - 3);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final offset in offsets)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _DateChoiceChip(
                baseDate: today,
                offset: offset,
                selectedDate: selectedDate,
                onSelected: onSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _DateChoiceChip extends StatelessWidget {
  const _DateChoiceChip({
    required this.baseDate,
    required this.offset,
    required this.selectedDate,
    required this.onSelected,
  });

  final DateTime baseDate;
  final int offset;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final date = baseDate.add(Duration(days: offset));
    final isToday = offset == 0;
    final label = isToday ? 'Сегодня' : shortDowDay(date);
    final isSelected =
        selectedDate != null && _isSameDay(selectedDate!, date);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(date),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
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

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Future<int> _defaultAccountId(WidgetRef ref) async {
  final accountsRepository = ref.read(accountsRepoProvider);
  final accounts = await accountsRepository.getAll();
  if (accounts.isEmpty) {
    throw StateError('Нет доступных счетов для сохранения операции');
  }
  final preferred = accounts.firstWhere(
    (account) =>
        account.name.trim().toLowerCase() == 'карта',
    orElse: () => accounts.first,
  );
  return preferred.id ?? accounts.first.id!;
}

TransactionType _mapTransactionType(CategoryType type) {
  switch (type) {
    case CategoryType.income:
      return TransactionType.income;
    case CategoryType.expense:
      return TransactionType.expense;
    case CategoryType.saving:
      return TransactionType.saving;
  }
}

