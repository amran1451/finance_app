import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/account.dart';
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
import '../../utils/period_utils.dart';
import '../../utils/plan_formatting.dart';
import '../widgets/add_another_snack.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/necessity_choice_chip.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

enum _ClosedPeriodAction { reopen, chooseOther }

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  static const int _kUnselectedAccountId = -1;

  bool _asPlanned = false;
  bool _forcePlanned = false;
  bool _reasonValidationError = false;
  bool _accountInitialized = false;
  int? _defaultAccountId;
  List<Account> _latestAccounts = const [];

  late final ValueNotifier<DateTime> selectedDate;
  late final ValueNotifier<int> selectedAccountId;
  late final ValueNotifier<int> amountMinor;
  late final ProviderSubscription<EntryFlowState> _entryFlowSubscription;
  late final ProviderSubscription<AsyncValue<List<Account>>>
      _accountsSubscription;
  late final ProviderSubscription<AsyncValue<int?>>
      _defaultAccountSubscription;

  @override
  void initState() {
    super.initState();
    final entryState = ref.read(entryFlowControllerProvider);
    _forcePlanned = _shouldForcePlanned(entryState);
    _asPlanned = entryState.attachToPlanned ||
        (_forcePlanned && entryState.type == CategoryType.expense);
    selectedDate = ValueNotifier(entryState.selectedDate);
    final initialAmountMinor = (entryState.amount * 100).round();
    amountMinor = ValueNotifier(initialAmountMinor);
    final initialAccountId =
        entryState.accountId ?? entryState.editingRecord?.accountId;
    if (initialAccountId != null) {
      _accountInitialized = true;
    }
    selectedAccountId =
        ValueNotifier<int>(initialAccountId ?? _kUnselectedAccountId);
    if (initialAccountId != null && entryState.accountId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ref
            .read(entryFlowControllerProvider.notifier)
            .setAccount(initialAccountId);
      });
    }
    _reasonValidationError = false;
    final defaultAccountSnapshot = ref.read(defaultAccountIdProvider);
    _defaultAccountId = defaultAccountSnapshot.valueOrNull;
    _entryFlowSubscription = ref.listenManual<EntryFlowState>(
      entryFlowControllerProvider,
      (previous, next) {
        final nextDate = next.selectedDate;
        if (!_isSameDay(selectedDate.value, nextDate)) {
          selectedDate.value = nextDate;
        }
        final nextAmountMinor = (next.amount * 100).round();
        if (amountMinor.value != nextAmountMinor) {
          amountMinor.value = nextAmountMinor;
        }
        final nextAccountId = next.accountId;
        if (nextAccountId != null && selectedAccountId.value != nextAccountId) {
          _syncAccountFromState(nextAccountId);
        }
      },
    );
    _accountsSubscription = ref.listenManual<AsyncValue<List<Account>>>(
      activeAccountsProvider,
      (previous, next) {
        next.whenData(_handleAccountsLoaded);
      },
    );
    _defaultAccountSubscription = ref.listenManual<AsyncValue<int?>>(
      defaultAccountIdProvider,
      (previous, next) {
        next.whenData((value) {
          _defaultAccountId = value;
          _applyDefaultAccountIfAvailable();
        });
      },
    );
  }

  bool _shouldForcePlanned(EntryFlowState state) {
    if (state.type != CategoryType.expense) {
      return false;
    }
    return state.attachToPlanned;
  }

  void _syncAccountFromState(int accountId) {
    if (selectedAccountId.value != accountId) {
      selectedAccountId.value = accountId;
    }
    _accountInitialized = true;
  }

  void _handleAccountsLoaded(List<Account> accounts) {
    _latestAccounts = accounts;
    if (accounts.isEmpty) {
      selectedAccountId.value = _kUnselectedAccountId;
      _accountInitialized = false;
      ref.read(entryFlowControllerProvider.notifier).setAccount(null);
      return;
    }
    final entryState = ref.read(entryFlowControllerProvider);
    final stateAccountId = entryState.accountId ?? entryState.editingRecord?.accountId;
    if (stateAccountId != null &&
        accounts.any((account) => account.id == stateAccountId)) {
      _syncAccountFromState(stateAccountId);
      return;
    }
    if (_accountInitialized && selectedAccountId.value != _kUnselectedAccountId) {
      return;
    }
    final preferred = _resolveDefaultAccount(accounts);
    if (preferred != null && preferred.id != null) {
      _updateAccountSelection(preferred.id!);
    }
  }

  Account? _resolveDefaultAccount(List<Account> accounts) {
    final defaultAccountId = _defaultAccountId;
    if (defaultAccountId != null) {
      for (final account in accounts) {
        if (account.id == defaultAccountId) {
          return account;
        }
      }
    }
    return _findPreferredAccount(accounts);
  }

  Account? _findPreferredAccount(List<Account> accounts) {
    if (accounts.isEmpty) {
      return null;
    }
    const normalizedTarget = 'карта';
    for (final account in accounts) {
      final name = account.name.trim().toLowerCase();
      if (name == normalizedTarget) {
        return account;
      }
    }
    return accounts.first;
  }

  void _applyDefaultAccountIfAvailable() {
    final accounts = _latestAccounts;
    if (accounts.isEmpty) {
      return;
    }
    final entryState = ref.read(entryFlowControllerProvider);
    final stateAccountId =
        entryState.accountId ?? entryState.editingRecord?.accountId;
    if (stateAccountId != null &&
        accounts.any((account) => account.id == stateAccountId)) {
      return;
    }
    if (_accountInitialized && selectedAccountId.value != _kUnselectedAccountId) {
      return;
    }
    final preferred = _resolveDefaultAccount(accounts);
    if (preferred != null && preferred.id != null) {
      _updateAccountSelection(preferred.id!);
    }
  }

  void _updateAccountSelection(int accountId) {
    if (selectedAccountId.value != accountId) {
      selectedAccountId.value = accountId;
    }
    _accountInitialized = true;
    ref.read(entryFlowControllerProvider.notifier).setAccount(accountId);
  }

  String _formatDateLabel(DateTime date) {
    return _formatReviewDate(date);
  }

  Future<void> editAmountViaCalculator(
    BuildContext context,
    int initialMinor,
  ) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _AmountCalculatorSheet(initialMinor: initialMinor);
      },
    );
    if (result != null) {
      amountMinor.value = result;
      ref.read(entryFlowControllerProvider.notifier).setAmountMinor(result);
    }
  }

  @override
  void dispose() {
    _entryFlowSubscription.close();
    _accountsSubscription.close();
    _defaultAccountSubscription.close();
    selectedDate.dispose();
    selectedAccountId.dispose();
    amountMinor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entryState = ref.watch(entryFlowControllerProvider);
    final controller = ref.read(entryFlowControllerProvider.notifier);
    final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
    final accountsAsync = ref.watch(activeAccountsProvider);
    final isEditing = entryState.editingRecord != null;

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
        entryState.reasonId != null &&
        reasonLabels.where((label) => label.id == entryState.reasonId).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        controller.setReason(
          id: null,
          label: entryState.reasonLabel,
        );
      });
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

    if (showReasonSection && entryState.reasonId != null) {
      for (final label in reasonLabels) {
        if (label.id == entryState.reasonId) {
          if (entryState.reasonLabel != label.name) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              controller.setReason(id: label.id, label: label.name);
            });
          }
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
      final editingRecord = entryState.editingRecord;
      final editingCounterpart = entryState.editingCounterpart;
      final isEditingOperation = editingRecord != null;

      final selectedAccountValue = selectedAccountId.value;
      if (selectedAccountValue == _kUnselectedAccountId) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите счёт')),
        );
        return;
      }
      final int accountId = selectedAccountValue;
      final transactionType = _mapTransactionType(entryState.type);
      final currentAmountMinor = amountMinor.value;
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

      int? reasonId = entryState.reasonId;
      String? reasonLabel = entryState.reasonLabel;
      if (showReasonSection) {
        final hasReason = reasonId != null ||
            (reasonLabel != null && reasonLabel.trim().isNotEmpty);
        if (!hasReason) {
          setState(() {
            _reasonValidationError = true;
          });
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Укажите причину расхода')),
          );
          return;
        }
        setState(() {
          _reasonValidationError = false;
        });
        if (reasonId != null) {
          final reasonRepo = ref.read(reasonRepoProvider);
          final resolved = await reasonRepo.findById(reasonId);
          if (resolved != null) {
            reasonId = resolved.id;
            reasonLabel = resolved.name;
          }
        } else if (reasonLabel != null) {
          reasonLabel = reasonLabel.trim();
        }
      } else {
        reasonId = null;
        reasonLabel = null;
        if (_reasonValidationError) {
          setState(() {
            _reasonValidationError = false;
          });
        }
      }

      final operationDate = selectedDate.value;
      final normalizedDate =
          DateTime(operationDate.year, operationDate.month, operationDate.day);
      final selectedPeriod = ref.read(selectedPeriodRefProvider);
      final periodStatus =
          await ref.read(periodStatusProvider(selectedPeriod).future);
      if (periodStatus.isClosed) {
        if (!mounted) {
          return;
        }
        final action = await showDialog<_ClosedPeriodAction>(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: const Text(
                'Период закрыт. Откройте период или выберите другой.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(_ClosedPeriodAction.chooseOther),
                  child: const Text('Выбрать другой период'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(_ClosedPeriodAction.reopen),
                  child: const Text('Открыть период'),
                ),
              ],
            );
          },
        );
        if (action != _ClosedPeriodAction.reopen) {
          return;
        }
        await ref.read(periodsRepoProvider).reopen(selectedPeriod);
        bumpDbTick(ref);
      }
      final bounds = ref.read(periodBoundsProvider);
      final normalizedStart = DateUtils.dateOnly(bounds.$1);
      final normalizedEndExclusive = DateUtils.dateOnly(bounds.$2);
      final isDateOutside = normalizedDate.isBefore(normalizedStart) ||
          !normalizedDate.isBefore(normalizedEndExclusive);
      final (anchor1, anchor2) = ref.read(anchorDaysProvider);
      var targetPeriod = periodRefForDate(normalizedDate, anchor1, anchor2);
      if (isDateOutside) {
        targetPeriod = selectedPeriod;
      }
      if (isDateOutside && mounted) {
        final targetBounds = targetPeriod.bounds(anchor1, anchor2);
        final targetLabel = compactPeriodLabel(
              targetBounds.start,
              targetBounds.endExclusive,
            ) ??
            'выбранной дате';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Дата вне границ выбранного периода, запись будет сохранена в период $targetLabel.',
            ),
          ),
        );
      }
      final inCurrent = ref.read(isInCurrentPeriodProvider(normalizedDate));

      final normalizedOriginalDate = isEditingOperation
          ? DateTime(
              editingRecord!.date.year,
              editingRecord.date.month,
              editingRecord.date.day,
            )
          : null;

      final includeInPeriod = entryState.includeInPeriod && inCurrent;

      final record = isEditingOperation
          ? editingRecord!.copyWith(
              accountId: accountId,
              categoryId: categoryId,
              type: transactionType,
              amountMinor: currentAmountMinor,
              date: normalizedDate,
              note: note,
              isPlanned: isPlannedExpense,
              includedInPeriod: isPlannedExpense ? false : includeInPeriod,
              criticality: necessityCriticality,
              necessityId: necessityId,
              necessityLabel: necessityLabel,
              reasonId: reasonId,
              reasonLabel: reasonLabel,
              periodId: targetPeriod.id,
            )
          : TransactionRecord(
              accountId: accountId,
              categoryId: categoryId,
              type: transactionType,
              amountMinor: currentAmountMinor,
              date: normalizedDate,
              note: note,
              isPlanned: isPlannedExpense,
              includedInPeriod: isPlannedExpense ? false : includeInPeriod,
              criticality: necessityCriticality,
              necessityId: necessityId,
              necessityLabel: necessityLabel,
              reasonId: reasonId,
              reasonLabel: reasonLabel,
              periodId: targetPeriod.id,
            );

      final shouldConfirmUpdate = isEditingOperation &&
          (editingRecord!.accountId != accountId ||
              editingRecord.categoryId != categoryId ||
              editingRecord.amountMinor != currentAmountMinor ||
              (normalizedOriginalDate != null &&
                  !_isSameDay(normalizedOriginalDate, normalizedDate)));

      if (shouldConfirmUpdate) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: const Text('Итоги периода будут пересчитаны'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('ОК'),
                ),
              ],
            );
          },
        );
        if (confirmed != true) {
          return;
        }
      }

      final transactionsRepository = ref.read(transactionsRepoProvider);
      if (isEditingOperation) {
        await transactionsRepository.update(
          record,
          includedInPeriod: isPlannedExpense ? null : includeInPeriod,
          uiPeriod: targetPeriod,
        );
        if (editingCounterpart != null) {
          final updatedCounterpart = editingCounterpart.copyWith(
            amountMinor: currentAmountMinor,
            date: normalizedDate,
            note: note,
            isPlanned: isPlannedExpense,
            includedInPeriod: isPlannedExpense ? false : includeInPeriod,
            criticality: necessityCriticality,
            necessityId: necessityId,
            necessityLabel: necessityLabel,
            reasonId: reasonId,
            reasonLabel: reasonLabel,
            periodId: targetPeriod.id,
          );
          await transactionsRepository.update(
            updatedCounterpart,
            includedInPeriod: isPlannedExpense ? null : includeInPeriod,
            uiPeriod: targetPeriod,
          );
        }
      } else {
        await transactionsRepository.add(
          record,
          asSavingPair: entryState.type == CategoryType.saving,
          includedInPeriod: isPlannedExpense ? null : includeInPeriod,
          uiPeriod: targetPeriod,
        );
      }
      await _maybePromptToClosePeriod(targetPeriod);
      bumpDbTick(ref);
      controller.reset();
      if (!mounted) {
        return;
      }
      final newState = ref.read(entryFlowControllerProvider);
      setState(() {
        _forcePlanned = _shouldForcePlanned(newState);
        _asPlanned = newState.attachToPlanned ||
            (_forcePlanned && newState.type == CategoryType.expense);
        _reasonValidationError = false;
      });
      selectedDate.value = newState.selectedDate;
      amountMinor.value = (newState.amount * 100).round();
      final resetAccountId = newState.accountId ?? _kUnselectedAccountId;
      selectedAccountId.value = resetAccountId;
      _accountInitialized = newState.accountId != null;
      if (isEditingOperation) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Операция обновлена')),
        );
        return;
      }
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
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
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
                              ValueListenableBuilder<int>(
                                valueListenable: amountMinor,
                                builder: (context, value, _) {
                                  final formattedAmount =
                                      formatCurrency(value / 100);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _SummaryRow(
                                        label: 'Сумма',
                                        value: formattedAmount,
                                      ),
                                      if (isEditing) ...[
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () =>
                                                editAmountViaCalculator(
                                              context,
                                              value,
                                            ),
                                            child: const Text('Изменить сумму'),
                                          ),
                                          ),
                                        ],
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _SummaryRow(
                                label: 'Тип операции',
                                value: entryState.type.label,
                              ),
                              const SizedBox(height: 12),
                              ValueListenableBuilder<DateTime>(
                                valueListenable: selectedDate,
                                builder: (context, value, _) {
                                  return _SummaryRow(
                                    label: 'Дата',
                                    value: _formatDateLabel(value),
                                  );
                                },
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
                                        _reasonValidationError = false;
                                      }
                                    });
                                    controller.setAttachToPlanned(selection.first);
                                    if (selection.first) {
                                      controller.setReason(id: null, label: null);
                                    }
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
                                else ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final reason in reasonLabels)
                                        ChoiceChip(
                                          label: Text(reason.name),
                                          selected:
                                              entryState.reasonId == reason.id,
                                          onSelected: (selected) {
                                            if (selected) {
                                              controller.setReason(
                                                id: reason.id,
                                                label: reason.name,
                                              );
                                              setState(() {
                                                _reasonValidationError = false;
                                              });
                                            } else {
                                              controller.setReason(
                                                id: null,
                                                label: null,
                                              );
                                            }
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
                                  if (entryState.reasonId == null &&
                                      entryState.reasonLabel != null &&
                                      entryState.reasonLabel!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Причина "${entryState.reasonLabel!}" недоступна. Выберите новую.',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                  if (_reasonValidationError)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Укажите причину расхода',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                ],
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
                      ValueListenableBuilder<DateTime>(
                        valueListenable: selectedDate,
                        builder: (context, value, _) {
                          return _QuickDatePicker(
                            selectedDate: value,
                            periodStart: periodStart,
                            periodEndExclusive: periodEndExclusive,
                            onSelected: (date) {
                              final normalized =
                                  DateTime(date.year, date.month, date.day);
                              selectedDate.value = normalized;
                              controller.setDate(normalized);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Счёт',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      accountsAsync.when(
                        data: (accounts) {
                          final selectableAccounts =
                              accounts.where((account) => account.id != null).toList();
                          if (selectableAccounts.isEmpty) {
                            return Text(
                              'Добавьте счёт, чтобы продолжить.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                          return ValueListenableBuilder<int>(
                            valueListenable: selectedAccountId,
                            builder: (context, selectedValue, _) {
                              final hasMatch = selectableAccounts
                                  .any((account) => account.id == selectedValue);
                              final dropdownValue =
                                  hasMatch ? selectedValue : null;
                              final showError =
                                  (dropdownValue == null ||
                                      selectedValue == _kUnselectedAccountId) &&
                                      _accountInitialized;
                              return DropdownButtonFormField<int>(
                                value: dropdownValue,
                                decoration: InputDecoration(
                                  hintText: 'Выберите счёт',
                                  errorText: showError ? 'Выберите счёт' : null,
                                ),
                                items: [
                                  for (final account in selectableAccounts)
                                    DropdownMenuItem<int>(
                                      value: account.id!,
                                      child: Text(account.name),
                                    ),
                                ],
                                onChanged: (newValue) {
                                  if (newValue != null) {
                                    _updateAccountSelection(newValue);
                                  }
                                },
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (error, _) => Text('Не удалось загрузить счета: $error'),
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
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: ValueListenableBuilder<int>(
          valueListenable: selectedAccountId,
          builder: (context, accountIdValue, _) {
            final canSave = entryState.canSave &&
                accountIdValue != _kUnselectedAccountId;
            return SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSave ? saveOperation : null,
                child: const Text('Сохранить'),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _maybePromptToClosePeriod(PeriodRef period) async {
    final status = await ref.read(periodStatusProvider(period).future);
    if (status.isClosed) {
      return;
    }

    final (anchor1, anchor2) = ref.read(anchorDaysProvider);
    final bounds = period.bounds(anchor1, anchor2);
    final today = DateUtils.dateOnly(DateTime.now());
    final endExclusive = DateUtils.dateOnly(bounds.endExclusive);
    if (today.isBefore(endExclusive)) {
      return;
    }

    if (!mounted) {
      return;
    }

    final periodLabel = ref.read(periodLabelForRefProvider(period));
    final shouldClose = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Закрыть период?'),
            content: Text('Период $periodLabel завершён. Закрыть его?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldClose) {
      return;
    }

    try {
      final read = ref.read;
      final spent = await read(spentForPeriodProvider(period).future);
      final planned =
          await read(plannedIncludedAmountForPeriodProvider(period).future);
      final payout = await read(payoutForPeriodProvider(period).future);
      await read(periodsRepoProvider).closePeriod(
        period,
        payoutId: payout?.id,
        dailyLimitMinor: payout?.dailyLimitMinor,
        spentMinor: spent,
        plannedIncludedMinor: planned,
        carryoverMinor: 0,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Период $periodLabel закрыт')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось закрыть период: $error')),
      );
    }
  }
}

const double _dateItemWidth = 96;
const double _dateItemSpacing = 12;

class _QuickDatePicker extends StatefulWidget {
  const _QuickDatePicker({
    required this.selectedDate,
    required this.onSelected,
    required this.periodStart,
    required this.periodEndExclusive,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelected;
  final DateTime periodStart;
  final DateTime periodEndExclusive;

  @override
  State<_QuickDatePicker> createState() => _QuickDatePickerState();
}

class _QuickDatePickerState extends State<_QuickDatePicker> {
  late final ScrollController _controller;
  late List<DateTime> _dates;
  bool _didInitialScroll = false;
  double? _viewportWidth;
  DateTime? _pendingCenteredDate;
  bool _pendingAnimate = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _dates = _buildDates();
  }

  @override
  void didUpdateWidget(covariant _QuickDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodStart != widget.periodStart ||
        oldWidget.periodEndExclusive != widget.periodEndExclusive) {
      _dates = _buildDates();
      _didInitialScroll = false;
    }
    final oldSelected = oldWidget.selectedDate;
    final newSelected = widget.selectedDate;
    final sameSelection =
        (oldSelected == null && newSelected == null) ||
            (oldSelected != null &&
                newSelected != null &&
                _isSameDay(oldSelected, newSelected));
    if (!sameSelection) {
      _centerOnDate(newSelected ?? DateTime.now(), animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final mediaQueryWidth = MediaQuery.of(context).size.width;
        final resolvedWidth =
            maxWidth.isFinite ? maxWidth : mediaQueryWidth;
        if (_viewportWidth != resolvedWidth) {
          _viewportWidth = resolvedWidth;
          if (_pendingCenteredDate != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              final pending = _pendingCenteredDate;
              final animate = _pendingAnimate;
              if (pending != null) {
                _centerOnDate(pending, animate: animate);
              }
            });
          }
        }
        _scheduleInitialScroll();
        return SizedBox(
          height: 48,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final date = _dates[index];
              final isSelected = widget.selectedDate != null &&
                  _isSameDay(widget.selectedDate!, date);
              return SizedBox(
                width: _dateItemWidth,
                child: Center(
                  child: _DateChoiceChip(
                    date: date,
                    isSelected: isSelected,
                    onSelected: widget.onSelected,
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: _dateItemSpacing),
            itemCount: _dates.length,
          ),
        );
      },
    );
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _centerOnDate(widget.selectedDate ?? DateTime.now());
      _didInitialScroll = true;
    });
  }

  List<DateTime> _buildDates() {
    final start = widget.periodStart.subtract(const Duration(days: 3));
    final end = widget.periodEndExclusive.add(const Duration(days: 3));
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    final diff = normalizedEnd.difference(normalizedStart).inDays;
    final count = diff >= 0 ? diff + 1 : 1;
    return List<DateTime>.generate(count, (index) {
      return normalizedStart.add(Duration(days: index));
    });
  }

  void _centerOnDate(DateTime target, {bool animate = false}) {
    if (_dates.isEmpty) {
      _pendingCenteredDate = null;
      _pendingAnimate = false;
      return;
    }
    final normalized = DateTime(target.year, target.month, target.day);
    var index = _dates.indexWhere((date) => _isSameDay(date, normalized));
    if (index == -1) {
      if (normalized.isBefore(_dates.first)) {
        index = 0;
      } else if (normalized.isAfter(_dates.last)) {
        index = _dates.length - 1;
      } else {
        index = 0;
      }
    }

    if (!_controller.hasClients || _viewportWidth == null) {
      _pendingCenteredDate = normalized;
      if (animate) {
        _pendingAnimate = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final pendingDate = _pendingCenteredDate;
        if (pendingDate != null) {
          _centerOnDate(pendingDate, animate: _pendingAnimate);
        }
      });
      return;
    }

    _pendingCenteredDate = null;
    final viewWidth = _viewportWidth!;
    final itemExtent = _dateItemWidth + _dateItemSpacing;
    final targetOffset = index * itemExtent - (viewWidth - _dateItemWidth) / 2;
    final maxOffset = math.max(0.0, _controller.position.maxScrollExtent);
    final offset = targetOffset.clamp(0.0, maxOffset);
    if (animate || _pendingAnimate) {
      _controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(offset);
    }
    _pendingAnimate = false;
  }
}

class _DateChoiceChip extends StatelessWidget {
  const _DateChoiceChip({
    required this.date,
    required this.isSelected,
    required this.onSelected,
  });

  final DateTime date;
  final bool isSelected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = _formatReviewDate(date);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(date),
    );
  }
}

class _AmountCalculatorSheet extends StatefulWidget {
  const _AmountCalculatorSheet({required this.initialMinor});

  final int initialMinor;

  @override
  State<_AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<_AmountCalculatorSheet> {
  late String _expression;
  double? _previewResult;
  double? _evaluatedResult;

  @override
  void initState() {
    super.initState();
    final initialAmount = widget.initialMinor / 100;
    if (initialAmount > 0) {
      final normalized = _formatExpressionValue(initialAmount);
      _expression = normalized;
      _previewResult = initialAmount;
      _evaluatedResult = initialAmount;
    } else {
      _expression = '';
      _previewResult = null;
      _evaluatedResult = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expressionDisplay = _expression.isEmpty
        ? '0'
        : _expression.replaceAll('*', '×').replaceAll('/', '÷');
    final currentAmount = _evaluatedResult ?? _previewResult;
    final formattedAmount = formatCurrency(currentAmount ?? 0);
    final canSave = _canSave;

    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Изменение суммы',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      expressionDisplay,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formattedAmount,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_previewResult != null && _evaluatedResult == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '= ${formatCurrency(_previewResult ?? 0)}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AmountKeypad(
                onDigitPressed: _appendDigit,
                onOperatorPressed: _appendOperator,
                onBackspace: _backspace,
                onDecimal: _appendDecimal,
                onAllClear: _clear,
                onEvaluate: _evaluateExpression,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave {
    final value = _evaluatedResult ?? _previewResult;
    return value != null && value > 0;
  }

  void _appendDigit(String digit) {
    final segment = _currentNumberSegment(_expression);
    if (_expression == '0') {
      _setExpression(digit);
      return;
    }
    if (segment == '0' && _expression.isNotEmpty) {
      _setExpression(
        _expression.substring(0, _expression.length - 1) + digit,
      );
      return;
    }
    if (segment == '-0' && _expression.length >= 2) {
      _setExpression(
        _expression.substring(0, _expression.length - 1) + digit,
      );
      return;
    }
    _setExpression('$_expression$digit');
  }

  void _appendOperator(String operator) {
    if (_expression.isEmpty) {
      if (operator == '-') {
        _setExpression('-');
      }
      return;
    }
    final lastChar = _expression[_expression.length - 1];
    if (_isOperator(lastChar) || lastChar == '.') {
      return;
    }
    _setExpression('$_expression$operator');
  }

  void _appendDecimal() {
    final segment = _currentNumberSegment(_expression);
    if (segment.contains('.')) {
      return;
    }
    if (segment.isEmpty) {
      if (_expression.isEmpty) {
        _setExpression('0.');
      } else {
        _setExpression('${_expression}0.');
      }
      return;
    }
    if (segment == '-') {
      _setExpression('${_expression}0.');
      return;
    }
    _setExpression('$_expression.');
  }

  void _backspace() {
    if (_expression.isEmpty) {
      return;
    }
    final updated = _expression.substring(0, _expression.length - 1);
    _setExpression(updated);
  }

  void _clear() {
    setState(() {
      _expression = '';
      _previewResult = null;
      _evaluatedResult = null;
    });
  }

  void _evaluateExpression() {
    final evaluated = ExpressionEvaluator.tryEvaluate(_expression);
    if (evaluated == null) {
      return;
    }
    setState(() {
      final normalized = _formatExpressionValue(evaluated);
      _expression = normalized;
      _previewResult = evaluated;
      _evaluatedResult = evaluated;
    });
  }

  void _save() {
    final value = _evaluatedResult ?? _previewResult;
    if (value == null || value <= 0) {
      return;
    }
    final minor = (value * 100).round();
    Navigator.of(context).pop(minor);
  }

  void _setExpression(String expression) {
    if (expression.isEmpty) {
      setState(() {
        _expression = '';
        _previewResult = null;
        _evaluatedResult = null;
      });
      return;
    }
    final preview = ExpressionEvaluator.tryEvaluate(expression);
    setState(() {
      _expression = expression;
      _previewResult = preview;
      _evaluatedResult = null;
    });
  }

  bool _isOperator(String value) {
    return value == '+' || value == '-' || value == '*' || value == '/';
  }

  String _currentNumberSegment(String expression) {
    if (expression.isEmpty) {
      return '';
    }
    final index = _lastOperatorIndex(expression);
    if (index == -1) {
      return expression;
    }
    return expression.substring(index + 1);
  }

  int _lastOperatorIndex(String expression) {
    for (var i = expression.length - 1; i >= 0; i--) {
      final char = expression[i];
      if (_isOperator(char)) {
        if (char == '-' && i == 0) {
          continue;
        }
        return i;
      }
    }
    return -1;
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

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatReviewDate(DateTime date) {
  final raw = DateFormat('EE, d MMM', 'ru').format(date);
  final sanitized = raw.replaceAll('.', '');
  return _capitalizeFirst(sanitized);
}

String _capitalizeFirst(String value) {
  if (value.isEmpty) {
    return value;
  }
  final first = value[0].toUpperCase();
  return '$first${value.substring(1)}';
}

String _formatExpressionValue(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  var text = value.toStringAsFixed(2);
  text = text.replaceAll(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

