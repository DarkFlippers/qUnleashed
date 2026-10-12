// The file manager's new-folder prompt, the first of #277's five.
//
// It was a hand-rolled `showDialog<String>` that validated nothing, so
// `gate/one` went to `mkdir` and came back as "Create folder failed" with no
// cause named. It is `QNameDialog` now, carrying the Flipper's own rule - and
// a collision check of its own, because `mkdir` onto an existing folder fails
// the same cause-free way and the taken names are already on screen.
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';

import 'firmware_fixture.dart';

/// A Flipper with one folder and one file in `/ext`, answering a listing and
/// nothing else.
class _OneFolder implements FlipperClient {
  /// Every mkdir the page asked for, which must stay empty for a refused name.
  final mkdirs = <String>[];

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

  @override
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) => body();

  List<Main> _answer(Main request) {
    if (request.hasStorageListRequest()) {
      return [
        Main(
          storageListResponse: ListResponse(
            file: [
              fl.File(name: 'badusb', type: File_FileType.DIR, size: 0),
              fl.File(name: 'notes.txt', type: File_FileType.FILE, size: 16),
            ],
          ),
        ),
      ];
    }
    if (request.hasStorageMkdirRequest()) {
      mkdirs.add(request.storageMkdirRequest.path);
    }
    return const [];
  }

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
    final frames = _answer(request);
    for (final frame in frames) {
      onFrame?.call(frame);
    }
    return frames;
  }

  @override
  Future<FlipperRpcBatch<T>> callRpc<T extends GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = _answer(request);
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
  late _OneFolder client;

  /// The page with its new-folder prompt open, and the device to close.
  ///
  /// Closed in the body rather than from a teardown, which is what
  /// `closeDevice`'s own doc asks for: the controller starts a DFU detector
  /// that polls on a one-second timer wherever libusb is present, and the
  /// binding checks for pending timers *before* teardowns run. Disposing from
  /// `addTearDown` passes on a Windows dev box and fails on Linux CI, which is
  /// how this was found.
  Future<DeviceController> openPrompt(WidgetTester tester) async {
    client = _OneFolder();
    final (device, _) = mountedDevice();

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapWithDevice(FileManagerPage(client: client), device),
    );
    await tester.pumpAndSettle();

    // The action lives in the page's own sheet, behind the small FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    return device;
  }

  TextButton confirm(WidgetTester tester) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Create'));

  /// The dialog's field, not the page's search box - the page has one of its
  /// own and `find.byType` would match both.
  final field = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  testWidgets('refuses a name the Flipper will not carry', (tester) async {
    final device = await openPrompt(tester);

    await tester.enterText(field, 'gate/one');
    await tester.pumpAndSettle();

    expect(find.textContaining(r'\ / : * ? " < > |'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
    expect(client.mkdirs, isEmpty);

    await closeDevice(tester, device);
  });

  // The collision, which the storage rule knows nothing about and `mkdir`
  // answers with the same cause-free failure.
  testWidgets('refuses a folder that is already there', (tester) async {
    final device = await openPrompt(tester);

    await tester.enterText(field, 'badusb');
    await tester.pumpAndSettle();

    expect(find.text('A file with this name already exists'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);

    await closeDevice(tester, device);
  });

  testWidgets('creates the folder when the name is one the device takes', (
    tester,
  ) async {
    final device = await openPrompt(tester);

    await tester.enterText(field, 'subghz');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(client.mkdirs, ['/ext/subghz']);

    await closeDevice(tester, device);
  });
}
