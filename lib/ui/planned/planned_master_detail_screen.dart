import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction_record.dart';
import '../../data/repositories/planned_master_repository.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../state/app_providers.dart';
import '../../state/planned_providers.dart';
import '../../utils/date_ru.dart';
import '../../utils/formatting.dart';
import '../../utils/period_utils.dart';
import 'planned_assign_to_period_sheet.dart';
import 'planned_master_edit_sheet.dart';

class PlannedMasterDetailScreen extends ConsumerStatefulWidget {
  const PlannedMasterDetailScreen({super.key, required this.masterId});

  final int masterId;

  @override
  ConsumerState<PlannedMasterDetailScreen> createState() =>
      _PlannedMasterDetailScreenState();
}

class _PlannedMasterDetailScreenState
    extends ConsumerState<PlannedMasterDetailScreen> {
  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final masterAsync = ref.watch(plannedMasterByIdProvider(widget.masterId));
    final periodLabel = ref.watch(periodLabelProvider);
    final bounds = ref.watch(periodBoundsProvider);
    final categoriesMap = ref.watch(categoriesMapProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали плана'),
      ),
      body: masterAsync.when(
        data: (master) {
          if (master == null) {
            return const Center(child: Text('План не найден'));
          }
          final categoryName = master.categoryId != null
              ? categoriesMap[master.categoryId!]?.name
              : null;
          final instancesAsync =
              ref.watch(plannedInstancesForSelectedPeriodProvider(master.type));
          return RefreshIndicator(
            onRefresh: () async {
              bumpDbTick(ref);
            },
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _MasterHeader(
                  master: master,
                  categoryName: categoryName,
                  onEdit: () {
                    showPlannedMasterEditSheet(
                      context,
                      initial: master,
                    );
                  },
                  onAssign: () {
                    showPlannedAssignToPeriodSheet(
                      context,
                      master: master,
                    );
                  },
                  onToggleArchive: () {
                    _toggleArchive(master);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Экземпляры ($periodLabel)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                instancesAsync.when(
                  data: (items) {
                    final filtered = items
                        .where((item) => item.plannedId == master.id)
                        .toList();
                    if (filtered.isEmpty) {
                      return const Text(
                        'В выбранном периоде нет экземпляров. Назначьте план, чтобы он появился здесь.',
                      );
                    }
                    return Column(
                      children: [
                        for (final item in filtered)
                          _InstanceTile(
                            record: item,
                            periodLabel: periodBadge(bounds.$1, bounds.$2),
                            onToggle: (value) => _toggleIncluded(item, value),
                            onEdit: () => _editInstance(master, item),
                            onDelete: () => _deleteInstance(item),
                            onDeleteMaster: () => _deleteMasterFromPlan(item),
                          ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text('Ошибка: $error'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка: $error')),
      ),
    );
  }

  Future<void> _toggleArchive(PlannedMaster master) async {
    final id = master.id;
    if (id == null) {
      return;
    }
    final repo = ref.read(plannedMasterRepoProvider);
    final updated = await repo.update(id, archived: !master.archived);
    if (!mounted) {
      return;
    }
    if (updated) {
      bumpDbTick(ref);
    }
  }

  Future<void> _editInstance(PlannedMaster master, TransactionRecord record) async {
    final (anchor1, anchor2) = ref.read(anchorDaysProvider);
    final period = periodRefForDate(record.date, anchor1, anchor2);
    await showPlannedAssignToPeriodSheet(
      context,
      master: master,
      initialPeriod: period,
      initialRecord: record,
    );
  }

  Future<void> _toggleIncluded(TransactionRecord record, bool value) async {
    final id = record.id;
    if (id == null) {
      return;
    }
    final repo = ref.read(transactionsRepoProvider);
    await repo.setPlannedIncluded(id, value);
    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }

  Future<void> _deleteInstance(TransactionRecord record) async {
    final id = record.id;
    if (id == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить экземпляр?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    final repo = ref.read(transactionsRepoProvider);
    await repo.delete(id);
    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }

  Future<void> _deleteMasterFromPlan(TransactionRecord record) async {
    final masterId = record.plannedId;
    if (masterId == null) {
      return;
    }
    final choice = await showDialog<_DeleteMasterChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить план из общего плана'),
        content: const Text(
          'Удалить сам план и все его назначения во всех периодах?',
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DeleteMasterChoice.deleteAll),
            child: const Text('Удалить всё'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_DeleteMasterChoice.deleteInstance),
            child: const Text('Удалить только текущий экземпляр'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (choice == null) {
      return;
    }

    final transactionsRepo = ref.read(transactionsRepoProvider);
    switch (choice) {
      case _DeleteMasterChoice.deleteAll:
        final plannedRepo = ref.read(plannedMasterRepoProvider);
        try {
          await plannedRepo.delete(masterId);
        } on StateError {
          await transactionsRepo.deleteInstancesByPlannedId(masterId);
          await plannedRepo.delete(masterId);
        }
        break;
      case _DeleteMasterChoice.deleteInstance:
        final id = record.id;
        if (id == null) {
          return;
        }
        await transactionsRepo.delete(id);
        break;
    }

    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }

}

class _MasterHeader extends StatelessWidget {
  const _MasterHeader({
    required this.master,
    required this.categoryName,
    required this.onEdit,
    required this.onAssign,
    required this.onToggleArchive,
  });

  final PlannedMaster master;
  final String? categoryName;
  final VoidCallback onEdit;
  final VoidCallback onAssign;
  final VoidCallback onToggleArchive;

  @override
  Widget build(BuildContext context) {
    final amount = master.defaultAmountMinor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(_typeLabel(master.type))),
                const SizedBox(width: 8),
                if (master.archived)
                  const Chip(
                    avatar: Icon(Icons.archive_outlined, size: 16),
                    label: Text('В архиве'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              master.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (categoryName != null) ...[
              const SizedBox(height: 8),
              Text('Категория: $categoryName'),
            ],
            if (amount != null) ...[
              const SizedBox(height: 8),
              Text('Сумма по умолчанию: ${formatCurrencyMinor(amount)}'),
            ],
            if (master.note != null && master.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Примечание: ${master.note}'),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Редактировать'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Назначить в период'),
                ),
                OutlinedButton.icon(
                  onPressed: onToggleArchive,
                  icon: Icon(master.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined),
                  label: Text(master.archived ? 'Разархивировать' : 'Архивировать'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Доход';
      case 'saving':
        return 'Сбережение';
      case 'expense':
      default:
        return 'Расход';
    }
  }

}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile({
    required this.record,
    required this.periodLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteMaster,
  });

  final TransactionRecord record;
  final String periodLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDeleteMaster;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(periodLabel)),
                const Spacer(),
                Checkbox(
                  value: record.includedInPeriod,
                  onChanged: (value) {
                    if (value != null) {
                      onToggle(value);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatCurrencyMinor(record.amountMinor),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить'),
                ),
                PopupMenuButton<_InstanceMenuAction>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Действия',
                  onSelected: (action) {
                    switch (action) {
                      case _InstanceMenuAction.deleteInstance:
                        onDelete();
                        break;
                      case _InstanceMenuAction.deleteMaster:
                        onDeleteMaster();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _InstanceMenuAction.deleteInstance,
                      child: Text('Удалить экземпляр'),
                    ),
                    PopupMenuItem(
                      value: _InstanceMenuAction.deleteMaster,
                      child: Text('Удалить план и все экземпляры…'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeleteMasterChoice {
  deleteAll,
  deleteInstance,
}

enum _InstanceMenuAction { deleteInstance, deleteMaster }

String periodBadge(DateTime start, DateTime endEx) {
  final month = ruMonthShort(start.month);
  final to = endEx.subtract(const Duration(days: 1)).day;
  return '$month ${start.day}–$to';
}
