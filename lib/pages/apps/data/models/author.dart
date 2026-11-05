class AppAuthor {
  final String id;
  final String name;

  const AppAuthor({required this.id, required this.name});

  factory AppAuthor.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '') as String;
    final name = (json['name'] ?? '') as String;
    return AppAuthor(id: id, name: name.isEmpty ? id : name);
  }

  static List<AppAuthor> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <AppAuthor>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final author = AppAuthor.fromJson(entry);
      if (author.id.isNotEmpty) out.add(author);
    }
    return List.unmodifiable(out);
  }
}

class AuthorSummary {
  final AppAuthor author;
  final Map<String, int> counts;
  final int? downloads;

  const AuthorSummary({
    required this.author,
    required this.counts,
    this.downloads,
  });

  String get id => author.id;
  String get name => author.name;

  int get total => counts.values.fold(0, (sum, n) => sum + n);

  factory AuthorSummary.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final raw = json['counts'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is num) counts[key] = value.toInt();
      });
    }
    final author = AppAuthor.fromJson(json);
    if (author.id.isEmpty) throw const FormatException('author without id');
    return AuthorSummary(
      author: author,
      counts: Map.unmodifiable(counts),
      downloads: (json['downloads'] as num?)?.toInt(),
    );
  }
}
