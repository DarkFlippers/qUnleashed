import 'archive_category.dart';

enum ArchiveKeyState { remoteOnly, localOnly, synced, deleted }

class ArchiveKey {
  ArchiveKey({
    required this.name,
    required this.category,
    required this.state,
    String? extension,
    this.subFolder = '',
    this.remoteSize = 0,
    this.localSize = 0,
    this.localPath,
    this.favorite = false,
  }) : extension = extension ?? category.extension;

  final String name;
  final ArchiveCategory category;
  final ArchiveKeyState state;
  final String extension;
  final String subFolder;
  final int remoteSize;
  final int localSize;
  final String? localPath;
  final bool favorite;

  String get fileName => '$name.$extension';

  bool get isAutosave => subFolder.toLowerCase() == 'autosave';

  String get remotePath {
    if (subFolder.isEmpty) return '${category.remoteDir}/$fileName';
    return '${category.remoteDir}/$subFolder/$fileName';
  }

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
      extension: extension,
      subFolder: subFolder,
      remoteSize: remoteSize ?? this.remoteSize,
      localSize: localSize ?? this.localSize,
      localPath: localPath ?? this.localPath,
      favorite: favorite ?? this.favorite,
    );
  }
}
