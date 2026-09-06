import '../../components/archive/category.dart';
import '../../components/archive/models/key.dart';

/// The one file a home-screen widget stands for: enough to launch it over RPC
/// without the archive (which a cold isolate never loads).
class WidgetKey {
  const WidgetKey({
    required this.name,
    required this.category,
    required this.remotePath,
    required this.holdToSend,
  });

  final String name;
  final ArchiveCategory category;
  final String remotePath;
  final bool holdToSend;

  factory WidgetKey.fromArchiveKey(ArchiveKey key) => WidgetKey(
    name: key.name,
    category: key.category,
    remotePath: key.remotePath,
    holdToSend: key.category.holdToSend,
  );

  static WidgetKey? fromMap(Map<Object?, Object?> map) {
    final name = map['name'];
    final category = map['category'];
    final remotePath = map['remotePath'];
    if (name is! String || category is! String || remotePath is! String) {
      return null;
    }
    ArchiveCategory? cat;
    for (final c in ArchiveCategory.values) {
      if (c.name == category) cat = c;
    }
    if (cat == null) return null;
    return WidgetKey(
      name: name,
      category: cat,
      remotePath: remotePath,
      holdToSend: map['holdToSend'] == true,
    );
  }

  Map<String, Object> toMap() => {
    'name': name,
    'category': category.name,
    'remotePath': remotePath,
    'holdToSend': holdToSend,
  };

  ArchiveKey toArchiveKey() => ArchiveKey(
    name: name,
    category: category,
    state: ArchiveKeyState.synced,
    remotePath: remotePath,
  );
}
