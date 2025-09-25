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
import '../../utils/ru_plural.dart';
import '../planned/planned_sheet.dart';
import '../payouts/payout_edit_sheet.dart';
import 'daily_limit_sheet.dart';
import '../widgets/callout_card.dart';
import '../widgets/period_selector.dart';
import '../widgets/progress_line.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyLimitAsync = ref.watch(dailyLimitProvider);
    final accountsAsync = ref.watch(accountsDbProvider);
    final hideFab = ref.watch(isSheetOpenProvider);
    final entryController = ref.read(entryFlowControllerProvider.notifier);
    final transactionsAsync = ref.watch(halfPeriodTransactionsProvider);
    final (periodStart, periodEndExclusive) = ref.watch(periodBoundsProvider);
    final label = ref.watch(periodLabelProvider);
    final daysLeft = ref.watch(daysFromPayoutToPeriodEndProvider);
    final payoutAsync = ref.watch(payoutForSelectedPeriodProvider);
    final suggestedType = ref.watch(payoutSuggestedTypeProvider);
    final generalPayoutLabel =
        'Добавить выплату (по периоду: ${payoutTypeLabel(suggestedType)})';
    final plannedRemainderAsync = ref.watch(plannedRemainderForPeriodProvider);
    final plannedRemainderSubtitle = plannedRemainderAsync.when(
      data: (value) {
        if (value == null) {
          return 'Остаток на планы: —';
        }
        return 'Остаток на планы: ${formatCurrencyMinor(value.remainderMinor)}';
      },
      loading: () => 'Остаток на планы: …',
      error: (error, _) => 'Остаток на планы: —',
    );

    void openPlannedSheet(PlannedType type) {
      final notifier = ref.read(isSheetOpenProvider.notifier);
      notifier.state = true;
      showPlannedSheet(
        context,
        type: type,
        onClosed: () {
          notifier.state = false;
        },
      );
    }

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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: PeriodSelector(dense: true, label: label),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.centerRight,
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
                          : Row(
                              key: ValueKey(daysLeft),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 12),
                                _DaysLeftBadge(days: daysLeft),
                              ],
                            ),
                    ),
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
                title: 'Запланировано',
                subtitle: plannedRemainderSubtitle,
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
                child: _PlannedOverview(
                  ref: ref,
                  onOpenPlanned: openPlannedSheet,
                ),
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

class _PlannedOverview extends StatelessWidget {
  const _PlannedOverview({
    required this.ref,
    required this.onOpenPlanned,
  });

  final WidgetRef ref;
  final void Function(PlannedType type) onOpenPlanned;

  @override
  Widget build(BuildContext context) {
    final payoutAsync = ref.watch(payoutForSelectedPeriodProvider);
    final plannedRemainderAsync = ref.watch(plannedRemainderForPeriodProvider);
    return payoutAsync.when(
      data: (payout) {
        if (payout == null) {
          return const Text(
            'Добавьте ближайшую выплату, чтобы расчёт бюджета был точным.',
          );
        }

        final incomeTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.income));
        final expenseTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.expense));
        final savingTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.saving));
        final plannedPool = ref.watch(plannedPoolMinorProvider);
        final remainderData =
            plannedRemainderAsync.maybeWhen<PlannedRemainder?>(
          data: (value) => value,
          orElse: () => null,
        );
        final deficitMinor = remainderData?.deficitMinor ?? 0;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Быстрый доступ к будущим операциям',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
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
            plannedPool.when(
              data: (value) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Доступно на планы'),
                subtitle: Text(formatCurrencyMinor(value)),
              ),
              loading: () => const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Доступно на планы'),
                subtitle: Text('Загрузка…'),
              ),
              error: (_, __) => const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Доступно на планы'),
                subtitle: Text('Не удалось загрузить'),
              ),
            ),
            const Divider(height: 0),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Доходы'),
              subtitle: incomeTotalAsync.when(
                data: (value) => Text(formatCurrencyMinor(value)),
                loading: () => const Text('Загрузка…'),
                error: (error, _) => Text('Ошибка: $error'),
              ),
              onTap: () => onOpenPlanned(PlannedType.income),
            ),
            const Divider(height: 0),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Расходы'),
              subtitle: expenseTotalAsync.when(
                data: (value) => Text(formatCurrencyMinor(value)),
                loading: () => const Text('Загрузка…'),
                error: (error, _) => Text('Ошибка: $error'),
              ),
              onTap: () => onOpenPlanned(PlannedType.expense),
            ),
            const Divider(height: 0),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Сбережения'),
              subtitle: savingTotalAsync.when(
                data: (value) => Text(formatCurrencyMinor(value)),
                loading: () => const Text('Загрузка…'),
                error: (error, _) => Text('Ошибка: $error'),
              ),
              onTap: () => onOpenPlanned(PlannedType.saving),
            ),
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
