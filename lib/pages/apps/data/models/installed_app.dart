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

  /// Whether the app's `.fap` was on the device the last time the whole device
  /// was walked, or null when no walk has finished since connecting.
  ///
  /// An app can be known to this app without being installed: the list is the
  /// union of the device's manifests and the local backup copies, and neither
  /// disappears when a `.fap` is deleted outside this app - through the file
  /// manager, qFlipper, or the card in a reader. Null and false are not the
  /// same answer, so callers must not treat "not proven present" as "absent".
  final bool? onDevice;

  const InstalledApp({
    required this.alias,
    required this.path,
    required this.folder,
    required this.size,
    this.manifest,
    this.fap,
    this.fapChecked = false,
    this.onDevice,
  });

  /// The app is not installed, and we know that rather than merely not having
  /// looked. Only true once a complete walk has proved the `.fap` gone.
  bool get isMissingFromDevice => onDevice == false;

  bool get hasManifest => manifest != null;

  String get name {
    final full = manifest?.fullName ?? '';
    if (full.isNotEmpty) return full;
    final embedded = fap?.manifest?.name ?? '';
    return embedded.isNotEmpty ? embedded : alias;
  }

  String get uid => manifest?.uid ?? '';
}
