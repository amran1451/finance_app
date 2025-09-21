import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart' as db_models;
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../utils/formatting.dart';

class AccountsListStub extends ConsumerWidget {
  const AccountsListStub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsDbProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои счета'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed(RouteNames.accountCreate),
            icon: const Icon(Icons.add),
            tooltip: 'Добавить счёт',
          ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить счета: $error'),
          ),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Добавьте первый счёт, чтобы следить за балансом.'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              return _AccountListTile(account: account);
            },
          );
        },
      ),
    );
  }
}

class _AccountListTile extends ConsumerWidget {
  const _AccountListTile({required this.account});

  final db_models.Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountId = account.id;
    if (accountId == null) {
      return const SizedBox.shrink();
    }
    final computedAsync = ref.watch(computedBalanceProvider(accountId));
    final reconcile = ref.read(reconcileAccountProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance_wallet),
              ),
              title: Text(account.name),
              subtitle: Text(
                'Текущий: ${formatCurrencyMinor(account.startBalanceMinor)}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => context.pushNamed(
                  RouteNames.accountEdit,
                  extra: account.name,
                ),
              ),
            ),
            computedAsync.when(
              data: (computed) {
                final difference = computed - account.startBalanceMinor;
                final differenceText = difference == 0
                    ? 'Расхождений нет'
                    : 'Расхождение: ${formatCurrencyMinor(difference)}';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Рассчитанный баланс: ${formatCurrencyMinor(computed)}'),
                      const SizedBox(height: 4),
                      Text(
                        differenceText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (difference != 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              await reconcile(accountId);
                              ref.invalidate(accountsDbProvider);
                              ref.invalidate(computedBalanceProvider(accountId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Баланс выровнен')),
                              );
                            },
                            child: const Text('Выровнять'),
                          ),
                        ),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Не удалось рассчитать баланс: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
