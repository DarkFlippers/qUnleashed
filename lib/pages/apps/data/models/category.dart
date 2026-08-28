class AppCategory {
  final String id;
  final String name;
  final String color;
  final String? iconUri;
  final String? iconAsset;
  final int? priority;

  const AppCategory({
    required this.id,
    required this.name,
    required this.color,
    this.iconUri,
    this.iconAsset,
    this.priority,
  });

  AppCategory withIconAsset(String? asset) => AppCategory(
    id: id,
    name: name,
    color: color,
    iconUri: iconUri,
    iconAsset: asset ?? iconAsset,
    priority: priority,
  );

  factory AppCategory.fromJson(Map<String, dynamic> json) {
    return AppCategory(
      id: (json['id'] ?? json['_id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      color: (json['color'] ?? '') as String,
      iconUri: json['icon_uri'] as String?,
      priority: (json['priority'] as num?)?.toInt(),
    );
  }
}
