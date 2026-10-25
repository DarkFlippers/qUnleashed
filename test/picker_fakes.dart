// Stand-ins for `file_picker`, and the channel a folder pick talks to.
//
// Four files set `FilePicker.platform` to a one-method fake before this
// (`double_tap_guards_test.dart`, `firmware_double_start_test.dart`,
// `oversized_pick_test.dart`, `unguarded_pick_test.dart`), each spelling out
// the plugin's thirteen-parameter `pickFiles` signature and each repeating why
// the field is set and not restored. This is where the next one goes: the
// signature belongs to a package pinned at `^8.1.2`, and `folder_pick.dart`'s
// own doc expects that major bump - which is one edit here instead of one per
// copy. The four are not converted in this change; they are the migration
// after it.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel `file_picker` registers on Android and iOS.
///
/// A test-side copy of a name the *plugin* owns, deliberately not imported
/// from `lib/`: a test that asserts the shim talks on this channel would
/// otherwise agree with the production constant however wrong both were.
/// `folder_pick_test.dart` closes that loop from the other side by driving the
/// plugin's own `FilePickerIO` against this same channel.
const MethodChannel folderPickChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// Answers [folderPickChannel] for the duration of the test.
///
/// [path] is what a `dir` call answers - null for a cancelled pick, which is
/// what both mobile platforms report. [failure] is thrown instead, and [gate]
/// holds the answer until it completes, which is a system dialog still on
/// screen. Every call is appended to [calls] when one is given.
///
/// Leaving this uninstalled is not the third state it looks like: an
/// unregistered channel under `flutter_test` does not answer at all, so the
/// future never completes and the case hangs for the whole timeout. A missing
/// plugin is [MissingPluginException] *thrown* from here.
void answerFolderPick({
  String? path,
  Object? failure,
  Completer<void>? gate,
  List<MethodCall>? calls,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(folderPickChannel, (call) async {
        calls?.add(call);
        if (gate != null) await gate.future;
        if (failure != null) throw failure;
        return path;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickChannel, null),
  );
}

/// The plugin's own implementation, as the code under test sees it.
///
/// Set on `FilePicker.platform` and not put back, the way every picker test in
/// this suite does it and for the same reason: the field is `late` with no
/// value off a real platform, so *reading* it to restore it is what throws.
/// Safe because a test that installs a picker does so before it pumps.
///
/// One class for both methods and all three answers, because the three fakes
/// this replaced differed by one value each: a folder, a result, or a throw.
class StubFilePicker extends FilePicker {
  StubFilePicker({this.folder, this.result, this.failure});

  /// What `getDirectoryPath` answers.
  final String? folder;

  /// What `pickFiles` answers. `FilePickerResult(const [])` is the pick where
  /// the platform dropped every chosen item; null is a cancellation.
  final FilePickerResult? result;

  /// Thrown by whichever method is called, in place of answering.
  final Object? failure;

  /// How many times either method was called.
  int calls = 0;

  /// The arguments the last `getDirectoryPath` was given, which the desktop
  /// path has to forward and the mobile one drops.
  String? title;
  String? initial;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    calls++;
    title = dialogTitle;
    initial = initialDirectory;
    if (failure != null) throw failure!;
    return folder;
  }

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
  }) async {
    calls++;
    if (failure != null) throw failure!;
    return result;
  }
}
