import 'dart:io' as io;

import '../../../../components/archive/models/key.dart';
import '../../../../services/logging.dart';

/// Copies each key's local file into [dir], and says how it went.
///
/// A lift out of the page for one reason: the failure record has to be one
/// entry per selection rather than one per file. A hundred keys against a
/// full disk fail for the same reason a hundred times, and a line each would
/// fill the log screen from a single tap - which is why #111 declined to
/// record this at all. The count already reaches the user in the toast the
/// caller shows; what never reached anyone was the cause.
///
/// Returns how many landed, so the caller can render its own message.
Future<int> saveKeysInto(List<ArchiveKey> keys, String dir) async {
  final sep = io.Platform.pathSeparator;
  var saved = 0;
  String? firstFailure;
  for (final key in keys) {
    final localPath = key.localPath;
    if (localPath == null || localPath.isEmpty) {
      firstFailure ??= '${key.fileName}: no local copy';
      continue;
    }
    try {
      final bytes = await io.File(localPath).readAsBytes();
      await io.File('$dir$sep${key.fileName}').writeAsBytes(bytes, flush: true);
      saved++;
    } catch (e) {
      firstFailure ??= '${key.fileName}: $e';
    }
  }
  if (firstFailure != null) {
    LogService.warn(
      '[Archive] saved $saved of ${keys.length}, first failure $firstFailure',
    );
  }
  return saved;
}
