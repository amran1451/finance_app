import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/account.dart' as db_models;
import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../state/db_refresh.dart';
import '../../utils/formatting.dart';
import 'account_form_result.dart';

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
            onPressed: () async {
              final result = await context.pushNamed(RouteNames.accountCreate);
              _handleFormResult(context, result);
            },
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

void _handleFormResult(BuildContext context, Object? result) {
  if (result is! AccountFormResult) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  String message;
  switch (result) {
    case AccountFormResult.created:
      message = 'Счёт создан';
      break;
    case AccountFormResult.updated:
      message = 'Изменения сохранены';
      break;
    case AccountFormResult.deleted:
      message = 'Счёт удалён';
      break;
  }

  messenger.showSnackBar(SnackBar(content: Text(message)));
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

    Future<void> openEdit() async {
      final result = await context.pushNamed(
        RouteNames.accountEdit,
        queryParameters: {'id': accountId.toString()},
      );
      _handleFormResult(context, result);
    }

    return computedAsync.when(
      data: (computed) {
        final difference = computed - account.startBalanceMinor;
        final hasDifference = difference != 0;
        final differenceText = hasDifference
            ? 'Δ с учётом: ${formatCurrencyMinor(difference)}'
            : 'Баланс совпадает с учётом';

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
                  subtitle: Text('Баланс: ${formatCurrencyMinor(computed)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: openEdit,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        differenceText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (hasDifference) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              await reconcile(accountId);
                              bumpDbTick(ref);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Баланс выровнен'),
                                ),
                              );
                            },
                            child: const Text('Выровнять'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Card(
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
                subtitle: const Text('Баланс рассчитывается…'),
                trailing: IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: openEdit,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
      error: (error, _) => Card(
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
                subtitle: const Text('Не удалось рассчитать баланс'),
                trailing: IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: openEdit,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Не удалось рассчитать баланс: $error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
