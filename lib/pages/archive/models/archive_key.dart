import 'archive_category.dart';

enum ArchiveKeyState { remoteOnly, localOnly, synced, deleted }

class ArchiveKey {
  ArchiveKey({
    required this.name,
    required this.category,
    required this.state,
    this.remoteSize = 0,
    this.localSize = 0,
    this.localPath,
    this.favorite = false,
  });

  final String name;
  final ArchiveCategory category;
  final ArchiveKeyState state;
  final int remoteSize;
  final int localSize;
  final String? localPath;
  final bool favorite;

  String get fileName => '$name.${category.extension}';

  String get remotePath => '${category.remoteDir}/$fileName';

  bool get onDevice => state == ArchiveKeyState.remoteOnly || state == ArchiveKeyState.synced;
  bool get inLocal => state == ArchiveKeyState.localOnly || state == ArchiveKeyState.synced || state == ArchiveKeyState.deleted;
  bool get isDeleted => state == ArchiveKeyState.deleted;

  ArchiveKey copyWith({
    ArchiveKeyState? state,
    int? remoteSize,
    int? localSize,
    String? localPath,
    bool? favorite,
  }) {
    return ArchiveKey(
      name: name,
      category: category,
      state: state ?? this.state,
      remoteSize: remoteSize ?? this.remoteSize,
      localSize: localSize ?? this.localSize,
      localPath: localPath ?? this.localPath,
      favorite: favorite ?? this.favorite,
    );
  }
}
