// Stand-ins for `file_picker`, and the channel a folder pick talks to.
//
// Four files each set the picker to a one-method fake before this, spelling
// out the plugin's thirteen-parameter `pickFiles` signature four times and
// repeating four times why the field is set and not restored. This is where
// the next one goes - which is what made the `file_picker` 13 bump one edit
// here instead of five.
//
// What that bump changed, because the shape of these fakes is the shape of the
// API: `FilePicker` became a class of statics in 11.0.0, so the settable seam
// is `FilePickerPlatform.instance`, whose token a subclass inherits from the
// default constructor - no `plugin_platform_interface` mixin and no new dev
// dependency. `FilePickerResult` is gone: `pickFiles` answers
// `List<PlatformFile>` and `pickFile` a `PlatformFile?`. And `PlatformFile`
// can no longer be constructed - see [StubPickedFile].
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
/// plugin's own implementation against this same channel - `FilePickerAndroid`
/// since 12.0.0 split `FilePickerIO` into one package per platform.
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

/// A file the platform returned, as the code under test sees it.
///
/// `PlatformFile` is an `abstract base class`, so this extends it rather than
/// implementing it, and `base` requires this class to be `final` in turn. Only
/// [path] and [name] answer: production reads the first, and the second for
/// one log line. Everything else throws, and that is the point - the bytes of
/// a pick are read through `readPickedFile`, which stats and reads the path
/// itself, so a test that started reaching for them would be a regression
/// rather than a surprise.
///
/// **[path] is answered verbatim rather than derived from a [Uri]**, which the
/// base class would otherwise do for us. Deriving it made this host-dependent
/// and cost a red CI run: `Uri.file('C:/tmp/fw.tgz')` is absolute on Windows
/// and *relative* on Linux, a relative file URI carries no scheme, and
/// `PlatformFile.path` answers null for any scheme but `file:` - so a fixture
/// that named a file locally named nothing on the runner. Handing the string
/// back untouched is also what the plugin does with what the platform sent.
///
/// `AndroidPlatformFile` from the `android_file_picker` dev dependency would
/// also do, and would read bytes for real.
final class StubPickedFile extends PlatformFile {
  StubPickedFile({required this.path, required this.name});

  /// A file the platform returned without a usable path.
  ///
  /// Android reports one for a Storage Access Framework pick it could not
  /// resolve to disk - the outcome a page reports and then forgets.
  StubPickedFile.unusable({required this.name}) : path = null;

  @override
  final String? path;

  @override
  final String name;

  @override
  Uri get uri => throw UnsupportedError('a stub picked file has no uri');

  /// Typed by override inference, so that naming `XFile` does not make
  /// `cross_file` a direct dependency of a test.
  @override
  get xFile => throw UnsupportedError('a stub picked file has no XFile');

  @override
  int? lengthSync() => throw UnsupportedError('a stub has no length');

  @override
  Future<int?> length() => throw UnsupportedError('a stub has no length');

  @override
  Future<Uint8List> readAsBytes() =>
      throw UnsupportedError('a stub picked file has no bytes');

  @override
  Stream<Uint8List> readAsByteStream() =>
      throw UnsupportedError('a stub picked file has no bytes');
}

/// A stand-in for the plugin, as the code under test sees it.
///
/// Set on `FilePickerPlatform.instance` and not put back: a test that installs
/// a picker does so before it pumps, and the next test installs its own.
///
/// One class for every method and all three answers, because the fakes this
/// replaced differed by one value each: a folder, some files, or a throw.
class StubFilePicker extends FilePickerPlatform {
  StubFilePicker({this.folder, this.files = const [], this.failure, this.gate});

  /// What `getDirectoryPath` answers.
  final String? folder;

  /// What `pickFiles` answers, and whose first entry `pickFile` answers.
  ///
  /// An empty list is a cancellation - which since 12.0.0 is all it can be:
  /// every implementation maps the channel's null to `[]`, and
  /// `android_file_picker` 2.1.1 made a pick whose files could none of them be
  /// read fail with `unknown_path` rather than answer empty. #354's case is a
  /// [failure] now.
  final List<PlatformFile> files;

  /// Thrown by whichever method is called, in place of answering.
  final Object? failure;

  /// Held before answering, which is a system dialog still on screen.
  ///
  /// Build it outside `testWidgets`' `FakeAsync` zone when the test completes
  /// it from the body, or the continuation lands after the body has run.
  final Completer<void>? gate;

  /// How many times one of the three methods below was called.
  int calls = 0;

  /// The arguments the last `getDirectoryPath` was given, which the desktop
  /// path has to forward and the mobile one drops.
  String? title;
  String? initial;

  /// Counts the call, waits out [gate] and throws [failure], then answers
  /// [value].
  ///
  /// The three overrides below differ by that one expression; without this the
  /// next thing added to the sequence - `gate` was the last - is three edits
  /// with nothing checking that they agree.
  Future<T> _answer<T>(T value) async {
    calls++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    title = dialogTitle;
    initial = initialDirectory;
    return _answer(folder);
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => _answer(files);

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => _answer(files.isEmpty ? null : files.first);
}
