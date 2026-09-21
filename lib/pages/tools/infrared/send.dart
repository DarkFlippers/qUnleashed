import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../../../components/archive/category.dart';
import '../../../services/localization/l10n.dart';

/// Writes [bytes] as `fileName` into the infrared folder of the Flipper this
/// call starts against.
///
/// Declared as one task, so the transfer keeps going to that Flipper even if
/// the user switches devices while it runs - the file belongs to the device it
/// was sent to, not to whichever one is on screen when the last frame lands.
///
/// The folder comes from [ArchiveCategory.infrared] rather than a literal.
/// Where each category lives on the device is declared once, in the category
/// config, and a module that spells the path out again is a second place that
/// has to be kept in step with it.
///
/// The disconnect watch is not redundant with what flipperlib already raises.
/// A link that goes - including a switch into CLI mode, which tears the RPC
/// session down and builds a new one - does fail the write, but with a bare
/// StateError naming the transport. This puts a sentence the viewer can show in
/// its place.
Future<void> sendIrFile(
  FlipperClient client,
  String fileName,
  List<int> bytes, {
  void Function(double progress)? onProgress,
}) {
  return client.runTask(FlipperRequestPriority.background, () async {
    final disconnected = Completer<void>();
    late final StreamSubscription<FlipperConnectionState> sub;
    sub = client.connectionStream.listen((state) {
      if (!state.connected && !disconnected.isCompleted) {
        disconnected.completeError(StateError(l10n.irDisconnected));
      }
    });
    await Future.any<void>([
      client.storageWriteChunked(
        '${ArchiveCategory.infrared.remoteDir}/$fileName',
        bytes,
        onProgress: onProgress,
      ),
      disconnected.future,
    ]).whenComplete(sub.cancel);
  });
}
