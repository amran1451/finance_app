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
import '../../utils/formatting.dart';
import '../../utils/ru_plural.dart';
import '../planned/planned_sheet.dart';
import '../payouts/add_payout_sheet.dart';
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
    final periodBounds = ref.watch(halfPeriodBoundsProvider);
    final periodStart = periodBounds.start;
    final periodEndExclusive = periodBounds.endExclusive;
    final daysLeft = ref.watch(daysToPeriodEndProvider);

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
                    const Expanded(
                      child: PeriodSelector(dense: true),
                    ),
                    const SizedBox(width: 12),
                    _DaysLeftBadge(days: daysLeft),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildRemainingSection(
                context,
                ref,
                hasOperations,
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
                subtitle: 'Быстрый доступ к будущим операциям',
                child: _PlannedOverview(ref: ref),
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

  Widget _buildRemainingSection(
    BuildContext context,
    WidgetRef ref,
    bool hasOperations,
  ) {
    if (!hasOperations) {
      return CalloutCard(
        title: 'Остаток бюджета',
        subtitle: 'Здесь появятся данные, когда вы добавите операции.',
      );
    }

    final leftTodayAsync = ref.watch(leftTodayMinorProvider);
    final leftPeriodAsync = ref.watch(leftInPeriodMinorProvider);

    final leftTodayLabel = leftTodayAsync.when(
      data: (value) => formatCurrencyMinor(value),
      loading: () => '…',
      error: (_, __) => '—',
    );
    final leftPeriodLabel = leftPeriodAsync.when(
      data: (value) => formatCurrencyMinor(value),
      loading: () => '…',
      error: (_, __) => '—',
    );

    return Row(
      children: [
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось на день',
            value: leftTodayLabel,
            alignment: TextAlign.left,
            onEdit: () => _showDailyLimitSheet(context, ref),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: leftPeriodLabel,
            alignment: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _showDailyLimitSheet(BuildContext context, WidgetRef ref) async {
    final currentValue = await ref.read(dailyLimitProvider.future);

    final controller = TextEditingController(
      text: currentValue != null
          ? (currentValue / 100).toStringAsFixed(2)
          : '',
    );
    String? errorText;
    var isSaving = false;
    var saved = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> save() async {
                if (isSaving) {
                  return;
                }
                setState(() {
                  errorText = null;
                  isSaving = true;
                });

                final raw = controller.text.trim().replaceAll(',', '.');
                int? minorValue;
                if (raw.isEmpty) {
                  minorValue = null;
                } else {
                  final parsed = double.tryParse(raw);
                  if (parsed == null) {
                    setState(() {
                      errorText = 'Введите число';
                      isSaving = false;
                    });
                    return;
                  }
                  minorValue = (parsed * 100).round();
                }

                final manager = ref.read(dailyLimitManagerProvider);
                final message = await manager.saveDailyLimitMinor(minorValue);
                if (message != null) {
                  setState(() {
                    errorText = message;
                    isSaving = false;
                  });
                  return;
                }

                saved = true;
                Navigator.of(sheetContext).pop();
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Лимит на день',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Сумма',
                      prefixText: '₽ ',
                      hintText: 'Например, 1500',
                      errorText: errorText,
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () {
                                controller.clear();
                                setState(() => errorText = null);
                              },
                        child: const Text('Очистить'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: isSaving ? null : save,
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лимит сохранён')),
      );
    }
  }
}

class _DaysLeftBadge extends StatelessWidget {
  final int? days;

  const _DaysLeftBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = days == null ? '—' : ruDaysShort(days!);
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
          Text(txt, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _PlannedOverview extends StatelessWidget {
  const _PlannedOverview({
    required this.ref,
  });

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final payoutAsync = ref.watch(currentPayoutProvider);
    return payoutAsync.when(
      data: (payout) {
        if (payout == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final saved = await showAddPayoutSheet(
                    context,
                    type: PayoutType.salary,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (saved) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Выплата добавлена')),
                    );
                  }
                },
                icon: const Icon(Icons.payments),
                label: const Text('Добавить выплату'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Добавьте ближайшую выплату, чтобы расчёт бюджета был точным.',
              ),
            ],
          );
        }

        final incomeTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.income));
        final expenseTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.expense));
        final savingTotalAsync =
            ref.watch(plannedIncludedTotalProvider(PlannedType.saving));
        final plannedPool = ref.watch(plannedPoolMinorProvider);

        return Column(
          children: [
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
              onTap: () =>
                  showPlannedSheet(context, type: PlannedType.income),
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
              onTap: () =>
                  showPlannedSheet(context, type: PlannedType.expense),
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
              onTap: () =>
                  showPlannedSheet(context, type: PlannedType.saving),
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
        data: (computed) {
          return Text(
            'Текущий: ${formatCurrencyMinor(account.startBalanceMinor)}\n'
            'Рассчитанный: ${formatCurrencyMinor(computed)}',
          );
        },
        loading: () => const Text('Загрузка баланса…'),
        error: (error, _) => Text('Ошибка расчёта: $error'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        RouteNames.accountEdit,
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
