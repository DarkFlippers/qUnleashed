import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/localization/l10n.dart';
import '../services/logging.dart';
import '../services/storage/picker_memory.dart';
import 'notification.dart';

export '../services/storage/picker_memory.dart' show PickerPlace;

/// The channel `file_picker` registers on Android and iOS.
///
/// Taken from the plugin, which since the 12.0.0 federated split declares it
/// in three places with the default [StandardMethodCodec]: `FilePickerAndroid`
/// (`android_file_picker` 2.1.5), `FilePickerDarwin` (`file_picker_darwin`
/// 2.5.1), and `MethodChannelFilePicker` in the platform interface, which
/// overrides nothing and is a dead default.
///
/// [pickFolder] sends `dir` with an empty argument map, and **the empty map is
/// load-bearing now where it used to be merely equal to the plugin's.** 13.x
/// sends arguments for `dir`: Darwin the title and the initial directory,
/// which its native side ignores for a directory panel, and Android
/// `androidSafOptions` - which flips a branch in `FileUtils.kt`, answering
/// `data.data.toString()`, a `content://…/tree/…` URI, instead of the
/// filesystem path `getFullPathFromTreeUri` resolves. Every caller here uses
/// the answer as a path. The app's own fall-back sends null for it too, since
/// `FilePicker.getDirectoryPath`'s default is `AndroidOptions` and not
/// `FilePickerAndroidOptions`, so both halves of this function agree only
/// while this map stays empty.
///
/// **Reaching past the plugin's Dart layer is the fix**, not a shortcut around
/// it. `android_file_picker` 2.1.5's `getDirectoryPath` wraps its `dir` call in
/// `on PlatformException`, prints for `unknown_path` alone and returns null for
/// every one of them, so `already_active`, `invalid_format_type` and
/// `unknown_activity` leave no trace at all. From Dart a refused folder pick
/// and a cancelled one are therefore the same value, and nothing above it can
/// tell them apart, which is #353. The call *we* make sees the refusal.
///
/// That is what settled #353's "try upstream first", and it survived five
/// majors: a version bump would not fix this, and the 13.x bump did not.
///
/// At `^13.3.3` the method is still `dir` on both platforms; the argument map
/// is the thing that moved, which is the paragraph above. The two halves still
/// fail differently:
///
///  * **a renamed channel degrades.** `invokeMethod` throws
///    [MissingPluginException] before anything native runs, and [pickFolder]
///    falls back to the plugin's own call - the fix goes quiet, folder picks
///    keep working, and one line says so.
///  * **a renamed method used not to.** `FilePickerPlugin.java` called
///    `result.notImplemented()` for a type it could not resolve and then
///    carried on *without returning*, which latched the delegate for the life
///    of the process: the fall-back's call then got `already_active`, which
///    the plugin swallows, and every folder pick in the app answered null.
///    `FilePickerPlugin.kt`'s `else ->` branch now returns, so a renamed
///    method degrades like a renamed channel. `test/folder_pick_test.dart`
///    pins the method name against the plugin's own call anyway, rather than
///    against a copy of it - nothing in a compile can, and the latch is one
///    upstream change away from coming back.
///
/// **What would retire this file**: two upstream behaviours, not one.
/// `getDirectoryPath` rethrowing the way `pickFiles` already does - and `dir`
/// answering a path whatever `androidSafOptions` says, because while that
/// argument changes the kind of string that comes back, a copy of the call is
/// the only way to be sure which kind this app gets. Either in the plugin or
/// in a fork. Then the five sites could
/// go back to the plugin's own call - with their own `try` each, which is what
/// `picker_guard_test.dart`'s first rule is for. A fork was weighed and not
/// taken: it removes the two copied constants and costs a repository tracking
/// five platforms' native code, and it would not subsume this file anyway,
/// because the log tag, the sentence and the never-rejects contract still want
/// one place to live.
const String _pluginChannelName = 'miguelruivo.flutter.plugins.filepicker';

const MethodChannel _pluginChannel = MethodChannel(_pluginChannelName);

/// Whether the plugin's own folder pick hides its failures on this platform.
///
/// Android and iOS, the two platforms whose implementations catch and answer
/// null - `android_file_picker` and `file_picker_darwin`, which replaced the
/// single `FilePickerIO` in 12.0.0.
///
/// The other targets need no workaround, for two different reasons. Linux and
/// Windows are Dart implementations that let a failure out: `file_picker_linux`
/// 2.0.4 goes through the XDG desktop portal over D-Bus and lets its error
/// through - the `zenity` this used to name is gone from it - and Windows
/// throws from its COM call.
///
/// macOS is the one that changed shape. It is served by `file_picker_darwin`,
/// which answers `dir` on both Darwin platforms
/// (`case "dir", "getDirectoryPath":`), so the channel branch would reach real
/// native code there rather than earning a [MissingPluginException] and the
/// fall-back. It is left out all the same: its `getDirectoryPath` rethrows
/// nothing but `window_not_found`, which `registerWith` cannot produce, so the
/// swallow is the same - but the case below is native and no Dart call can see
/// past it, so taking the channel branch would buy a different null rather
/// than a cause.
///
/// **macOS keeps one case of #353 and nothing here can fix it.**
/// `handleDirectorySelection` in the Swift plugin answers
/// `result(url.path)` for an `OK` with a URL and `result(nil)` for everything
/// else - including an `OK` whose panel has no resolvable URL, under a comment
/// reading "User dismissed the dialog". That collapse is native, so no Dart
/// call can see past it.
///
/// Web is excluded outright: `defaultTargetPlatform` there reports the
/// *browser's* host platform, so a phone browser would take the channel
/// branch, get [MissingPluginException] and log the fall-back line on every
/// pick with nothing actually wrong - polluting the one line in this file that
/// is supposed to mean something.
///
/// It is a guard on a path that cannot run today and cannot be tested either:
/// the app does not build for web at all (`services/` imports `dart:io`,
/// flipperlib `dart:ffi`), and `kIsWeb` is a compile-time `false` under the
/// VM, so a mutation that removes this line survives the suite. Kept anyway,
/// because one word is cheaper than the failure it describes and the shipped
/// targets are Android, iOS and four desktops.
bool get _pluginHidesFolderFailures {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

/// Whether a folder pick is on screen, so a second one is not started.
///
/// The platform allows one picker at a time and says so badly: Android
/// answers `already_active` (`FilePickerDelegate.kt`), iOS `multiple_request`.
/// iOS used also to clear its pending result handle before replying, so the
/// second request abandoned the future belonging to the picker the user was
/// actually looking at; `IOSFilePickerHandler.swift` in `file_picker_darwin`
/// 2.5.1 answers the *second* caller and leaves the first's result alone
/// unless its picker is stale. Both are swallowed into a null that reads as a
/// cancel; surfacing them would report a double tap as a failed pick, which is
/// a wrong sentence rather than a missing one.
///
/// Not an `_isPicking` on one page, because the platform's limit is
/// app-wide - `flibler/project/page.dart`'s button, for one, is enabled
/// between the tap and the system dialog appearing.
///
/// **It covers the folder half only.** `pickFiles` does not come through here
/// and does not need to: it rethrows rather than swallowing, so a second file
/// pick reports its own refusal, and the two surfaces that take more than one
/// frame to open one hold a `_picking` flag of their own that also disables
/// the control - which is the better shape, because the user sees why nothing
/// happened. `test/double_tap_guards_test.dart` is that family (#244). One
/// seam owning both would be the general answer and is bigger than #353.
bool _picking = false;

/// Opens the system folder picker and answers the chosen directory, or null.
///
/// **Never rejects.** Null means the user cancelled, the pick failed, or a
/// pick was already open, and those are deliberately not distinguishable to
/// the caller: a cancellation is by far the common case and a sentence on
/// every cancel is worse than silence, so a failure is reported from in
/// here - one line at [LogService.caught] under [what], and a sentence on
/// screen - before null goes back. A caller that returns silently on null is
/// therefore right, and there is no shape of caller that is wrong: this is
/// reached from `VoidCallback` taps and sheet entries whose rejection would
/// have no listener at all and would reach the zone as a fatal error, which is
/// QUNLEASHED-K's mechanism and why `test/picker_guard_test.dart` exists.
///
/// [what] is the log line's subject, in `[Area] what it was doing` form, as
/// `guarded()` takes it. The sentence on screen carries no cause - the folder
/// picks share two between them - so the line is the only thing that can tell
/// a refused tree URI from a missing picker, and one tag per surface is what
/// makes a report readable. `test/picker_guard_test.dart` holds that the five
/// tags are distinct.
///
/// [place] is where the picker opens and what it remembers the chosen folder
/// as - see [PickerPlace]. Required, so a new surface cannot open at the root
/// by leaving it out.
///
/// [dialogTitle] and [place] reach the desktop pickers only. On Android and
/// iOS the plugin drops a title and a starting folder both, and so does the
/// channel call here; [pickerStart] answers null there and nothing is
/// remembered.
Future<String?> pickFolder(
  BuildContext context, {
  required String what,
  required String dialogTitle,
  required PickerPlace place,
}) async {
  if (_picking) return null;
  _picking = true;
  try {
    if (_pluginHidesFolderFailures) {
      try {
        return await _pluginChannel.invokeMethod<String>(
          'dir',
          const <String, dynamic>{},
        );
      } on MissingPluginException {
        // The channel moved, or the plugin is not registered on this build.
        // Fall through to its own call rather than reporting every pick as
        // failed: that answers null the way it always did, which is the
        // behaviour this function improves on, not one it can break.
        //
        // Recorded because the fall-through is a silent loss of the fix - a
        // major bump that renames the channel leaves folder picks working and
        // refusals invisible again, which is the state #353 describes and
        // nothing else would say. Nobody is paged for it: this is the one line
        // that tells a reader of a report which half of this function ran, and
        // `LogService`'s fold keeps a run of them at one line per surface.
        LogService.caught(
          '$what fell back to the plugin: no handler on $_pluginChannelName',
        );
      }
    }
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: await pickerStart(place),
    );
    await rememberPickerFolder(place, picked);
    return picked;
  } catch (e, st) {
    LogService.caught('$what failed: ${LogService.describe(e, st)}');
    try {
      if (context.mounted) {
        context.showNotification(
          // `fmFolderPickUnsupported` is "Choosing a folder is not supported
          // on this platform", and a missing implementation is the one failure
          // it describes correctly - the `fm` in the name is where it was
          // first needed, not what it means. Everything else gets
          // `commonPickFailed`, including a Linux desktop whose portal will
          // not answer: saying which piece is missing would be a new string,
          // which is the translation branch's call (ADR 0016).
          e is MissingPluginException
              ? context.l10n.fmFolderPickUnsupported
              : context.l10n.commonPickFailed,
          type: QNotificationType.error,
        );
      }
    } catch (e2, st2) {
      // The line above is the record, so this cannot be the thing that
      // rejects: `showNotification` reads the root [Overlay] and the theme's
      // `appColors` off the context it was handed, and five callers with no
      // `try` between them rely on the promise in this function's first
      // sentence. `guarded.dart`'s innermost fallback is the same shape, and
      // for the same reason.
      LogService.caught(
        '$what could not be shown: ${LogService.describe(e2, st2)}',
      );
    }
    return null;
  } finally {
    _picking = false;
  }
}
