import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart' as db_models;
import '../../data/models/payout.dart';
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/budget_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/planned_providers.dart';
import '../../utils/formatting.dart';
import '../planned/planned_sheet.dart';
import '../payouts/add_payout_sheet.dart';
import '../widgets/callout_card.dart';
import '../widgets/period_selector.dart';
import '../widgets/progress_line.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final summary = ref.watch(periodSummaryProvider);
    final dailyLimitAsync = ref.watch(dailyLimitProvider);
    final periodBudgetAsync = ref.watch(periodBudgetMinorProvider);
    final accountsAsync = ref.watch(accountsDbProvider);
    final hasOperations = ref.watch(hasOperationsProvider);
    final hideFab = ref.watch(isSheetOpenProvider);
    final entryController = ref.read(entryFlowControllerProvider.notifier);

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
              const PeriodSelector(),
              const SizedBox(height: 16),
              _buildRemainingSection(
                context,
                ref,
                hasOperations,
                dailyLimitAsync,
                periodBudgetAsync,
              ),
              const SizedBox(height: 16),
              CalloutCard(
                title: 'Траты сегодня',
                subtitle:
                    '${formatCurrency(summary.todaySpent)} из ${formatCurrency(summary.todayBudget)}',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.operations),
                child: ProgressLine(
                  value: summary.dailyProgress,
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
                '${period.title}: операции',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (!hasOperations)
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
              else
                FilledButton.tonalIcon(
                  onPressed: () => context.pushNamed(RouteNames.operations),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Открыть операции периода'),
                ),
            ],
          ),
        ),
      ),
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

                ref.invalidate(dailyLimitProvider);
                ref.invalidate(periodBudgetMinorProvider);
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

  Widget _buildRemainingSection(
    BuildContext context,
    WidgetRef ref,
    bool hasOperations,
    AsyncValue<int?> dailyLimitAsync,
    AsyncValue<int> periodBudgetAsync,
  ) {
    if (!hasOperations) {
      return CalloutCard(
        title: 'Остаток бюджета',
        subtitle: 'Здесь появятся данные, когда вы добавите операции.',
      );
    }

    final dailyLimitLabel = dailyLimitAsync.when(
      data: (value) => formatCurrencyMinorNullable(value),
      loading: () => '…',
      error: (e, st) => '—',
    );
    final periodBudgetLabel = periodBudgetAsync.when(
      data: (value) => formatCurrencyMinor(value),
      loading: () => '…',
      error: (e, st) => '—',
    );

    return Row(
      children: [
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось на день',
            value: dailyLimitLabel,
            alignment: TextAlign.left,
            onEdit: () => _showDailyLimitSheet(context, ref),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: periodBudgetLabel,
            alignment: TextAlign.right,
          ),
        ),
      ],
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
                    ref,
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

        final incomeTotal =
            ref.watch(plannedTotalByTypeProvider(PlannedType.income));
        final expenseTotal =
            ref.watch(plannedTotalByTypeProvider(PlannedType.expense));
        final savingTotal =
            ref.watch(plannedTotalByTypeProvider(PlannedType.saving));
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
              subtitle: Text(formatCurrency(incomeTotal)),
              onTap: () =>
                  showPlannedSheet(context, ref, type: PlannedType.income),
            ),
            const Divider(height: 0),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Расходы'),
              subtitle: Text(formatCurrency(expenseTotal)),
              onTap: () =>
                  showPlannedSheet(context, ref, type: PlannedType.expense),
            ),
            const Divider(height: 0),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Сбережения'),
              subtitle: Text(formatCurrency(savingTotal)),
              onTap: () =>
                  showPlannedSheet(context, ref, type: PlannedType.saving),
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
