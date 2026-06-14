import 'dart:typed_data';

/// A favorited Flipper application (`.fap`) imported from the device's
/// `favorites.txt`. Unlike [ArchiveKey]s these never live in an archive
/// category; they are tracked separately and rendered only in the favorites
/// list, with an icon extracted from the app binary when available.
class FapFavorite {
  const FapFavorite({
    required this.remotePath,
    required this.name,
    this.icon,
  });

  /// Full on-device path, e.g. `/ext/apps/Tools/Foo.fap`.
  final String remotePath;

  /// Display name: the manifest app name when known, else the file base name.
  final String name;

  /// Decoded [fapIconWidth]×[fapIconHeight] XBM icon bits, or `null` to fall
  /// back to the default app icon.
  final Uint8List? icon;

  /// File name including extension, e.g. `Foo.fap`.
  String get fileName {
    final slash = remotePath.lastIndexOf('/');
    return slash >= 0 ? remotePath.substring(slash + 1) : remotePath;
  }

  /// Path relative to `/ext/apps` without the file name, used as the subtitle
  /// (e.g. `Tools`). Empty when the app sits directly under `/ext/apps`.
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
