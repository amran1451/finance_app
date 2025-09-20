import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/app_providers.dart';
import '../../state/entry_flow_providers.dart';
import '../../state/planned_providers.dart';
import '../../utils/formatting.dart';
import '../widgets/callout_card.dart';
import '../widgets/period_selector.dart';
import '../widgets/progress_line.dart';
import '../../routing/app_router.dart';
import '../planned/planned_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final summary = ref.watch(periodSummaryProvider);
    final accounts = ref.watch(accountsProvider);
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
              _buildRemainingSection(context, summary, hasOperations),
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
                child: accounts.isEmpty
                    ? const Text('Добавьте первый счёт, чтобы видеть баланс здесь.')
                    : Column(
                        children: [
                          for (final account in accounts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: account.color.withOpacity(0.15),
                                child: Icon(
                                  Icons.account_balance_wallet,
                                  color: account.color,
                                ),
                              ),
                              title: Text(account.name),
                              subtitle: Text(formatCurrency(account.balance)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.pushNamed(
                                RouteNames.accountEdit,
                                extra: account.name,
                              ),
                            ),
                        ],
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

  Widget _buildRemainingSection(
    BuildContext context,
    PeriodSummary summary,
    bool hasOperations,
  ) {
    if (!hasOperations) {
      return CalloutCard(
        title: 'Остаток бюджета',
        subtitle: 'Здесь появятся данные, когда вы добавите операции.',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось на день',
            value: formatCurrency(summary.remainingPerDay),
            alignment: TextAlign.left,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RemainingInfoCard(
            label: 'Осталось в этом бюджете',
            value: formatCurrency(summary.remainingBudget),
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
    final incomeTotal =
        ref.watch(plannedTotalByTypeProvider(PlannedType.income));
    final expenseTotal =
        ref.watch(plannedTotalByTypeProvider(PlannedType.expense));
    final savingTotal =
        ref.watch(plannedTotalByTypeProvider(PlannedType.saving));

    return Column(
      children: [
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
  }
}

class _RemainingInfoCard extends StatelessWidget {
  const _RemainingInfoCard({
    required this.label,
    required this.value,
    required this.alignment,
  });

  final String label;
  final String value;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEnd = alignment == TextAlign.right || alignment == TextAlign.end;
    final crossAxis = isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;

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
            Text(
              label,
              textAlign: alignment,
              style: Theme.of(context).textTheme.labelSmall,
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
