import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'routing/app_router.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final mode = ref.watch(themeModeProvider);
    final bootstrap = ref.watch(appBootstrapProvider);

    return bootstrap.when(
      data: (_) => _buildMainApp(router: router, mode: mode),
      loading: () => _buildStatusApp(
        mode: mode,
        child: const _BootstrapLoadingScreen(),
      ),
      error: (error, stackTrace) => _buildStatusApp(
        mode: mode,
        child: _BootstrapErrorScreen(error: error, stackTrace: stackTrace),
      ),
    );
  }

  Widget _buildMainApp({required GoRouter router, required ThemeMode mode}) {
    return MaterialApp.router(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Finance App',
      themeMode: mode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      supportedLocales: _supportedLocales,
      locale: _locale,
      localizationsDelegates: _localizationsDelegates,
    );
  }

  Widget _buildStatusApp({required ThemeMode mode, required Widget child}) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Finance App',
      themeMode: mode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      supportedLocales: _supportedLocales,
      locale: _locale,
      localizationsDelegates: _localizationsDelegates,
      home: child,
    );
  }
}

const _supportedLocales = [Locale('ru', 'RU')];
const _locale = Locale('ru', 'RU');
const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _BootstrapErrorScreen extends ConsumerWidget {
  const _BootstrapErrorScreen({
    required this.error,
    this.stackTrace,
  });

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Не удалось инициализировать приложение',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
              ),
              if (stackTrace != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  stackTrace.toString(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => ref.invalidate(appBootstrapProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
