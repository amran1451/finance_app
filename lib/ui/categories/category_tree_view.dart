import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../utils/category_type_extensions.dart';

typedef CategoryCallback = void Function(Category category);

class CategoryTreeView extends StatelessWidget {
  const CategoryTreeView({
    super.key,
    required this.groups,
    required this.childrenByGroup,
    required this.ungrouped,
    this.onCategoryTap,
    this.onCategoryLongPress,
    this.onGroupTap,
    this.onGroupLongPress,
    this.selectionMode = false,
    this.selectedCategoryIds = const <int>{},
    this.onCategorySelectionToggle,
  });

  final List<Category> groups;
  final Map<int, List<Category>> childrenByGroup;
  final List<Category> ungrouped;
  final CategoryCallback? onCategoryTap;
  final CategoryCallback? onCategoryLongPress;
  final CategoryCallback? onGroupTap;
  final CategoryCallback? onGroupLongPress;
  final bool selectionMode;
  final Set<int> selectedCategoryIds;
  final CategoryCallback? onCategorySelectionToggle;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty && ungrouped.isEmpty) {
      return Center(
        child: Text(
          'Категории не найдены',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    final items = <Widget>[];

    for (final group in groups) {
      final groupId = group.id;
      items.add(_GroupCard(
        key: ValueKey(groupId ?? 'group-${group.name}'),
        group: group,
        children:
            groupId != null ? childrenByGroup[groupId] ?? const <Category>[] : const [],
        onCategoryTap: onCategoryTap,
        onCategoryLongPress: onCategoryLongPress,
        onGroupTap: onGroupTap != null ? () => onGroupTap!(group) : null,
        onGroupLongPress: onGroupLongPress,
        selectionMode: selectionMode,
        selectedCategoryIds: selectedCategoryIds,
        onCategorySelectionToggle: onCategorySelectionToggle,
      ));
      items.add(const SizedBox(height: 12));
    }

    if (ungrouped.isNotEmpty) {
      if (groups.isNotEmpty) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Без папки',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ));
      }
      for (final category in ungrouped) {
        items.add(_CategoryCard(
          category: category,
          onTap: selectionMode ? null : onCategoryTap,
          onLongPress: selectionMode ? null : onCategoryLongPress,
          selectionMode: selectionMode,
          selected: category.id != null &&
              selectedCategoryIds.contains(category.id),
          onSelectionToggle: onCategorySelectionToggle,
        ));
        items.add(const SizedBox(height: 12));
      }
    }

    if (items.isNotEmpty) {
      items.removeLast();
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: items,
    );
  }
}
class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.children,
    this.onCategoryTap,
    this.onCategoryLongPress,
    this.onGroupTap,
    this.onGroupLongPress,
    this.selectionMode = false,
    this.selectedCategoryIds = const <int>{},
    this.onCategorySelectionToggle,
  });

  final Category group;
  final List<Category> children;
  final CategoryCallback? onCategoryTap;
  final CategoryCallback? onCategoryLongPress;
  final VoidCallback? onGroupTap;
  final CategoryCallback? onGroupLongPress;
  final bool selectionMode;
  final Set<int> selectedCategoryIds;
  final CategoryCallback? onCategorySelectionToggle;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _expanded = false;

  void _toggleExpansion() {
    if (widget.children.isEmpty) {
      return;
    }
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.group.type.color;
    final hasChildren = widget.children.isNotEmpty;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(Icons.folder, color: color),
            ),
            title: Text(widget.group.name),
            onTap: widget.selectionMode
                ? (hasChildren ? _toggleExpansion : null)
                : widget.onGroupTap ?? (hasChildren ? _toggleExpansion : null),
            onLongPress: widget.selectionMode || widget.onGroupLongPress == null
                ? null
                : () => widget.onGroupLongPress!(widget.group),
            trailing: hasChildren
                ? IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: _toggleExpansion,
                  )
                : null,
          ),
          if (_expanded && hasChildren)
            ...widget.children.map(
              (category) => _CategoryTile(
                category: category,
                onTap: widget.selectionMode ? null : widget.onCategoryTap,
                onLongPress:
                    widget.selectionMode ? null : widget.onCategoryLongPress,
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
                selectionMode: widget.selectionMode,
                selected: category.id != null &&
                    widget.selectedCategoryIds.contains(category.id),
                onSelectionToggle: widget.onCategorySelectionToggle,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    this.onTap,
    this.onLongPress,
    this.contentPadding,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  final Category category;
  final CategoryCallback? onTap;
  final CategoryCallback? onLongPress;
  final EdgeInsetsGeometry? contentPadding;
  final bool selectionMode;
  final bool selected;
  final CategoryCallback? onSelectionToggle;

  @override
  Widget build(BuildContext context) {
    final color = category.type.color;
    final avatar = CircleAvatar(
      backgroundColor: color.withOpacity(0.15),
      child: Icon(Icons.label, color: color),
    );
    if (selectionMode) {
      final hasId = category.id != null;
      return CheckboxListTile(
        value: hasId && selected,
        onChanged: hasId
            ? (_) => onSelectionToggle?.call(category)
            : null,
        title: Text(category.name),
        secondary: avatar,
        contentPadding:
            contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
        controlAffinity: ListTileControlAffinity.leading,
        selected: selected,
      );
    }
    return ListTile(
      contentPadding: contentPadding,
      leading: avatar,
      title: Text(category.name),
      onTap: onTap != null ? () => onTap!(category) : null,
      onLongPress: onLongPress != null ? () => onLongPress!(category) : null,
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  final Category category;
  final CategoryCallback? onTap;
  final CategoryCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final CategoryCallback? onSelectionToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: _CategoryTile(
        category: category,
        onTap: onTap,
        onLongPress: onLongPress,
        selectionMode: selectionMode,
        selected: selected,
        onSelectionToggle: onSelectionToggle,
      ),
    );
  }
}
