import '../../path.dart';

import 'dart:typed_data';

class FapFavorite {
  const FapFavorite({required this.remotePath, required this.name, this.icon});

  final String remotePath;

  final String name;
  final Uint8List? icon;

  String get fileName => basename(remotePath);

  String get subFolder {
    const prefix = '/ext/apps/';
    if (!remotePath.startsWith(prefix)) return '';
    return dirname(remotePath.substring(prefix.length));
  }

  FapFavorite copyWith({String? name, Uint8List? icon}) => FapFavorite(
    remotePath: remotePath,
    name: name ?? this.name,
    icon: icon ?? this.icon,
  );
}
