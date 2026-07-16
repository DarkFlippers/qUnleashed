import 'dart:typed_data';

class FapFavorite {
  const FapFavorite({required this.remotePath, required this.name, this.icon});

  final String remotePath;

  final String name;
  final Uint8List? icon;

  String get fileName {
    final slash = remotePath.lastIndexOf('/');
    return slash >= 0 ? remotePath.substring(slash + 1) : remotePath;
  }

  String get subFolder {
    const prefix = '/ext/apps/';
    if (!remotePath.startsWith(prefix)) return '';
    final rel = remotePath.substring(prefix.length);
    final slash = rel.lastIndexOf('/');
    return slash >= 0 ? rel.substring(0, slash) : '';
  }

  FapFavorite copyWith({String? name, Uint8List? icon}) => FapFavorite(
    remotePath: remotePath,
    name: name ?? this.name,
    icon: icon ?? this.icon,
  );
}
