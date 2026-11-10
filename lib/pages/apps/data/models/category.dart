class AppCategory {
  final String id;
  final String name;
  final String color;
  final String? iconUri;
  final String? iconAsset;
  final int? priority;

  /// The category this one is a folder of; null for a top-level category.
  final String? parentId;

  const AppCategory({
    required this.id,
    required this.name,
    required this.color,
    this.iconUri,
    this.iconAsset,
    this.priority,
    this.parentId,
  });

  AppCategory withIconAsset(String? asset) => AppCategory(
    id: id,
    name: name,
    color: color,
    iconUri: iconUri,
    iconAsset: asset ?? iconAsset,
    priority: priority,
    parentId: parentId,
  );

  AppCategory _withColor(String value) => AppCategory(
    id: id,
    name: name,
    color: value,
    iconUri: iconUri,
    iconAsset: iconAsset,
    priority: priority,
    parentId: parentId,
  );

  factory AppCategory.fromJson(Map<String, dynamic> json) {
    return AppCategory(
      id: (json['id'] ?? json['_id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      color: (json['color'] ?? '') as String,
      iconUri: json['icon_uri'] as String?,
      priority: (json['priority'] as num?)?.toInt(),
      parentId: json['parent_id'] as String?,
    );
  }
}

/// Every top-level category followed by its own folders, so a folder sits
/// next to the category it belongs to and wears that category's colour.
/// Top-level categories keep their priority order, folders go by priority
/// and then name; a folder whose parent is missing goes last.
List<AppCategory> nestCategories(List<AppCategory> categories) {
  final ids = {for (final c in categories) c.id};
  bool nested(AppCategory c) => c.parentId != null && ids.contains(c.parentId);
  // List.sort is not stable, so the incoming position breaks ties.
  final position = {
    for (var i = 0; i < categories.length; i++) categories[i]: i,
  };
  int order(AppCategory a, AppCategory b, {bool byName = false}) {
    final priority = (a.priority ?? 0).compareTo(b.priority ?? 0);
    if (priority != 0) return priority;
    final name = byName ? a.name.compareTo(b.name) : 0;
    return name != 0 ? name : position[a]!.compareTo(position[b]!);
  }

  final top = [
    for (final c in categories)
      if (c.parentId == null) c,
  ]..sort(order);
  final out = <AppCategory>[];
  final placed = <String>{};
  void place(AppCategory category, String color) {
    if (!placed.add(category.id)) return;
    final own = category.color.isEmpty ? category._withColor(color) : category;
    out.add(own);
    final folders = [
      for (final c in categories)
        if (nested(c) && c.parentId == category.id) c,
    ]..sort((a, b) => order(a, b, byName: true));
    for (final folder in folders) {
      place(folder, own.color);
    }
  }

  for (final root in top) {
    place(root, root.color);
  }
  out.addAll([
    for (final c in categories)
      if (!placed.contains(c.id)) c,
  ]);
  return out;
}
