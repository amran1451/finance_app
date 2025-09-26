import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_service.dart';
import '../data/models/manual_backup_entry.dart';
import 'app_providers.dart';
import 'db_refresh.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return BackupService(database: database);
});

final manualBackupHistoryProvider =
    FutureProvider<List<ManualBackupEntry>>((ref) async {
  ref.watch(dbTickProvider);
  final repository = ref.watch(settingsRepoProvider);
  return repository.getManualBackupHistory();
});
