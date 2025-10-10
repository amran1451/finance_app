import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/accounts/account_create_stub.dart';
import '../ui/accounts/account_edit_stub.dart';
import '../ui/accounts/accounts_list_stub.dart';
import '../ui/analytics/analytics_screen.dart';
import '../ui/categories/category_create_stub.dart';
import '../ui/entry/amount_screen.dart';
import '../ui/entry/category_screen.dart';
import '../ui/entry/review_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/operations/operations_screen.dart';
import '../ui/planned/planned_expense_stub.dart';
import '../ui/planned/planned_income_stub.dart';
import '../ui/planned/planned_library_screen.dart';
import '../ui/planned/planned_master_detail_screen.dart';
import '../ui/planned/planned_savings_stub.dart';
import '../ui/settings/settings_placeholder.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavigationShell(
            navigationShell: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: RouteNames.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                name: RouteNames.analytics,
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: RouteNames.settings,
                builder: (context, state) => const SettingsPlaceholder(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/operations',
        name: RouteNames.operations,
        builder: (context, state) => const OperationsScreen(),
      ),
      GoRoute(
        path: '/entry/amount',
        name: RouteNames.entryAmount,
        builder: (context, state) => const AmountScreen(),
      ),
      GoRoute(
        path: '/entry/category',
        name: RouteNames.entryCategory,
        builder: (context, state) => const CategoryScreen(),
      ),
      GoRoute(
        path: '/entry/review',
        name: RouteNames.entryReview,
        builder: (context, state) => const ReviewScreen(),
      ),
      GoRoute(
        path: '/planned/income',
        name: RouteNames.plannedIncome,
        builder: (context, state) => const PlannedIncomeStub(),
      ),
      GoRoute(
        path: '/planned/expense',
        name: RouteNames.plannedExpense,
        builder: (context, state) => const PlannedExpenseStub(),
      ),
      GoRoute(
        path: '/planned/savings',
        name: RouteNames.plannedSavings,
        builder: (context, state) => const PlannedSavingsStub(),
      ),
      GoRoute(
        path: '/planned/library',
        name: RouteNames.plannedLibrary,
        builder: (context, state) {
          final select = state.uri.queryParameters['select'] == '1';
          final type = state.uri.queryParameters['type'];
          return PlannedLibraryScreen(
            selectForAssignment: select,
            assignmentType: type,
          );
        },
      ),
      GoRoute(
        path: '/planned/master/:id',
        name: RouteNames.plannedMasterDetail,
        builder: (context, state) {
          final idRaw = state.pathParameters['id'];
          final masterId = int.tryParse(idRaw ?? '');
          if (masterId == null) {
            return const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Некорректный идентификатор плана'),
                ),
              ),
            );
          }
          return PlannedMasterDetailScreen(masterId: masterId);
        },
      ),
      GoRoute(
        path: '/accounts',
        name: RouteNames.accounts,
        builder: (context, state) => const AccountsListStub(),
      ),
      GoRoute(
        path: '/accounts/new',
        name: RouteNames.accountCreate,
        builder: (context, state) => const AccountCreateStub(),
      ),
      GoRoute(
        path: '/accounts/edit',
        name: RouteNames.accountEdit,
        builder: (context, state) {
          final rawId = state.uri.queryParameters['id'];
          final accountId = int.tryParse(rawId ?? '');
          if (accountId == null) {
            return const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Некорректный идентификатор счёта'),
                ),
              ),
            );
          }
          return AccountEditStub(accountId: accountId);
        },
      ),
      GoRoute(
        path: '/categories/new',
        name: RouteNames.categoryCreate,
        builder: (context, state) => const CategoryCreateStub(),
      ),
    ],
  );
});

class RouteNames {
  static const String home = 'home';
  static const String analytics = 'analytics';
  static const String settings = 'settings';
  static const String operations = 'operations';
  static const String entryAmount = 'entry-amount';
  static const String entryCategory = 'entry-category';
  static const String entryReview = 'entry-review';
  static const String plannedIncome = 'planned-income';
  static const String plannedExpense = 'planned-expense';
  static const String plannedSavings = 'planned-savings';
  static const String plannedLibrary = 'planned-library';
  static const String plannedMasterDetail = 'planned-master-detail';
  static const String accounts = 'accounts';
  static const String accountCreate = 'account-create';
  static const String accountEdit = 'account-edit';
  static const String categoryCreate = 'category-create';
}

class ScaffoldWithNavigationShell extends ConsumerWidget {
  const ScaffoldWithNavigationShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _onItemTapped(BuildContext context, int index) {
    navigationShell.goBranch(index,
        initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => _onItemTapped(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Дом',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Аналитика',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
