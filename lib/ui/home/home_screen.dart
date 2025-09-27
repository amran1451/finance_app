import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart' as db_models;
import '../../data/models/payout.dart';
import '../../data/models/transaction_record.dart';
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
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
import '../planned/planned_quick_add_sheet.dart';
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
    final dailyLimitAsync = ref.watch(dailyLimitProvider);
    final accountsAsync = ref.watch(accountsDbProvider);
    final hideFab = ref.watch(isSheetOpenProvider);
    final entryController = ref.read(entryFlowControllerProvider.notifier);
    final transactionsAsync = ref.watch(halfPeriodTransactionsProvider);
    final period = ref.watch(selectedPeriodRefProvider);
    final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
    final label = ref.watch(periodLabelProvider);
    final daysLeft = ref.watch(daysFromPayoutToPeriodEndProvider);
    final payoutAsync = ref.watch(payoutForSelectedPeriodProvider);
    final suggestedType = ref.watch(payoutSuggestedTypeProvider);
    final canClosePeriod = ref.watch(canCloseCurrentPeriodProvider);
    final periodStatusAsync = ref.watch(periodStatusProvider(period));
    final periodClosed = periodStatusAsync.maybeWhen(
      data: (status) => status.closed,
      orElse: () => false,
    );
    final generalPayoutLabel =
        'Добавить выплату (по периоду: ${payoutTypeLabel(suggestedType)})';

    final transactions = transactionsAsync.asData?.value ?? const [];
    final isTransactionsLoading = transactionsAsync.isLoading;
    final transactionsError = transactionsAsync is AsyncError
        ? (transactionsAsync as AsyncError).error
        : null;
    final hasOperations = transactions.isNotEmpty;
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final todaySpentMinor = transactions
        .where((record) =>
            record.type == TransactionType.expense &&
            _isSameDay(record.date, normalizedToday))
        .fold<int>(0, (sum, record) => sum + record.amountMinor);
    final periodExpenseMinor = transactions
        .where((record) => record.type == TransactionType.expense)
        .fold<int>(0, (sum, record) => sum + record.amountMinor);
    final periodIncomeMinor = transactions
        .where((record) => record.type == TransactionType.income)
        .fold<int>(0, (sum, record) => sum + record.amountMinor);

    final dailyLimitValue = dailyLimitAsync.asData?.value;
    final dailyLimitLabel = dailyLimitAsync.when(
      data: (value) => formatCurrencyMinorNullable(value),
      loading: () => '…',
      error: (e, _) => '—',
    );
    final todaySubtitle = isTransactionsLoading
        ? 'Загрузка…'
        : transactionsError != null
            ? 'Ошибка загрузки'
            : '${formatCurrencyMinor(todaySpentMinor)} из $dailyLimitLabel';
    final todayProgress = (dailyLimitValue ?? 0) <= 0
        ? 0.0
        : (todaySpentMinor / (dailyLimitValue ?? 1)).clamp(0.0, 1.0);

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
                            await read(dailyLimitProvider.future) ?? 0;
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
                    if (periodClosed || daysLeft != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          if (periodClosed) const _ClosedPeriodBadge(),
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
                  return _LimitCards(
                    leftToday: ref.watch(leftTodayMinorProvider),
                    leftPeriod: ref.watch(periodBudgetMinorProvider),
                    onEditLimit: () async {
                      final saved = await showEditDailyLimitSheet(context, ref);
                      if (!context.mounted || !saved) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Лимит сохранён')),
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
                child: isTransactionsLoading
                    ? const LinearProgressIndicator()
                    : ProgressLine(
                        value: todayProgress,
                        label: 'Прогресс дня',
                      ),
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
    required this.leftToday,
    required this.leftPeriod,
    required this.onEditLimit,
  });

  final AsyncValue<int> leftToday;
  final AsyncValue<int> leftPeriod;
  final VoidCallback onEditLimit;

  @override
  Widget build(BuildContext context) {
    String buildLabel(AsyncValue<int> value) {
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
            value: buildLabel(leftToday),
            alignment: TextAlign.left,
            onEdit: onEditLimit,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: buildLabel(leftPeriod),
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
  bool _expanded = false;

  Future<void> _openQuickAdd(BuildContext context) async {
    final sheetNotifier = ref.read(isSheetOpenProvider.notifier);
    sheetNotifier.state = true;
    try {
      final period = ref.read(selectedPeriodRefProvider);
      final result = await showPlannedQuickAddForm(
        context,
        ref: ref,
        type: 'expense',
        period: period,
      );
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('План добавлен')),
        );
      }
    } finally {
      sheetNotifier.state = false;
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
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
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  tooltip: _expanded ? 'Скрыть планы' : 'Показать планы',
                  onPressed: _toggleExpanded,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              _PlannedExpensesList(period: period),
            ],
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
    final itemsAsync = ref.watch(plannedExpensesForPeriodProvider(period));
    final necessityLabelsAsync = ref.watch(necessityLabelsFutureProvider);
    final necessityLabels =
        necessityLabelsAsync.value ?? const <necessity_repo.NecessityLabel>[];
    final necessityById = {
      for (final label in necessityLabels) label.id: label,
    };
    final theme = Theme.of(context);

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'Пока нет планов расходов в этом периоде.',
            style: theme.textTheme.bodyMedium,
          );
        }
        final children = <Widget>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          children.add(
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(formatCurrencyMinor(item.record.amountMinor)),
                  ..._buildNecessityChip(
                    context,
                    item,
                    necessityById,
                  ),
                ],
              ),
              trailing: Checkbox(
                value: item.record.includedInPeriod,
                onChanged: (value) async {
                  final transactionId = item.record.id;
                  if (transactionId == null) {
                    return;
                  }
                  await ref
                      .read(transactionsRepoProvider)
                      .setPlannedIncluded(transactionId, value ?? false);
                  bumpDbTick(ref);
                },
              ),
              onTap: () => showPlannedAddForm(
                context,
                type: PlannedType.expense,
                initialRecord: item.record,
              ),
            ),
          );
          if (i != items.length - 1) {
            children.add(const Divider(height: 12));
          }
        }
        return Column(children: children);
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => Text('Ошибка: $error'),
    );
  }

  List<Widget> _buildNecessityChip(
    BuildContext context,
    PlannedItemView item,
    Map<int, necessity_repo.NecessityLabel> necessityById,
  ) {
    final record = item.record;
    final label = record.necessityLabel;
    final necessity =
        record.necessityId != null ? necessityById[record.necessityId!] : null;
    final labelText = label?.isNotEmpty == true
        ? label!
        : necessity?.name?.isNotEmpty == true
            ? necessity!.name
            : record.criticality > 0
                ? 'Критичность ${record.criticality}'
                : null;
    if (labelText == null) {
      return const [];
    }
    final theme = Theme.of(context);
    final background = _necessityColorFromHex(necessity?.color) ??
        theme.colorScheme.secondaryContainer;
    final brightness = ThemeData.estimateBrightnessForColor(background);
    final labelColor = brightness == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSecondaryContainer;

    return [
      Chip(
        label: Text(labelText),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: labelColor,
          fontWeight: FontWeight.w600,
        ),
        visualDensity: VisualDensity.compact,
        backgroundColor: background,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ];
  }
}

Color? _necessityColorFromHex(String? raw) {
  if (raw == null) {
    return null;
  }
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    return null;
  }
  final hex = normalized.startsWith('#') ? normalized.substring(1) : normalized;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    return null;
  }
  if (hex.length == 6) {
    return Color(0xFF000000 | value);
  }
  if (hex.length == 8) {
    return Color(value);
  }
  return null;
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
