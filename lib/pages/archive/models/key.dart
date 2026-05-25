import 'category.dart';

enum ArchiveKeyState { local, synced, deleted }

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
    this.protocol,
    this.extra,
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
  final String? protocol;
  final String? extra;

  String get fileName => '$name.$extension';

  String get remotePath {
    if (subFolder.isEmpty) return '${category.remoteDir}/$fileName';
    return '${category.remoteDir}/$subFolder/$fileName';
  }

  bool get onDevice => state == ArchiveKeyState.synced;
  bool get hasLocalFile => localPath != null && localPath!.isNotEmpty;
  bool get inLocal => state != ArchiveKeyState.deleted && hasLocalFile;
  bool get isDeleted => state == ArchiveKeyState.deleted;
  bool get isSynced => state == ArchiveKeyState.synced;

  ArchiveKey copyWith({
    ArchiveKeyState? state,
    int? remoteSize,
    int? localSize,
    String? localPath,
    bool? favorite,
    String? protocol,
    String? extra,
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
      protocol: protocol ?? this.protocol,
      extra: extra ?? this.extra,
    );
  }
}
