import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'ru_RU';
  await initializeDateFormatting('ru_RU');

  assert(() {
    Sqflite.setDebugModeOn(true);
    return true;
  }());

  runApp(const ProviderScope(child: FinanceApp()));
}
