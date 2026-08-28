import '../../../../components/codec/fap/info.dart';
import 'manifest.dart';

class InstalledApp {
  final String alias;

  final String path;

  final String folder;

  final int size;

  final AppManifest? manifest;

  /// Parsed contents of the local `.fap` copy, `null` when the file could not
  /// be read or has not been scanned yet — see [fapChecked].
  final FapInfo? fap;

  /// Whether the local copy was already read and handed to the parser.
  final bool fapChecked;

  const InstalledApp({
    required this.alias,
    required this.path,
    required this.folder,
    required this.size,
    this.manifest,
    this.fap,
    this.fapChecked = false,
  });

  bool get hasManifest => manifest != null;

  String get name {
    final full = manifest?.fullName ?? '';
    if (full.isNotEmpty) return full;
    final embedded = fap?.manifest?.name ?? '';
    return embedded.isNotEmpty ? embedded : alias;
  }

  String get uid => manifest?.uid ?? '';
}
