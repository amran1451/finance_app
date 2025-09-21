import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/bootstrap/app_bootstrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'ru_RU';
  await initializeDateFormatting('ru_RU');

  final bootstrapper = AppBootstrapper();
  await bootstrapper.run();

  runApp(const ProviderScope(child: FinanceApp()));
}
