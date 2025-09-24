import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/planned_master_repository.dart';
import '../../routing/app_router.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_master_providers.dart';
import '../../utils/formatting.dart';
import 'planned_assign_to_period_sheet.dart';
import 'planned_master_edit_sheet.dart';

class PlannedLibraryScreen extends ConsumerStatefulWidget {
  const PlannedLibraryScreen({super.key, this.selectForAssignment = false});

  final bool selectForAssignment;

  @override
  ConsumerState<PlannedLibraryScreen> createState() =>
      _PlannedLibraryScreenState();
}

class _PlannedLibraryScreenState
    extends ConsumerState<PlannedLibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final mastersAsync = ref.watch(plannedMasterListProvider);
    final counts = ref.watch(plannedInstancesCountByMasterProvider).value ?? {};
    final categories = ref.watch(categoriesMapProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Общий план'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Новый шаблон',
            onPressed: () => showPlannedMasterEditSheet(context),
          ),
        ],
      ),
      body: mastersAsync.when(
        data: (masters) {
          if (masters.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Добавьте первый шаблон, чтобы быстро назначать планы по периодам.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: masters.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final master = masters[index];
              final id = master.id;
              final categoryName =
                  master.categoryId != null ? categories[master.categoryId!]?.name : null;
              final defaultAmount = master.defaultAmountMinor != null
                  ? formatCurrencyMinor(master.defaultAmountMinor!)
                  : null;
              final subtitle = _buildSubtitle(categoryName, defaultAmount);
              final hasInstances = id != null && (counts[id] ?? 0) > 0;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  child: Icon(_iconForType(master.type)),
                ),
                title: Text(master.title),
                subtitle: subtitle != null ? Text(subtitle) : null,
                trailing: PopupMenuButton<_MasterMenuAction>(
                  onSelected: (action) => _handleMenuAction(context, master, action,
                      canDelete: !hasInstances),
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<_MasterMenuAction>>[
                      const PopupMenuItem(
                        value: _MasterMenuAction.edit,
                        child: Text('Редактировать'),
                      ),
                      const PopupMenuItem(
                        value: _MasterMenuAction.assign,
                        child: Text('Назначить в период'),
                      ),
                      PopupMenuItem(
                        value: _MasterMenuAction.toggleArchive,
                        child: Text(master.archived ? 'Разархивировать' : 'Архивировать'),
                      ),
                    ];
                    if (!hasInstances) {
                      items.add(
                        const PopupMenuItem(
                          value: _MasterMenuAction.delete,
                          child: Text('Удалить'),
                        ),
                      );
                    }
                    return items;
                  },
                ),
                onTap: id == null
                    ? null
                    : () => _handleTap(context, master, canDelete: !hasInstances),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить список: $error'),
          ),
        ),
      ),
    );
  }

  String? _buildSubtitle(String? categoryName, String? defaultAmount) {
    if (categoryName == null && defaultAmount == null) {
      return null;
    }
    if (categoryName != null && defaultAmount != null) {
      return '$categoryName · $defaultAmount';
    }
    return categoryName ?? defaultAmount;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'income':
        return Icons.trending_up;
      case 'saving':
        return Icons.savings_outlined;
      case 'expense':
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  Future<void> _handleTap(
    BuildContext context,
    PlannedMaster master, {
    required bool canDelete,
  }) async {
    if (widget.selectForAssignment) {
      final saved = await showPlannedAssignToPeriodSheet(
        context,
        master: master,
      );
      if (!mounted) {
        return;
      }
      if (saved == true) {
        Navigator.of(context).pop(master);
      }
      return;
    }
    final id = master.id;
    if (id == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    context.pushNamed(
      RouteNames.plannedMasterDetail,
      pathParameters: {'id': id.toString()},
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    PlannedMaster master,
    _MasterMenuAction action, {
    required bool canDelete,
  }) async {
    switch (action) {
      case _MasterMenuAction.edit:
        await showPlannedMasterEditSheet(context, initial: master);
        break;
      case _MasterMenuAction.assign:
        await showPlannedAssignToPeriodSheet(context, master: master);
        break;
      case _MasterMenuAction.toggleArchive:
        await _toggleArchive(context, master);
        break;
      case _MasterMenuAction.delete:
        if (canDelete) {
          await _deleteMaster(context, master);
        }
        break;
    }
  }

  Future<void> _toggleArchive(BuildContext context, PlannedMaster master) async {
    final id = master.id;
    if (id == null) {
      return;
    }
    final repo = ref.read(plannedMasterRepoProvider);
    await repo.update(id, archived: !master.archived);
    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }

  Future<void> _deleteMaster(BuildContext context, PlannedMaster master) async {
    final id = master.id;
    if (id == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить шаблон?'),
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
    final repo = ref.read(plannedMasterRepoProvider);
    try {
      await repo.delete(id);
      if (!mounted) {
        return;
      }
      bumpDbTick(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шаблон удалён')),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

enum _MasterMenuAction { edit, assign, toggleArchive, delete }
