// What a user sees when the system picker refuses the pick. QUNLEASHED-K.
//
// `picker_guard_test.dart` holds the shape - that no picker call sits outside
// a `try`. This holds the half that was the actual complaint: the app
// disappeared. "Upload files" called `pickFiles` with no catch, from a
// `ListTile.onTap` that did not await the future either, so Android's
// `unknown_path` reached the zone, `PlatformDispatcher.onError` reported it
// fatal, and the browser was gone behind a dialog the user was still looking
// at.
//
// The test that matters is therefore the *absence* of an uncaught error.
// `testWidgets` fails a test whose zone takes one, which is exactly the
// pre-fix behaviour - so the two assertions below cover the two halves
// separately: the page survives and is still usable, and a sentence arrives
// in the crash's place. Deleting the catch fails this on the first; deleting
// only the notification inside it fails the second.
import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flipperlib/flipperlib.dart' as fl show File;
// Not exported by the package root, and `FlipperClient` declares it, so a fake
// has to answer it by name.
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:qunleashed/pages/archive/browser/page.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'firmware_fixture.dart';

/// The failure the plugin actually reports, and the one that shipped the bug.
///
/// `unknown_path` is not a pick that came back with a null path - the page
/// handles that, and counts it as skipped. The Android delegate fails the
/// *whole* call when `FileUtils.openFileStream` answers null for what the
/// user chose, which is what a provider handing back no stream looks like
/// from here.
final _refused = PlatformException(
  code: 'unknown_path',
  message: 'Failed to retrieve path.',
);

void main() {
  late DeviceController device;
  late _Listing storage;

  setUp(() {
    (device, _) = mountedDevice();
    storage = _Listing();
    // Set and not restored, which is `oversized_pick_test.dart`'s convention
    // and not laziness: `FilePicker.platform` is a `late` field with no value
    // off a real platform, so *reading* it to put it back is what throws.
    // Every test that cares installs its own in its own `setUp`.
    FilePicker.platform = _RefusingPicker();
  });

  /// Opens the browser, then the FAB sheet, then taps Upload files.
  Future<void> tapUpload(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithDevice(FileManagerPage(client: storage), device),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nGlobal.fmUploadFiles));
    await tester.pumpAndSettle();
  }

  testWidgets('a refused pick leaves the browser standing', (tester) async {
    await tapUpload(tester);

    // The listing is the page, and a page that is gone cannot show it. Framed
    // on what is still there rather than on "no exception", because the
    // uncaught error is what `testWidgets` reports by itself and an assertion
    // claiming to check it would pass on a page that never built at all.
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('and says the pick failed instead of nothing', (tester) async {
    await tapUpload(tester);

    expect(find.text(l10nGlobal.commonPickFailed), findsOneWidget);
  });

  testWidgets('and the FAB still opens, so the user can try again', (
    tester,
  ) async {
    // The refusal leaves through a `catch` that returns. A sheet left open, or
    // a guard left armed, would make the page unusable without restarting it -
    // which is the shape the plotter's own refusal test watches for.
    await tapUpload(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text(l10nGlobal.fmUploadFiles), findsOneWidget);
  });
}

/// Rejects every pick, the way the Android delegate does.
class _RefusingPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => throw _refused;
}

/// One folder with one file in it, and nothing else answered.
///
/// Lifted from `file_manager_double_open_test.dart`'s fake rather than shared
/// with it: that one parks a read to hold a download in flight, which is a
/// state this has no use for, and a fake that serves both grows a flag per
/// test.
class _Listing implements FlipperClient {
  final _listing = <String, List<fl.File>>{
    '/ext': [fl.File(name: 'notes.txt', type: File_FileType.FILE, size: 16)],
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
