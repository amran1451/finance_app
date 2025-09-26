import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart' as category_models;
import '../../data/repositories/necessity_repository.dart' as necessity_repo;
import '../../data/repositories/planned_master_repository.dart';
import '../../state/budget_providers.dart';
import '../../state/db_refresh.dart';
import '../../state/planned_library_providers.dart';
import '../../state/planned_master_providers.dart';
import '../../utils/color_hex.dart';
import '../../utils/formatting.dart';
import 'planned_assign_to_period_sheet.dart';
import 'planned_master_edit_sheet.dart';

class PlannedLibraryScreen extends ConsumerStatefulWidget {
  const PlannedLibraryScreen({
    super.key,
    this.selectForAssignment = false,
    this.assignmentType,
  });

  final bool selectForAssignment;
  final String? assignmentType;

  @override
  ConsumerState<PlannedLibraryScreen> createState() =>
      _PlannedLibraryScreenState();
}

class _PlannedLibraryScreenState
    extends ConsumerState<PlannedLibraryScreen> {
  bool _showAssigned = false;
  Timer? _searchDebounce;
  late final TextEditingController _searchController;
  ProviderSubscription<PlannedLibraryFilters>? _filtersSubscription;

  @override
  void initState() {
    super.initState();
    final initialFilters = ref.read(plannedLibraryFiltersProvider);
    _searchController = TextEditingController(
      text: widget.selectForAssignment ? '' : initialFilters.search,
    );
    if (!widget.selectForAssignment) {
      _filtersSubscription = ref.listenManual<PlannedLibraryFilters>(
        plannedLibraryFiltersProvider,
        (previous, next) {
          if (_searchController.text != next.search) {
            _searchController.value = TextEditingValue(
              text: next.search,
              selection: TextSelection.collapsed(offset: next.search.length),
            );
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _filtersSubscription?.close();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final body = widget.selectForAssignment
        ? _buildAssignmentBody(context)
        : _buildLibraryBody(context);

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
      body: body,
    );
  }

  Widget _buildLibraryBody(BuildContext context) {
    final filters = ref.watch(plannedLibraryFiltersProvider);
    final (periodStart, periodEndEx) = ref.watch(periodBoundsProvider);
    final mastersAsync =
        ref.watch(plannedLibraryListProvider((periodStart, periodEndEx)));
    final necessityLabels =
        ref.watch(necessityLabelsProvider).value ?? const <int, necessity_repo.NecessityLabel>{};
    final categories = ref.watch(categoriesMapProvider).value ??
        const <int, category_models.Category>{};
    final counts = ref.watch(plannedInstancesCountByMasterProvider).value ??
        const <int, int>{};

    return Column(
      children: [
        _buildFilterPanel(context, filters, necessityLabels),
        Expanded(
          child: mastersAsync.when(
            data: (masters) {
              if (masters.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Нет шаблонов, подходящих под выбранные фильтры.',
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
                  final view = masters[index];
                  final categoryName = view.categoryId != null
                      ? categories[view.categoryId]?.name
                      : null;
                  final amount = view.defaultAmountMinor != null
                      ? formatCurrencyMinor(view.defaultAmountMinor!)
                      : null;
                  final subtitleText = _buildSubtitle(categoryName, amount);
                  final hasInstances = (counts[view.id] ?? 0) > 0;
                  final master = view.toMaster();
                  return _PlannedMasterTile(
                    view: view,
                    subtitle: subtitleText,
                    hasInstances: hasInstances,
                    showAssignButton: !widget.selectForAssignment,
                    onAssign: () {
                      _handleTap(context, master);
                    },
                    onEdit: () {
                      _handleMenuAction(
                        context,
                        master,
                        _MasterMenuAction.edit,
                        canDelete: !hasInstances,
                      );
                    },
                    onAssignToPeriod: () {
                      _handleMenuAction(
                        context,
                        master,
                        _MasterMenuAction.assign,
                        canDelete: !hasInstances,
                      );
                    },
                    onToggleArchive: () {
                      _handleMenuAction(
                        context,
                        master,
                        _MasterMenuAction.toggleArchive,
                        canDelete: !hasInstances,
                      );
                    },
                    onDelete: hasInstances
                        ? null
                        : () {
                            _handleMenuAction(
                              context,
                              master,
                              _MasterMenuAction.delete,
                              canDelete: !hasInstances,
                            );
                          },
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
        ),
      ],
    );
  }

  Widget _buildFilterPanel(
    BuildContext context,
    PlannedLibraryFilters filters,
    Map<int, necessity_repo.NecessityLabel> necessityLabels,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(plannedLibraryFiltersProvider.notifier);
    final labelsList = necessityLabels.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Material(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TypeFilterChips(
                  filters: filters,
                  onChanged: (next) => notifier.update(
                    (state) => state.copyWith(type: next),
                  ),
                ),
                _AssignmentSegment(
                  filters: filters,
                  onChanged: (value) => notifier.update(
                    (state) => state.copyWith(assignedInPeriod: value),
                  ),
                ),
                _StatusSegment(
                  archived: filters.archived,
                  onChanged: (value) => notifier.update(
                    (state) => state.copyWith(archived: value),
                  ),
                ),
                _NecessityDropdown(
                  filters: filters,
                  labels: labelsList,
                  onSelectAll: () => notifier.update(
                    (state) => state.copyWith(necessityIds: <int>{}),
                  ),
                  onSelectSingle: (id) => notifier.update(
                    (state) => state.copyWith(necessityIds: {id}),
                  ),
                  onSelectMultiple: () => _showNecessityMultiSelect(
                    context,
                    labelsList,
                    filters.necessityIds,
                  ),
                ),
                _SortChip(
                  filters: filters,
                  onChanged: (sort, desc) => notifier.update(
                    (state) => state.copyWith(sort: sort, desc: desc),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filters.search.isNotEmpty
                    ? IconButton(
                        tooltip: 'Очистить',
                        onPressed: () {
                          _searchController.clear();
                          _applySearch('');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                hintText: 'Поиск по названию',
                border: const OutlineInputBorder(),
              ),
              onChanged: _handleSearchChanged,
              onSubmitted: _applySearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentBody(BuildContext context) {
    final rawType = widget.assignmentType?.toLowerCase();
    final assignmentType = switch (rawType) {
      'income' => rawType,
      'expense' => rawType,
      'saving' => rawType,
      _ => null,
    };
    final mastersAsync = ref.watch(
      plannedMastersForAssignmentProvider(
        (type: assignmentType, includeAssigned: _showAssigned),
      ),
    );
    final counts = ref.watch(plannedInstancesCountByMasterProvider).value ??
        const <int, int>{};
    final categories = ref.watch(categoriesMapProvider).value ?? {};

    return mastersAsync.when(
      data: (masters) {
        if (masters.isEmpty) {
          return ListView(
            padding: const EdgeInsets.only(top: 16),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text('Нет доступных шаблонов для выбранного периода.'),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: masters.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('Показать уже назначенные'),
                value: _showAssigned,
                onChanged: (value) => setState(() {
                  _showAssigned = value;
                }),
              );
            }
            final master = masters[index - 1];
            final id = master.id;
            final categoryName = master.categoryId != null
                ? categories[master.categoryId!]?.name
                : null;
            final amount = master.defaultAmountMinor != null
                ? formatCurrencyMinor(master.defaultAmountMinor!)
                : null;
            final subtitle = _buildSubtitle(categoryName, amount);
            final hasInstances = id != null && (counts[id] ?? 0) > 0;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Icon(_iconForType(master.type)),
              ),
              title: Text(master.title),
              subtitle: subtitle != null ? Text(subtitle) : null,
              trailing: PopupMenuButton<_MasterMenuAction>(
                onSelected: (action) => _handleMenuAction(
                  context,
                  master,
                  action,
                  canDelete: !hasInstances,
                ),
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<_MasterMenuAction>>[
                    const PopupMenuItem(
                      value: _MasterMenuAction.assign,
                      child: Text('Назначить в период'),
                    ),
                    const PopupMenuItem(
                      value: _MasterMenuAction.edit,
                      child: Text('Редактировать'),
                    ),
                    PopupMenuItem(
                      value: _MasterMenuAction.toggleArchive,
                      child: Text(
                        master.archived
                            ? 'Разархивировать'
                            : 'Архивировать',
                      ),
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
              onTap: id == null ? null : () => _handleTap(context, master),
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
    );
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _applySearch(value),
    );
  }

  void _applySearch(String value) {
    ref.read(plannedLibraryFiltersProvider.notifier).update(
          (state) => state.copyWith(search: value.trim()),
        );
  }

  Future<void> _showNecessityMultiSelect(
    BuildContext context,
    List<necessity_repo.NecessityLabel> labels,
    Set<int> current,
  ) async {
    final initialSelection = Set<int>.from(current);
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      useSafeArea: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        var selection = Set<int>.from(initialSelection);
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Выберите ярлыки критичности',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          selection.clear();
                        }),
                        child: const Text('Сбросить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final label in labels)
                            CheckboxListTile(
                              value: selection.contains(label.id),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  selection.add(label.id);
                                } else {
                                  selection.remove(label.id);
                                }
                              }),
                              title: Text(label.name),
                              secondary: CircleAvatar(
                                backgroundColor:
                                    hexToColor(label.color) ?? theme.colorScheme.surfaceVariant,
                              ),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context)
                              .pop(Set<int>.from(selection)),
                          child: const Text('Применить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      ref.read(plannedLibraryFiltersProvider.notifier).update(
            (state) => state.copyWith(necessityIds: result),
          );
    }
  }

  String? _buildSubtitle(String? categoryName, String? amount) {
    if ((categoryName == null || categoryName.isEmpty) && amount == null) {
      return null;
    }
    final parts = <String>[
      if (categoryName != null && categoryName.isNotEmpty) categoryName,
      if (amount != null) amount,
    ];
    return parts.join(' · ');
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
    PlannedMaster master,
  ) async {
    final saved = await showPlannedAssignToPeriodSheet(
      context,
      master: master,
    );
    if (!mounted) {
      return;
    }
    if (widget.selectForAssignment && saved == true) {
      Navigator.of(context).pop(master);
    }
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
    final updated = await repo.update(id, archived: !master.archived);
    if (!mounted) {
      return;
    }
    if (updated) {
      bumpDbTick(ref);
    }
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
          FilledButton(
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
    await repo.delete(id);
    if (!mounted) {
      return;
    }
    bumpDbTick(ref);
  }
}

class _PlannedMasterTile extends StatelessWidget {
  const _PlannedMasterTile({
    required this.view,
    required this.subtitle,
    required this.hasInstances,
    required this.showAssignButton,
    required this.onAssign,
    required this.onEdit,
    required this.onAssignToPeriod,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final PlannedMasterView view;
  final String? subtitle;
  final bool hasInstances;
  final bool showAssignButton;
  final VoidCallback onAssign;
  final VoidCallback onEdit;
  final VoidCallback onAssignToPeriod;
  final VoidCallback onToggleArchive;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleWidgets = <Widget>[];
    if (subtitle != null) {
      subtitleWidgets.add(Text(subtitle!));
    }
    if (view.assignedNow) {
      subtitleWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                'в периоде',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    subtitleWidgets.add(
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _buildNecessityInfo(theme)),
            if (showAssignButton) ...[
              const SizedBox(width: 12),
              Flexible(
                fit: FlexFit.loose,
                child: OutlinedButton.icon(
                  onPressed: onAssignToPeriod,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Назначить в период'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final trailingMenuItems = <PopupMenuEntry<_MasterMenuAction>>[
      const PopupMenuItem(
        value: _MasterMenuAction.assign,
        child: Text('Назначить в период'),
      ),
      const PopupMenuItem(
        value: _MasterMenuAction.edit,
        child: Text('Редактировать'),
      ),
      PopupMenuItem(
        value: _MasterMenuAction.toggleArchive,
        child: Text(view.archived ? 'Разархивировать' : 'Архивировать'),
      ),
      if (!hasInstances)
        const PopupMenuItem(
          value: _MasterMenuAction.delete,
          child: Text('Удалить'),
        ),
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Colors.transparent,
        child: Icon(_iconForType(view.type)),
      ),
      title: Text(view.title),
      subtitle: subtitleWidgets.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: subtitleWidgets,
            ),
      trailing: PopupMenuButton<_MasterMenuAction>(
        onSelected: (action) {
          switch (action) {
            case _MasterMenuAction.assign:
              onAssignToPeriod();
              break;
            case _MasterMenuAction.edit:
              onEdit();
              break;
            case _MasterMenuAction.toggleArchive:
              onToggleArchive();
              break;
            case _MasterMenuAction.delete:
              if (onDelete != null) {
                onDelete!();
              }
              break;
          }
        },
        itemBuilder: (context) => trailingMenuItems,
      ),
      onTap: onAssign,
    );
  }

  Widget _buildNecessityInfo(ThemeData theme) {
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (view.type != 'expense') {
      return Text(
        'Критичность: —',
        style: baseStyle,
        overflow: TextOverflow.ellipsis,
      );
    }

    final necessityName =
        view.necessityName?.isNotEmpty == true ? view.necessityName! : '—';
    final highlightColor = view.necessityColor != null
        ? Color(view.necessityColor!)
        : theme.colorScheme.primary;

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Критичность: '),
          if (view.necessityColor != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: highlightColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          TextSpan(
            text: necessityName,
            style: TextStyle(
              color: highlightColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
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

}

class _TypeFilterChips extends StatelessWidget {
  const _TypeFilterChips({
    required this.filters,
    required this.onChanged,
  });

  final PlannedLibraryFilters filters;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Тип'),
        ChoiceChip(
          label: const Text('Все'),
          selected: filters.type == null,
          onSelected: (_) => onChanged(null),
        ),
        ChoiceChip(
          label: const Text('Расходы'),
          selected: filters.type == 'expense',
          onSelected: (_) => onChanged(
            filters.type == 'expense' ? null : 'expense',
          ),
        ),
        ChoiceChip(
          label: const Text('Доходы'),
          selected: filters.type == 'income',
          onSelected: (_) => onChanged(
            filters.type == 'income' ? null : 'income',
          ),
        ),
        ChoiceChip(
          label: const Text('Сбережения'),
          selected: filters.type == 'saving',
          onSelected: (_) => onChanged(
            filters.type == 'saving' ? null : 'saving',
          ),
        ),
      ],
    );
  }
}

class _AssignmentSegment extends StatelessWidget {
  const _AssignmentSegment({
    required this.filters,
    required this.onChanged,
  });

  final PlannedLibraryFilters filters;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = <String>{
      switch (filters.assignedInPeriod) {
        true => 'assigned',
        false => 'unassigned',
        null => 'all',
      }
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Назначение'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('Все')),
            ButtonSegment(value: 'assigned', label: Text('В периоде')),
            ButtonSegment(value: 'unassigned', label: Text('Не в периоде')),
          ],
          selected: selected,
          onSelectionChanged: (values) {
            final value = values.isEmpty ? 'all' : values.first;
            switch (value) {
              case 'assigned':
                onChanged(true);
                break;
              case 'unassigned':
                onChanged(false);
                break;
              case 'all':
              default:
                onChanged(null);
            }
          },
        ),
      ],
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.archived,
    required this.onChanged,
  });

  final bool archived;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Статус'),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Активные')),
            ButtonSegment(value: true, label: Text('Архив')),
          ],
          selected: {archived},
          onSelectionChanged: (values) {
            onChanged(values.first);
          },
        ),
      ],
    );
  }
}

class _NecessityDropdown extends StatelessWidget {
  const _NecessityDropdown({
    required this.filters,
    required this.labels,
    required this.onSelectAll,
    required this.onSelectSingle,
    required this.onSelectMultiple,
  });

  final PlannedLibraryFilters filters;
  final List<necessity_repo.NecessityLabel> labels;
  final VoidCallback onSelectAll;
  final ValueChanged<int> onSelectSingle;
  final VoidCallback onSelectMultiple;

  @override
  Widget build(BuildContext context) {
    final value = _currentValue();
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'all',
        child: Text('Все'),
      ),
      for (final label in labels)
        DropdownMenuItem(
          value: 'id:${label.id}',
          child: Text(label.name),
        ),
      DropdownMenuItem(
        value: 'multi',
        child: Text(
          filters.necessityIds.length > 1
              ? 'Несколько… (${filters.necessityIds.length})'
              : 'Несколько…',
        ),
      ),
    ];

    final missing = filters.necessityIds.length == 1
        ? filters.necessityIds.firstWhere(
            (id) => labels.every((label) => label.id != id),
            orElse: () => -1,
          )
        : -1;
    if (missing > 0) {
      items.insert(
        1,
        DropdownMenuItem(
          value: 'id:$missing',
          child: Text('Метка #$missing'),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Критичность'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          items: items,
          onChanged: (selected) {
            if (selected == null) {
              return;
            }
            if (selected == 'all') {
              onSelectAll();
            } else if (selected == 'multi') {
              onSelectMultiple();
            } else if (selected.startsWith('id:')) {
              final id = int.tryParse(selected.substring(3));
              if (id != null) {
                onSelectSingle(id);
              }
            }
          },
        ),
      ],
    );
  }

  String _currentValue() {
    if (filters.necessityIds.isEmpty) {
      return 'all';
    }
    if (filters.necessityIds.length == 1) {
      final id = filters.necessityIds.first;
      final exists = labels.any((label) => label.id == id);
      if (exists) {
        return 'id:$id';
      }
    }
    return 'multi';
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.filters,
    required this.onChanged,
  });

  final PlannedLibraryFilters filters;
  final void Function(String sort, bool desc) onChanged;

  static const _options = [
    _SortSelection(sort: 'title', desc: false, label: 'Название ↑'),
    _SortSelection(sort: 'title', desc: true, label: 'Название ↓'),
    _SortSelection(sort: 'amount', desc: false, label: 'Сумма ↑'),
    _SortSelection(sort: 'amount', desc: true, label: 'Сумма ↓'),
    _SortSelection(sort: 'updated_at', desc: false, label: 'Обновлено ↑'),
    _SortSelection(sort: 'updated_at', desc: true, label: 'Обновлено ↓'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _labelFor(filters);
    return PopupMenuButton<_SortSelection>(
      position: PopupMenuPosition.under,
      tooltip: 'Сортировка',
      onSelected: (option) => onChanged(option.sort, option.desc),
      itemBuilder: (context) => [
        for (final option in _options)
          PopupMenuItem<_SortSelection>(
            value: option,
            child: Text(option.label),
          ),
      ],
      child: Chip(
        avatar: Icon(
          Icons.sort,
          size: 18,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        label: Text(label),
        backgroundColor: theme.colorScheme.secondaryContainer,
      ),
    );
  }

  String _labelFor(PlannedLibraryFilters filters) {
    final direction = filters.desc ? '↓' : '↑';
    switch (filters.sort) {
      case 'amount':
        return 'Сумма $direction';
      case 'updated_at':
        return 'Обновлено $direction';
      case 'title':
      default:
        return 'Название $direction';
    }
  }
}

class _SortSelection {
  const _SortSelection({
    required this.sort,
    required this.desc,
    required this.label,
  });

  final String sort;
  final bool desc;
  final String label;
}

enum _MasterMenuAction { edit, assign, toggleArchive, delete }
