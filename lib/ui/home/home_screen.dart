import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/app_providers.dart';
import '../../utils/formatting.dart';
import '../widgets/callout_card.dart';
import '../widgets/period_selector.dart';
import '../widgets/progress_line.dart';
import '../../routing/app_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activePeriodProvider);
    final summary = ref.watch(periodSummaryProvider);
    final accounts = ref.watch(accountsProvider);
    final hasOperations = ref.watch(hasOperationsProvider);

    return SafeArea(
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
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.trending_up),
                    title: const Text('Доходы'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed(RouteNames.plannedIncome),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.trending_down),
                    title: const Text('Расходы'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed(RouteNames.plannedExpense),
                  ),
                  const Divider(height: 0),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.savings),
                    title: const Text('Сбережения'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed(RouteNames.plannedSavings),
                  ),
                ],
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

    return Column(
      children: [
        CalloutCard(
          title: 'Осталось в этом бюджете',
          subtitle: formatCurrency(summary.remainingBudget),
          borderless: true,
          centered: true,
        ),
        const SizedBox(height: 12),
        CalloutCard(
          title: 'Осталось на день',
          subtitle: formatCurrency(summary.remainingPerDay),
          borderless: true,
          centered: true,
        ),
      ],
    );
  }
}
