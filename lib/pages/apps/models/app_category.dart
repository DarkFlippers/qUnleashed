class AppCategory {
  final String id;
  final String name;
  final String color;
  final String? iconUri;
  final int? applicationsCount;
  final int? priority;

  const AppCategory({
    required this.id,
    required this.name,
    required this.color,
    this.iconUri,
    this.applicationsCount,
    this.priority,
  });

  factory AppCategory.fromJson(Map<String, dynamic> json) {
    return AppCategory(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      color: (json['color'] ?? '') as String,
      iconUri: json['icon_uri'] as String?,
      applicationsCount: (json['applications'] as num?)?.toInt(),
      priority: (json['priority'] as num?)?.toInt(),
    );
  }
}
