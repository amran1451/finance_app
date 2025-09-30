import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart' as db_models;
import '../../data/models/payout.dart';
import '../../data/models/transaction_record.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/planned_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';
import '../../utils/period_utils.dart';
import '../../utils/ru_plural.dart';
import '../planned/planned_add_form.dart';
import '../planned/expense_plan_sheets.dart';
import '../payouts/payout_edit_sheet.dart';
import 'daily_limit_sheet.dart';
import '../widgets/callout_card.dart';
import '../widgets/period_selector.dart';
import '../widgets/progress_line.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbTickProvider);
    final accountsAsync = ref.watch(accountsDbProvider);
    final hideFab = ref.watch(isSheetOpenProvider);
    final entryController = ref.read(entryFlowControllerProvider.notifier);
    final transactionsAsync = ref.watch(halfPeriodTransactionsProvider);
    final period = ref.watch(selectedPeriodRefProvider);
    final spentTodayAsync = ref.watch(spentTodayProvider(period));
    final todayProgressState = ref.watch(todayProgressProvider);
    final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
    final label = ref.watch(periodLabelProvider);
    final payoutAsync = ref.watch(payoutForSelectedPeriodProvider);
    final suggestedType = ref.watch(payoutSuggestedTypeProvider);
    final canClosePeriod = ref.watch(canCloseCurrentPeriodProvider);
    final periodStatusAsync = ref.watch(periodStatusProvider(period));
    final periodClosed = periodStatusAsync.maybeWhen(
      data: (status) => status.closed,
      orElse: () => false,
    );
    final isActivePeriod = ref.watch(isActivePeriodProvider);
    final daysLeft =
        isActivePeriod ? ref.watch(daysUntilNextPayoutFromTodayProvider) : null;
    final showClosedBadge = isActivePeriod && periodClosed;
    final generalPayoutLabel =
        'Добавить выплату (по периоду: ${payoutTypeLabel(suggestedType)})';

    final transactions = transactionsAsync.asData?.value ?? const [];
    final isTransactionsLoading = transactionsAsync.isLoading;
    final transactionsError = transactionsAsync is AsyncError
        ? (transactionsAsync as AsyncError).error
        : null;
    final hasOperations = transactions.isNotEmpty;
    final periodExpenseMinor = transactions
        .where((record) => record.type == TransactionType.expense)
        .fold<int>(0, (sum, record) => sum + record.amountMinor);
    final periodIncomeMinor = transactions
        .where((record) => record.type == TransactionType.income)
        .fold<int>(0, (sum, record) => sum + record.amountMinor);

    final todayHasError = spentTodayAsync.hasError;
    final isTodayLoading = spentTodayAsync.isLoading;
    final todaySubtitle = todayHasError
        ? 'Ошибка загрузки'
        : isTodayLoading
            ? 'Загрузка…'
            : todayProgressState.show
                ? '${formatCurrencyMinor(todayProgressState.spent)} из '
                    '${formatCurrencyMinor(todayProgressState.limit)}'
                : '—';
    final todayProgressValue = !todayProgressState.show
        ? 0.0
        : todayProgressState.limit == 0
            ? 0.0
            : (todayProgressState.spent / todayProgressState.limit)
                .clamp(0.0, 1.0);
    final Widget todayChild;
    if (todayHasError) {
      todayChild = const SizedBox.shrink();
    } else if (isTodayLoading) {
      todayChild = const LinearProgressIndicator();
    } else if (!todayProgressState.show) {
      todayChild = const SizedBox.shrink();
    } else {
      todayChild = ProgressLine(
        value: todayProgressValue,
        label: 'Прогресс дня',
      );
    }

    final periodExpenseLabel = isTransactionsLoading
        ? 'Загрузка…'
        : transactionsError != null
            ? 'Ошибка'
            : formatCurrencyMinor(periodExpenseMinor);
    final periodIncomeLabel = isTransactionsLoading
        ? 'Загрузка…'
        : transactionsError != null
            ? 'Ошибка'
            : formatCurrencyMinor(periodIncomeMinor);

    final rawEnd = periodEndExclusive.subtract(const Duration(days: 1));
    final endInclusive =
        rawEnd.isBefore(periodStart) ? periodStart : rawEnd;
    final boundsLabel =
        '${formatDayMonth(periodStart)} – ${formatDayMonth(endInclusive)}';

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: hideFab
          ? null
          : _OvalFab(
              onPressed: () {
                entryController.startNew();
                context.pushNamed(RouteNames.entryAmount);
              },
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canClosePeriod) ...[
                MaterialBanner(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  content: Text('Период $label завершён. Закрыть?'),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        final read = ref.read;
                        final periodRef = read(selectedPeriodRefProvider);
                        final spent = await read(
                          spentForPeriodProvider(periodRef).future,
                        );
                        final planned = await read(
                          plannedIncludedAmountForPeriodProvider(periodRef).future,
                        );
                        final payout = await read(payoutForSelectedPeriodProvider.future);
                        final dailyLimitMinor =
                            read(periodDailyLimitProvider);
                        await read(periodsRepoProvider).closePeriod(
                          periodRef,
                          payoutId: payout?.id,
                          dailyLimitMinor: dailyLimitMinor,
                          spentMinor: spent,
                          plannedIncludedMinor: planned,
                          carryoverMinor: 0,
                        );
                        read(selectedPeriodRefProvider.notifier).state =
                            periodRef.nextHalf();
                        bumpDbTick(ref);
                      },
                      child: const Text('Закрыть'),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Позже'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PeriodSelector(dense: true, label: label),
                    if (showClosedBadge || daysLeft != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          if (showClosedBadge) const _ClosedPeriodBadge(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              final slideAnimation = Tween<Offset>(
                                begin: const Offset(0.12, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slideAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: daysLeft == null
                                ? const SizedBox.shrink()
                                : _DaysLeftBadge(
                                    key: ValueKey(daysLeft),
                                    days: daysLeft,
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              payoutAsync.when(
                loading: () => const _EmptyLimitPlaceholder(),
                error: (_, __) => const _EmptyLimitPlaceholder(),
                data: (payout) {
                  if (payout == null) {
                    return _AddPayoutCTA(
                      buttonLabel: generalPayoutLabel,
                      onTap: () async {
                        final tickBefore = ref.read(dbTickProvider);
                        await showPayoutForSelectedPeriod(context);
                        if (!context.mounted) {
                          return;
                        }
                        final tickAfter = ref.read(dbTickProvider);
                        if (tickAfter != tickBefore) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Выплата добавлена')),
                          );
                        }
                      },
                    );
                  }
                  final period = ref.watch(selectedPeriodRefProvider);
                  final dailyLimitMinor = ref.watch(periodDailyLimitProvider);
                  return _LimitCards(
                    dailyLimit: dailyLimitMinor,
                    leftPeriod: ref.watch(periodBudgetRemainingProvider(period)),
                    onEditLimit: () async {
                      final saved = await showEditDailyLimitSheet(context, ref);
                      if (!context.mounted || !saved) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Лимит для периода обновлён')),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              CalloutCard(
                title: 'Траты сегодня',
                subtitle: todaySubtitle,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.operations),
                child: todayChild,
              ),
              const SizedBox(height: 16),
              CalloutCard(
                title: 'Планы расходов',
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Редактировать выплату',
                  onPressed: () async {
                    final repository = ref.read(payoutsRepoProvider);
                    final last = await repository.getLast();
                    if (!context.mounted) {
                      return;
                    }
                    if (last == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Нет выплат для редактирования')),
                      );
                      return;
                    }
                    final tickBefore = ref.read(dbTickProvider);
                    await showPayoutEditSheet(
                      context,
                      initial: last,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    final tickAfter = ref.read(dbTickProvider);
                    if (tickAfter != tickBefore) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Изменения применены')),
                      );
                    }
                  },
                ),
                child: const _PlannedOverview(),
              ),
              const SizedBox(height: 16),
              CalloutCard(
                title: 'Счета',
                subtitle: 'Баланс ваших кошельков и карт',
                trailing: IconButton(
                  onPressed: () => context.pushNamed(RouteNames.accountCreate),
                  icon: const Icon(Icons.add),
                  tooltip: 'Добавить счёт',
                ),
                child: accountsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Не удалось загрузить счета: $error'),
                  ),
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return const Text(
                        'Добавьте первый счёт, чтобы видеть баланс здесь.',
                      );
                    }
                    return Column(
                      children: [
                        for (final account in accounts)
                          _HomeAccountTile(account: account),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '$boundsLabel: операции',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (transactionsError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Не удалось загрузить операции: $transactionsError'),
                  ),
                )
              else if (!hasOperations && !isTransactionsLoading)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Операций пока нет',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),
                        Text('Нажмите на “+”, чтобы добавить первую запись.'),
                      ],
                    ),
                  ),
                )
              else if (isTransactionsLoading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton.tonalIcon(
                  onPressed: () => context.pushNamed(RouteNames.operations),
                  icon: const Icon(Icons.receipt_long),
                  label: Text('Открыть операции периода · $periodExpenseLabel'),
                ),
              const SizedBox(height: 8),
              Text(
                'Доходы за период: $periodIncomeLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _EmptyLimitPlaceholder extends StatelessWidget {
  const _EmptyLimitPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось на день',
            value: '—',
            alignment: TextAlign.left,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: '—',
            alignment: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _AddPayoutCTA extends StatelessWidget {
  const _AddPayoutCTA({
    required this.onTap,
    required this.buttonLabel,
  });

  final VoidCallback onTap;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return CalloutCard(
      title: 'Добавьте ближайшую выплату',
      subtitle: 'Чтобы отслеживать бюджет, укажите дату и сумму.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: onTap,
          icon: const Icon(Icons.payments_outlined),
          label: Text(buttonLabel),
        ),
      ),
    );
  }
}

class _LimitCards extends StatelessWidget {
  const _LimitCards({
    required this.dailyLimit,
    required this.leftPeriod,
    required this.onEditLimit,
  });

  final int dailyLimit;
  final AsyncValue<int> leftPeriod;
  final VoidCallback onEditLimit;

  @override
  Widget build(BuildContext context) {
    String buildDailyLimitLabel() {
      if (dailyLimit <= 0) {
        return '—';
      }
      return formatCurrencyMinorToRubles(dailyLimit);
    }

    String buildPeriodLabel(AsyncValue<int> value) {
      return value.when(
        data: (v) => formatCurrencyMinorToRubles(v),
        loading: () => '…',
        error: (_, __) => '—',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось на день',
            value: buildDailyLimitLabel(),
            alignment: TextAlign.left,
            onEdit: onEditLimit,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: buildPeriodLabel(leftPeriod),
            alignment: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _ClosedPeriodBadge extends StatelessWidget {
  const _ClosedPeriodBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Закрыт',
        style: theme.textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DaysLeftBadge extends StatelessWidget {
  final int days;

  const _DaysLeftBadge({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = ruDaysShort(days);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined, size: 16),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.12, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            },
            child: Text(
              txt,
              key: ValueKey(txt),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannedOverview extends ConsumerStatefulWidget {
  const _PlannedOverview();

  @override
  ConsumerState<_PlannedOverview> createState() => _PlannedOverviewState();
}

class _PlannedOverviewState extends ConsumerState<_PlannedOverview> {
  Future<void> _openQuickAdd(BuildContext context) async {
    final sheetNotifier = ref.read(isSheetOpenProvider.notifier);
    final expandedState = ref.read(plansExpandedProvider);
    final expansionNotifier = ref.read(plansExpandedProvider.notifier);
    sheetNotifier.state = true;
    try {
      final period = ref.read(selectedPeriodRefProvider);
      final result = await showPlanExpenseAddEntry(context, period);
      if (!mounted) {
        return;
      }
      switch (result) {
        case ExpensePlanResult.created:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('План добавлен')),
          );
          break;
        case ExpensePlanResult.assigned:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('План назначен')),
          );
          break;
        case ExpensePlanResult.none:
          break;
      }
    } finally {
      sheetNotifier.state = false;
      expansionNotifier.state = expandedState;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payoutAsync = ref.watch(payoutForSelectedPeriodProvider);
    final period = ref.watch(selectedPeriodRefProvider);
    final baseAsync = ref.watch(plannedPoolBaseProvider);
    final remainingAsync = ref.watch(plannedPoolRemainingProvider(period));
    final usedAsync = ref.watch(sumIncludedPlannedExpensesProvider(period));
    return payoutAsync.when(
      data: (payout) {
        if (payout == null) {
          return const Text(
            'Добавьте ближайшую выплату, чтобы расчёт бюджета был точным.',
          );
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final baseValue = baseAsync.valueOrNull;
        final usedValue = usedAsync.valueOrNull;
        final deficitMinor = baseValue != null && usedValue != null && usedValue > baseValue
            ? usedValue - baseValue
            : 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (deficitMinor > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Планы превышают бюджет на ${formatCurrencyMinor(deficitMinor)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: remainingAsync.when(
                    data: (value) => Text(
                      'Доступно на планы: ${formatCurrencyMinor(value)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    loading: () => Row(
                      children: const [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Доступно на планы: …',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    error: (_, __) => Text(
                      'Доступно на планы: —',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                  onPressed: () => _openQuickAdd(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PlannedExpensesList(period: period),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Не удалось получить данные о выплатах: $error'),
      ),
    );
  }
}

class _PlannedExpensesList extends ConsumerWidget {
  const _PlannedExpensesList({required this.period});

  final PeriodRef period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(plansExpandedProvider);
    final itemsAsync = ref.watch(plannedExpensesForPeriodProvider(period));
    final theme = Theme.of(context);
    final plansCount = itemsAsync.maybeWhen(
      data: (items) => items.length,
      orElse: () => null,
    );

    return ExpansionTile(
      key: const PageStorageKey('home_plans_expansion'),
      initiallyExpanded: expanded,
      maintainState: true,
      onExpansionChanged: (value) =>
          ref.read(plansExpandedProvider.notifier).state = value,
      title: Text(
        'Планы расходов (${plansCount?.toString() ?? '…'})',
        style: theme.textTheme.titleMedium,
      ),
      children: [
        itemsAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Пока нет планов расходов в этом периоде.',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }
            return ListView.builder(
              key: const PageStorageKey('home_plans_list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final recordId = item.record.id;
                final necessity = item.necessityLabel;
                final necessityLabel =
                    necessity != null && necessity.trim().isNotEmpty
                        ? necessity
                        : '—';
                return Column(
                  key: ValueKey(recordId ?? -index - 1),
                  children: [
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Checkbox(
                        value: item.record.includedInPeriod,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: recordId == null
                            ? null
                            : (value) async {
                                await ref
                                    .read(transactionsRepoProvider)
                                    .setPlannedIncluded(
                                        recordId, value ?? false);
                                bumpDbTick(ref);
                              },
                      ),
                      title: Text(
                        '${item.title} — ${formatCurrencyMinor(item.record.amountMinor)} — $necessityLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Удалить из периода',
                        onPressed: recordId == null
                            ? null
                            : () async {
                                final confirmed = await _confirmDeletePlan(
                                  context,
                                  'Удалить план из периода?',
                                );
                                if (confirmed == true) {
                                  await ref
                                      .read(transactionsRepoProvider)
                                      .deletePlannedInstance(recordId);
                                  bumpDbTick(ref);
                                }
                              },
                      ),
                      onTap: () => showPlannedAddForm(
                        context,
                        type: PlannedType.expense,
                        initialRecord: item.record,
                      ),
                    ),
                    if (index != items.length - 1) const Divider(height: 0),
                  ],
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Ошибка: $error'),
          ),
        ),
      ],
    );
  }
}

Future<bool?> _confirmDeletePlan(BuildContext context, String message) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
}

class _HomeAccountTile extends ConsumerWidget {
  const _HomeAccountTile({required this.account});

  final db_models.Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountId = account.id;
    if (accountId == null) {
      return const SizedBox.shrink();
    }
    final computedAsync = ref.watch(computedBalanceProvider(accountId));

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        child: Icon(Icons.account_balance_wallet),
      ),
      title: Text(account.name),
      subtitle: computedAsync.when(
        data: (computed) => Text(
          'Баланс: ${formatCurrencyMinor(computed)}',
        ),
        loading: () => const Text('Загрузка баланса…'),
        error: (error, _) => Text('Ошибка расчёта: $error'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        RouteNames.accountEdit,
        queryParameters: {'id': accountId.toString()},
        extra: account.name,
      ),
    );
  }
}

class _RemainingInfoCard extends StatelessWidget {
  const _RemainingInfoCard({
    required this.label,
    required this.value,
    required this.alignment,
    this.onEdit,
  });

  final String label;
  final String value;
  final TextAlign alignment;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEnd = alignment == TextAlign.right || alignment == TextAlign.end;
    final crossAxis = isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final hasEdit = onEdit != null;

    return Card(
      elevation: 0,
      color: scheme.surfaceVariant.withOpacity(0.4),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: crossAxis,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment:
                  isEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    textAlign: alignment,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (hasEdit)
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    tooltip: 'Изменить лимит',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: alignment,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _OvalFab extends StatelessWidget {
  const _OvalFab({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RawMaterialButton(
      onPressed: onPressed,
      fillColor: theme.colorScheme.primary,
      constraints: const BoxConstraints(minWidth: 72, minHeight: 56),
      shape: const StadiumBorder(),
      elevation: 6,
      child: Icon(Icons.add, color: theme.colorScheme.onPrimary),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
