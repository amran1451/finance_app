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
import '../../utils/plan_formatting.dart';
import '../widgets/single_line_tooltip_text.dart';
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
  bool _isSearchVisible = false;
  Timer? _searchDebounce;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  ProviderSubscription<PlannedLibraryFilters>? _filtersSubscription;
  ProviderSubscription<
      AsyncValue<Map<int, necessity_repo.NecessityLabel>>>?
      _necessityLabelsSubscription;

  @override
  void initState() {
    super.initState();
    final initialFilters = ref.read(plannedLibraryFiltersProvider);
    _searchController = TextEditingController(
      text: widget.selectForAssignment ? '' : initialFilters.search,
    );
    _searchFocusNode = FocusNode();
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
      _necessityLabelsSubscription = ref.listenManual(
        necessityLabelsProvider,
        (previous, next) {
          next.whenData((labels) {
            final filters = ref.read(plannedLibraryFiltersProvider);
            if (filters.necessityIds.any((id) => !labels.containsKey(id))) {
              final updatedNecessityIds = filters.necessityIds
                  .where(labels.containsKey)
                  .toSet();
              ref
                  .read(plannedLibraryFiltersProvider.notifier)
                  .update(
                    (state) => state.copyWith(
                      necessityIds: updatedNecessityIds,
                    ),
                  );
            }
          });
        },
        fireImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    _filtersSubscription?.close();
    _necessityLabelsSubscription?.close();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
            tooltip: 'Новый план',
            onPressed: () => showPlannedMasterEditSheet(context),
          ),
        ],
      ),
      body: ListTileTheme(
        data: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        child: body,
      ),
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

    final labelsList = necessityLabels.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final selectedNecessity = filters.necessityIds.length == 1
        ? necessityLabels[filters.necessityIds.first]
        : null;
    final hasMultipleNecessities = filters.necessityIds.length > 1;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SizedBox(
            height: 56,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isSearchVisible
                  ? _InlineSearchBar(
                      key: const ValueKey('search'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _handleSearchChanged,
                      onSubmitted: (value) {
                        _applySearch(value);
                        _closeSearchBar();
                      },
                      onClear: () {
                        _searchController.clear();
                        _applySearch('');
                      },
                      onClose: _closeSearchBar,
                    )
                  : Padding(
                      key: const ValueKey('filters'),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: CompactFiltersBar(
                        filters: filters,
                        selectedNecessity: selectedNecessity,
                        hasMultipleNecessities: hasMultipleNecessities,
                        onTypeChange: (type) {
                          ref.read(plannedLibraryFiltersProvider.notifier).update(
                                (state) => state.copyWith(type: type),
                              );
                        },
                        onOpenAdvanced: () => _openAdvancedFilters(
                          context,
                          filters,
                          labelsList,
                        ),
                        onSearch: _openSearchBar,
                      ),
                    ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: mastersAsync.when(
            data: (masters) {
              if (masters.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Нет планов, подходящих под выбранные фильтры.',
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
                  final hasInstances = (counts[view.id] ?? 0) > 0;
                  final master = view.toMaster();
                  return PlannedMasterTile(
                    key: ValueKey(view.id),
                    view: view,
                    categoryName: categoryName,
                    onAssign: () {
                      _handleMenuAction(
                        context,
                        master,
                        _MasterMenuAction.assign,
                        canDelete: !hasInstances,
                      );
                    },
                    onEdit: () {
                      _handleMenuAction(
                        context,
                        master,
                        _MasterMenuAction.edit,
                        canDelete: !hasInstances,
                      );
                    },
                    onArchiveToggle: () {
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

  void _openSearchBar() {
    if (_isSearchVisible) {
      return;
    }
    setState(() {
      _isSearchVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearchBar() {
    if (!_isSearchVisible) {
      return;
    }
    setState(() {
      _isSearchVisible = false;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _openAdvancedFilters(
    BuildContext context,
    PlannedLibraryFilters filters,
    List<necessity_repo.NecessityLabel> labels,
  ) async {
    final result = await showModalBottomSheet<PlannedLibraryFilters>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (modalContext) => AdvancedFiltersSheet(
        filters: filters,
        labels: labels,
      ),
    );
    if (result != null && mounted) {
      ref.read(plannedLibraryFiltersProvider.notifier).state = result;
    }
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
                child: Text('Нет доступных планов для выбранного периода.'),
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
        return Icons.arrow_upward;
      case 'saving':
        return Icons.savings;
      case 'expense':
        return Icons.arrow_downward;
      default:
        return Icons.all_inclusive;
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
        title: const Text('Удалить план?'),
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

class PlannedMasterTile extends StatelessWidget {
  const PlannedMasterTile({
    super.key,
    required this.view,
    this.categoryName,
    required this.onAssign,
    required this.onEdit,
    required this.onArchiveToggle,
    this.onDelete,
  });

  final PlannedMasterView view;
  final String? categoryName;
  final VoidCallback onAssign;
  final VoidCallback onEdit;
  final VoidCallback onArchiveToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _buildSubtitleText();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      title: SingleLineTooltipText(
        text: oneLinePlan(
          view.title,
          view.defaultAmountMinor,
          view.necessityName,
        ),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: SingleLineTooltipText(
        text: subtitle,
        style: theme.textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<_MasterMenuAction>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          switch (value) {
            case _MasterMenuAction.assign:
              onAssign();
              break;
            case _MasterMenuAction.edit:
              onEdit();
              break;
            case _MasterMenuAction.toggleArchive:
              onArchiveToggle();
              break;
            case _MasterMenuAction.delete:
              if (onDelete != null) {
                onDelete!();
              }
              break;
          }
        },
        itemBuilder: (context) => [
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
          PopupMenuItem(
            value: _MasterMenuAction.delete,
            enabled: onDelete != null,
            child: const Text('Удалить'),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }

  String _buildSubtitleText() {
    final parts = <String>[];
    final categoryText =
        (categoryName?.isNotEmpty ?? false) ? categoryName! : '—';
    parts.add(categoryText);
    parts.add(_typeLabel(view.type));
    if (view.assignedNow) {
      final periodLabel = compactPeriodLabel(
        view.assignedPeriodStart,
        view.assignedPeriodEndExclusive,
      );
      if (periodLabel != null) {
        parts.add('Назначен $periodLabel');
      } else {
        parts.add('Назначен');
      }
    }
    if (view.archived) {
      parts.add('Архив');
    }
    return parts.join(' • ');
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

class CompactFiltersBar extends StatelessWidget {
  const CompactFiltersBar({
    super.key,
    required this.filters,
    required this.onTypeChange,
    required this.onOpenAdvanced,
    required this.onSearch,
    this.selectedNecessity,
    this.hasMultipleNecessities = false,
  });

  final PlannedLibraryFilters filters;
  final void Function(String? type) onTypeChange;
  final VoidCallback onOpenAdvanced;
  final VoidCallback onSearch;
  final necessity_repo.NecessityLabel? selectedNecessity;
  final bool hasMultipleNecessities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = () {
      if (selectedNecessity != null) {
        return selectedNecessity!.name;
      }
      if (hasMultipleNecessities) {
        return 'Несколько';
      }
      return 'Все';
    }();

    final avatar = () {
      if (selectedNecessity != null) {
        final color = selectedNecessity!.color != null
            ? hexToColor(selectedNecessity!.color!)
            : theme.colorScheme.secondary;
        return CircleAvatar(
          radius: 7,
          backgroundColor: color ?? theme.colorScheme.secondary,
        );
      }
      if (hasMultipleNecessities) {
        return const Icon(Icons.label, size: 16);
      }
      return const Icon(Icons.label_outline, size: 16);
    }();

    return Row(
      children: [
        Flexible(
          flex: 3,
          child: _TypeSegmented(
            value: filters.type,
            onChanged: onTypeChange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: avatar,
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: onOpenAdvanced,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Поиск',
          icon: const Icon(Icons.search),
          onPressed: onSearch,
        ),
        IconButton(
          tooltip: 'Расширенные фильтры',
          icon: const Icon(Icons.tune),
          onPressed: onOpenAdvanced,
        ),
      ],
    );
  }
}

class _TypeSegmented extends StatelessWidget {
  const _TypeSegmented({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final void Function(String? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = {value ?? 'all'};
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'all', icon: Icon(Icons.all_inclusive)),
        ButtonSegment(value: 'expense', icon: Icon(Icons.arrow_downward)),
        ButtonSegment(value: 'income', icon: Icon(Icons.arrow_upward)),
        ButtonSegment(value: 'saving', icon: Icon(Icons.savings)),
      ],
      selected: selected,
      onSelectionChanged: (values) {
        final next = values.first;
        onChanged(next == 'all' ? null : next);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
      ),
      showSelectedIcon: false,
    );
  }
}

class _InlineSearchBar extends StatelessWidget {
  const _InlineSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    decoration: InputDecoration(
                      hintText: 'Поиск по названию',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить',
                              icon: const Icon(Icons.clear),
                              onPressed: onClear,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Закрыть поиск',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class AdvancedFiltersSheet extends StatefulWidget {
  const AdvancedFiltersSheet({
    super.key,
    required this.filters,
    required this.labels,
  });

  final PlannedLibraryFilters filters;
  final List<necessity_repo.NecessityLabel> labels;

  @override
  State<AdvancedFiltersSheet> createState() => _AdvancedFiltersSheetState();
}

class _AdvancedFiltersSheetState extends State<AdvancedFiltersSheet> {
  late String? _type;
  late Set<int> _necessityIds;
  late bool? _assignedInPeriod;
  late bool _archived;
  late String _sort;
  late bool _desc;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _type = widget.filters.type;
    _necessityIds = Set<int>.from(widget.filters.necessityIds);
    _assignedInPeriod = widget.filters.assignedInPeriod;
    _archived = widget.filters.archived;
    _sort = widget.filters.sort;
    _desc = widget.filters.desc;
    _searchController = TextEditingController(text: widget.filters.search);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Фильтры',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Тип'),
                    ..._buildTypeSection(),
                    const SizedBox(height: 16),
                    _SectionTitle('Критичность'),
                    ..._buildNecessitySection(theme),
                    const SizedBox(height: 16),
                    _SectionTitle('Назначение'),
                    ..._buildAssignmentSection(),
                    const SizedBox(height: 16),
                    _SectionTitle('Статус'),
                    ..._buildStatusSection(),
                    const SizedBox(height: 16),
                    _SectionTitle('Сортировка'),
                    _buildSortSection(),
                    const SizedBox(height: 16),
                    _SectionTitle('Поиск'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Поиск по названию',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                top: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _reset,
                      child: const Text('Сбросить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Применить'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTypeSection() {
    return [
      RadioListTile<String?>(
        title: const Text('Все'),
        value: null,
        groupValue: _type,
        onChanged: (value) => setState(() => _type = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<String?>(
        title: const Text('Расходы'),
        value: 'expense',
        groupValue: _type,
        onChanged: (value) => setState(() => _type = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<String?>(
        title: const Text('Доходы'),
        value: 'income',
        groupValue: _type,
        onChanged: (value) => setState(() => _type = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<String?>(
        title: const Text('Сбережения'),
        value: 'saving',
        groupValue: _type,
        onChanged: (value) => setState(() => _type = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  List<Widget> _buildNecessitySection(ThemeData theme) {
    if (widget.labels.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Нет доступных меток.'),
        ),
      ];
    }
    return [
      for (final label in widget.labels)
        CheckboxListTile(
          value: _necessityIds.contains(label.id),
          title: Text(label.name),
          dense: true,
          visualDensity: VisualDensity.compact,
          secondary: CircleAvatar(
            radius: 10,
            backgroundColor: label.color != null
                ? hexToColor(label.color!) ?? theme.colorScheme.secondaryContainer
                : theme.colorScheme.secondaryContainer,
          ),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _necessityIds.add(label.id);
              } else {
                _necessityIds.remove(label.id);
              }
            });
          },
        ),
    ];
  }

  List<Widget> _buildAssignmentSection() {
    return [
      RadioListTile<bool?>(
        title: const Text('Все'),
        value: null,
        groupValue: _assignedInPeriod,
        onChanged: (value) => setState(() => _assignedInPeriod = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<bool?>(
        title: const Text('В периоде'),
        value: true,
        groupValue: _assignedInPeriod,
        onChanged: (value) => setState(() => _assignedInPeriod = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<bool?>(
        title: const Text('Не в периоде'),
        value: false,
        groupValue: _assignedInPeriod,
        onChanged: (value) => setState(() => _assignedInPeriod = value),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  List<Widget> _buildStatusSection() {
    return [
      RadioListTile<bool>(
        title: const Text('Активные'),
        value: false,
        groupValue: _archived,
        onChanged: (value) => setState(() => _archived = value ?? false),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      RadioListTile<bool>(
        title: const Text('Архив'),
        value: true,
        groupValue: _archived,
        onChanged: (value) => setState(() => _archived = value ?? true),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  Widget _buildSortSection() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _sort,
            decoration: const InputDecoration(
              labelText: 'Поле',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'title', child: Text('Название')),
              DropdownMenuItem(value: 'amount', child: Text('Сумма')),
              DropdownMenuItem(value: 'updated_at', child: Text('Обновлено')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _sort = value);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.arrow_upward)),
            ButtonSegment(value: true, icon: Icon(Icons.arrow_downward)),
          ],
          selected: {_desc},
          onSelectionChanged: (values) {
            setState(() => _desc = values.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          showSelectedIcon: false,
        ),
      ],
    );
  }

  void _reset() {
    setState(() {
      _type = null;
      _necessityIds.clear();
      _assignedInPeriod = null;
      _archived = false;
      _sort = 'title';
      _desc = false;
      _searchController.text = '';
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      widget.filters.copyWith(
        type: _type,
        necessityIds: _necessityIds,
        assignedInPeriod: _assignedInPeriod,
        archived: _archived,
        search: _searchController.text.trim(),
        sort: _sort,
        desc: _desc,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

enum _MasterMenuAction { edit, assign, toggleArchive, delete }

