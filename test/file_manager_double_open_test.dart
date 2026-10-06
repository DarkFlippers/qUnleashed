import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
// Not exported by the package root, and storageWriteChunked reads it off the
// client to size its frames, so a fake has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';

import 'firmware_fixture.dart';

/// Opening the same file twice in one gesture.
///
/// Opening a file downloads it and *then* pushes a route, and neither step
/// cared that the last tap was still running - so on a desktop, where a double
/// click is one gesture, a heavy file was fetched twice over and two identical
/// viewers ended up stacked on the navigator, each to be dismissed separately
/// (#244).
///
/// The read is parked rather than answered: that is the whole window the bug
/// lived in, and it also keeps `storageReadChunked` from reaching disk, so no
/// path_provider stub is needed.
class _ParkedStorage implements FlipperClient {
  /// One read per file the page actually fetched.
  int reads = 0;

  final _listing = <String, List<fl.File>>{
    '/ext': [
      fl.File(name: 'notes.txt', type: File_FileType.FILE, size: 16),
      fl.File(name: 'other.txt', type: File_FileType.FILE, size: 16),
    ],
  };

  @override
  bool get isConnected => true;

  @override
  bool get isRpcReady => true;

  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  Transport? get transport => null;

  @override
  bool isLinkDropError(Object e) => false;

  /// Straight through, not serialised: a queue of its own would make the
  /// assertions below pass on the second read being *queued* rather than on it
  /// never being started.
  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    if (request.hasStorageListRequest()) {
      return [
        Main(
          storageListResponse: ListResponse()
            ..file.addAll(
              _listing[request.storageListRequest.path] ?? const [],
            ),
        ),
      ];
    }
    if (request.hasStorageReadRequest()) {
      reads++;
      // Never answers. A download in flight is the state the guard exists for.
      return Completer<List<Main>>().future;
    }
    return const [];
  }

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) send, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) async {
    await send((_) async {});
    return const [];
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await callRpcFrames(request);
    final items = <T>[];
    for (final frame in frames) {
      onFrame?.call(frame);
      final picked = pick(frame);
      if (picked != null) items.add(picked);
    }
    return FlipperRpcBatch<T>(
      commandId: 0,
      request: request,
      frames: frames,
      items: items,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('opening a file in the file manager', () {
    late DeviceController device;
    late _ParkedStorage storage;

    setUp(() {
      (device, _) = mountedDevice();
      storage = _ParkedStorage();
    });

    Future<void> openBrowser(WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithDevice(FileManagerPage(client: storage), device),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('twice in one gesture downloads it once', (tester) async {
      await openBrowser(tester);

      // One desktop double click.
      await tester.tap(find.text('notes.txt'));
      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(
        storage.reads,
        1,
        reason: 'the second click must not start a second download',
      );
    });

    // The reason the guard is a Set keyed on the path and not a bool. A flag
    // would make this read 1: the user taps a large file, waits, taps a small
    // one, and nothing at all happens - a worse bug than the one being fixed,
    // and the one the comment on `_opening` argues against.
    testWidgets('does not block a different file', (tester) async {
      await openBrowser(tester);

      await tester.tap(find.text('notes.txt'));
      await tester.pump();
      await tester.tap(find.text('other.txt'));
      await tester.pump();

      expect(storage.reads, 2, reason: 'a different file is a legitimate open');
    });

    // Both doors. The actions sheet's Edit repeated the same dispatch inline
    // and never touched `_opening`, so the invariant held on the row tap and
    // not here: open the sheet on a large file, tap Edit, then tap the row -
    // two downloads and two stacked editors, from one page, with the guard in
    // place.
    testWidgets('once from the actions sheet, not again from the row', (
      tester,
    ) async {
      await openBrowser(tester);

      // Right click is how the sheet opens on a desktop.
      await tester.tap(find.text('notes.txt'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(storage.reads, 1, reason: 'Edit starts the download');

      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(
        storage.reads,
        1,
        reason: 'and the row cannot start a second one behind it',
      );
    });
  });
}
