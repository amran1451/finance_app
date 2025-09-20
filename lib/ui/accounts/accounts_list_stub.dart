import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/app_router.dart';
import '../../state/app_providers.dart';
import '../../utils/formatting.dart';

class AccountsListStub extends ConsumerWidget {
  const AccountsListStub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);

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
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: accounts.length,
        itemBuilder: (context, index) {
          final account = accounts[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: account.color.withOpacity(0.15),
                child: Icon(Icons.account_balance_wallet, color: account.color),
              ),
              title: Text(account.name),
              subtitle: Text(formatCurrency(account.balance)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(
                RouteNames.accountEdit,
                extra: account.name,
              ),
            ),
          );
        },
      ),
    );
  }
}
