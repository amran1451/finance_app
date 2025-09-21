enum CategoryType { income, expense, saving }

class Category {
  const Category({
    this.id,
    required this.type,
    required this.name,
    this.isGroup = false,
    this.parentId,
    this.isArchived = false,
  });

  final int? id;
  final CategoryType type;
  final String name;
  final bool isGroup;
  final int? parentId;
  final bool isArchived;

  Category copyWith({
    int? id,
    CategoryType? type,
    String? name,
    bool? isGroup,
    int? parentId,
    bool? isArchived,
  }) {
    return Category(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      isGroup: isGroup ?? this.isGroup,
      parentId: parentId ?? this.parentId,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id'] as int?,
      type: _typeFromString(map['type'] as String?),
      name: map['name'] as String? ?? '',
      isGroup: (map['is_group'] as int? ?? 0) != 0,
      parentId: map['parent_id'] as int?,
      isArchived: (map['archived'] as int? ?? 0) != 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': _typeToString(type),
      'name': name,
      'is_group': isGroup ? 1 : 0,
      'parent_id': parentId,
      'archived': isArchived ? 1 : 0,
    };
  }

  static CategoryType _typeFromString(String? raw) {
    switch (raw) {
      case 'income':
        return CategoryType.income;
      case 'expense':
        return CategoryType.expense;
      case 'saving':
        return CategoryType.saving;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown category type');
    }
  }

  static String _typeToString(CategoryType type) {
    switch (type) {
      case CategoryType.income:
        return 'income';
      case CategoryType.expense:
        return 'expense';
      case CategoryType.saving:
        return 'saving';
    }
  }
}
