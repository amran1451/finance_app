import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/migrations.dart';
import '../../data/models/manual_backup_entry.dart';
import '../../state/app_providers.dart';
import '../../state/backup_providers.dart';
import '../../state/db_refresh.dart';

class BackupsSettingsScreen extends ConsumerStatefulWidget {
  const BackupsSettingsScreen({super.key});

  @override
  ConsumerState<BackupsSettingsScreen> createState() =>
      _BackupsSettingsScreenState();
}

class _BackupsSettingsScreenState
    extends ConsumerState<BackupsSettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(manualBackupHistoryProvider);
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Резервные копии')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Экспортировать базу данных',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Создайте файл резервной копии и сохраните его в облако или на другое устройство.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isExporting ? null : _exportBackup,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: Text(
                      _isExporting
                          ? 'Создание резервной копии...'
                          : 'Создать резервную копию (.db)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Восстановить из резервной копии',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Выберите файл .db и восстановите данные. Текущая база будет полностью заменена.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _importBackup,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(
                      _isImporting
                          ? 'Восстановление...'
                          : 'Восстановить из файла',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Последние экспортированные копии',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  historyAsync.when(
                    data: (history) {
                      if (history.isEmpty) {
                        return const Text(
                          'Пока нет сохранённых резервных копий. Создайте первую копию, чтобы увидеть её здесь.',
                        );
                      }

                      return Column(
                        children: [
                          for (final entry in history)
                            ListTile(
                              leading: const Icon(Icons.backup_outlined),
                              title: Text(dateFormat.format(entry.createdAt)),
                              subtitle:
                                  Text('Схема v${entry.schemaVersion} • ${entry.fileName}'),
                            ),
                        ],
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => Text('Ошибка загрузки списка: $error'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);
    File? tempBackupFile;
    String? savedPath;
    try {
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.createBackupFile();
      tempBackupFile = File(result.path);

      final targetPath = await _saveBackupFile(
        sourceFile: tempBackupFile,
        fileName: result.entry.fileName,
      );
      if (targetPath == null) {
        return;
      }
      savedPath = targetPath;
      final savedLocation = savedPath!;

      final settingsRepository = ref.read(settingsRepoProvider);
      final savedFileName = p.basename(savedLocation);
      final entry = ManualBackupEntry(
        createdAt: result.entry.createdAt,
        schemaVersion: result.entry.schemaVersion,
        fileName: savedFileName,
      );
      await settingsRepository.addManualBackupEntry(entry);
      bumpDbTick(ref);
      ref.invalidate(manualBackupHistoryProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedLocation.startsWith('content://')
                ? 'Резервная копия сохранена'
                : 'Резервная копия сохранена: $savedLocation',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать копию: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
      if (tempBackupFile != null && tempBackupFile.path != savedPath) {
        await _safeDelete(tempBackupFile);
      }
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Восстановить данные из файла?'),
              content: const Text(
                'Текущие данные будут полностью заменены данными из выбранного файла.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Восстановить'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    File? importFile;
    var shouldDeleteAfter = false;
    try {
      final picked = await _pickBackupFile();
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final platformFile = picked.files.first;
      if (!_hasDbExtension(platformFile)) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Выберите файл резервной копии с расширением .db.'),
          ),
        );
        return;
      }

      final materialized = await _materializeFile(platformFile);
      if (materialized == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать выбранный файл.')),
        );
        return;
      }
      importFile = materialized.file;
      shouldDeleteAfter = materialized.deleteAfter;

      final backupService = ref.read(backupServiceProvider);
      final backupVersion =
          await backupService.readUserVersionFromFile(importFile.path);
      if (backupVersion > AppMigrations.latestVersion) {
        if (shouldDeleteAfter) {
          await _safeDelete(importFile);
          shouldDeleteAfter = false;
        }
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Невозможно восстановить'),
            content: Text(
              'Файл создан в более новой версии приложения (v$backupVersion). '
              'Обновите приложение до последней версии и попробуйте снова.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
        return;
      }

      setState(() => _isImporting = true);
      await backupService.importDatabase(importFile.path);
      bumpDbTick(ref);
      ref.invalidate(manualBackupHistoryProvider);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Восстановление завершено'),
          content: const Text('Восстановлено. Перезапуск не требуется.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отлично'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось восстановить: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
      if (shouldDeleteAfter && importFile != null) {
        await _safeDelete(importFile);
      }
    }
  }

  Future<String?> _saveBackupFile({
    required File sourceFile,
    required String fileName,
  }) async {
    final bytes = await sourceFile.readAsBytes();

    Future<String?> attempt(FileType type, {List<String>? allowedExtensions}) {
      return FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: fileName,
        type: type,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      );
    }

    try {
      return await attempt(
        FileType.custom,
        allowedExtensions: const ['db'],
      );
    } on PlatformException catch (error) {
      if (_isUnsupportedFilterError(error)) {
        return attempt(FileType.any);
      }
      rethrow;
    }
  }

  Future<FilePickerResult?> _pickBackupFile() async {
    try {
      return await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'],
        withData: true,
      );
    } on PlatformException catch (error) {
      if (_isUnsupportedFilterError(error)) {
        return FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: true,
        );
      }
      rethrow;
    }
  }

  bool _hasDbExtension(PlatformFile file) {
    final extension = file.extension ?? p.extension(file.name);
    return extension.replaceFirst('.', '').toLowerCase() == 'db';
  }

  bool _isUnsupportedFilterError(PlatformException error) {
    return error.code == 'FilePicker' &&
        (error.message?.contains('Unsupported filter') ?? false);
  }

  Future<({File file, bool deleteAfter})?> _materializeFile(
    PlatformFile file,
  ) async {
    if (file.path != null) {
      return (file: File(file.path!), deleteAfter: false);
    }
    final bytes = file.bytes;
    if (bytes == null) {
      return null;
    }
    final directory = await getTemporaryDirectory();
    final tempPath = p.join(
      directory.path,
      'import-${DateTime.now().millisecondsSinceEpoch}-${file.name}',
    );
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes, flush: true);
    return (file: tempFile, deleteAfter: true);
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ignore cleanup errors
    }
  }
}
