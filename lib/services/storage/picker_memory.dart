import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../settings/persist.dart';
import 'paths.dart';

/// What a system picker is picking for, which decides where it opens.
///
/// Every picker in the app names one, and each place remembers the folder it
/// was last used in, separately from the others: a firmware archive in
/// Downloads says nothing about where the user keeps key dumps. Until a place
/// has been used it opens in the folder its kind of file most likely lives
/// in, and never at the root, which is where a picker with no starting folder
/// lands on Linux - `zenity` and `kdialog` open in the working directory, and
/// an app started from a launcher is often running in `/`.
///
/// `test/picker_memory_test.dart` holds that no picker under `lib/` opens
/// without one.
enum PickerPlace {
  /// Anything without a place of its own: files going to and from the
  /// Flipper, keys saved out of the archive, captures read into the plotter.
  disk('picker_last_disk', _FirstFolder.home),

  /// Firmware archives, which arrive from a browser.
  firmware('picker_last_firmware', _FirstFolder.downloads),

  /// Screenshots and screen recordings.
  media('picker_last_media', _FirstFolder.pictures),

  /// Application source folders for Flibler.
  ///
  /// The key predates this file and is kept, so the folder a user picked
  /// before it existed is still the one Flibler opens in.
  flibler('flibler_last_folder', _FirstFolder.home),

  /// Pixel editor projects, animations and the images imported into them.
  paint('picker_last_paint', _FirstFolder.pictures);

  const PickerPlace(this._prefsKey, this._first);

  final String _prefsKey;
  final _FirstFolder _first;
}

/// Where a place opens before it has been used.
enum _FirstFolder { home, downloads, pictures }

/// Whether this platform's pickers can be told where to open.
///
/// The desktops only. On Android and iOS `file_picker` drops
/// `initialDirectory` for a file and a folder pick, and for a save it hands
/// it to the platform as a URI - a `content://` tree on Android - which a
/// filesystem path is not. A file pick there also answers with a copy in the
/// app's cache, so the folder it was "picked from" is not one the user has
/// ever seen. Both systems remember the last location per app on their own,
/// which is the behaviour this file adds to the desktops.
///
/// Read off `defaultTargetPlatform` rather than `Platform`, so a test can put
/// a desktop under it.
bool get _remembers {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    default:
      return false;
  }
}

/// The folder a picker for [place] should open in, or null for the system's
/// own choice.
///
/// The folder [place] was last used in, while it still exists; otherwise the
/// first of [firstFoldersFor] that does. Null on Android and iOS, where
/// nothing is passed down, and when no candidate exists at all.
///
/// **Never throws**: it runs on the way to a picker the user tapped for, and
/// a picker that opens in the wrong folder is better than one that does not
/// open. Each step that touches a platform reports its own failure.
///
/// The checks are `existsSync` on purpose. They are a stat each, and the
/// async form never completes under the fake clock a widget test runs on, so
/// every page test that reaches a picker on a desktop would hang.
Future<String?> pickerStart(PickerPlace place) async {
  if (!_remembers) return null;
  final last = await _lastFolder(place);
  if (last != null && _isFolder(last)) return last;
  final home = desktopHomeDirectory();
  final candidates = firstFoldersFor(
    place,
    windows: io.Platform.isWindows,
    home: home,
    downloads: place._first == _FirstFolder.downloads
        ? await _knownDownloads(place)
        : null,
    xdgPictures: place._first == _FirstFolder.pictures && io.Platform.isLinux
        ? _xdgUserDir('PICTURES', home)
        : null,
  );
  for (final candidate in candidates) {
    if (_isFolder(candidate)) return candidate;
  }
  return null;
}

/// Remembers [folder] as where [place] was last used. Never throws.
///
/// Null and empty are ignored, so a site can hand over a cancelled pick's
/// answer as it came. Nothing is written on Android and iOS: see
/// [pickerStart] for why nothing there would ever read it.
Future<void> rememberPickerFolder(PickerPlace place, String? folder) async {
  if (!_remembers || folder == null || folder.isEmpty) return;
  await persistSetting(
    'the ${place.name} picker folder',
    (prefs) => prefs.setString(place._prefsKey, folder),
  );
}

/// Remembers the folder that holds [file] as where [place] was last used.
///
/// For a file pick and a save, which answer a file rather than a folder.
Future<void> rememberPickedFile(PickerPlace place, String? file) async {
  if (file == null || file.isEmpty) return;
  await rememberPickerFolder(place, io.File(file).parent.path);
}

/// Where [place] opens before it has been used, best first, unchecked.
///
/// The home folder is always last: it exists on every desktop and it is
/// where the user starts from in their own file manager, which the root is
/// not.
///
/// * Downloads is [downloads] when the platform named it - `path_provider`
///   asks Windows for its known folder, which follows a OneDrive or manual
///   redirect, and reads `XDG_DOWNLOAD_DIR` on Linux, which is how a Russian
///   desktop's `~/Загрузки` is found - and the conventional name under
///   [home] otherwise.
/// * Pictures has no `path_provider` call. Linux reads `XDG_PICTURES_DIR`,
///   handed in as [xdgPictures]; Windows tries `Pictures` and then the
///   OneDrive copy that Known Folder Move leaves behind it; macOS has the
///   one name.
///
/// [windows] picks the separator, so every desktop's answer can be checked
/// on the Linux machine CI runs on.
@visibleForTesting
List<String> firstFoldersFor(
  PickerPlace place, {
  required bool windows,
  required String? home,
  String? downloads,
  String? xdgPictures,
}) {
  final sep = windows ? r'\' : '/';
  String? under(String name) => home == null ? null : '$home$sep$name';
  final folders = <String?>[
    ...switch (place._first) {
      _FirstFolder.home => const <String?>[],
      _FirstFolder.downloads => [downloads, under('Downloads')],
      _FirstFolder.pictures => [
        xdgPictures,
        under('Pictures'),
        if (windows) under('OneDrive${sep}Pictures'),
      ],
    },
    home,
  ];
  return [
    for (final folder in folders)
      if (folder != null && folder.isNotEmpty) folder,
  ];
}

/// The value of `XDG_<name>_DIR` in a `user-dirs.dirs` file, or null.
///
/// The format is shell assignments, one per line: `XDG_PICTURES_DIR=
/// "$HOME/Изображения"`. The spec allows a path that is absolute or starts
/// with `$HOME`, and a folder equal to the home folder means the entry is
/// switched off, so both of those answer null rather than the home folder
/// standing in for Pictures.
@visibleForTesting
String? parseXdgUserDir(String contents, String name, String home) {
  final prefix = 'XDG_${name}_DIR=';
  for (final raw in const LineSplitter().convert(contents)) {
    final line = raw.trim();
    if (!line.startsWith(prefix)) continue;
    var value = line.substring(prefix.length).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.startsWith(r'$HOME')) value = home + value.substring(5);
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.startsWith('/') || value == home) return null;
    return value;
  }
  return null;
}

/// `existsSync` answers false for a path the OS will not stat - a drive
/// letter that is gone, a name it refuses - rather than throwing, and a
/// folder the picker cannot open is exactly what false means here.
bool _isFolder(String path) => io.Directory(path).existsSync();

Future<String?> _lastFolder(PickerPlace place) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(place._prefsKey);
    return value == null || value.isEmpty ? null : value;
  } catch (e, st) {
    // `caught`: the picker still opens, in the place's first folder, and the
    // user sees nothing but that. A store that will not read is worth
    // knowing about when someone says the app forgets their folders.
    LogService.caught(
      '[Picker] the ${place.name} folder could not be read: '
      '${LogService.describe(e, st)}',
    );
    return null;
  }
}

Future<String?> _knownDownloads(PickerPlace place) async {
  try {
    return (await getDownloadsDirectory())?.path;
  } catch (e, st) {
    LogService.caught(
      '[Picker] the system would not name Downloads for the ${place.name} '
      'picker: ${LogService.describe(e, st)}',
    );
    return null;
  }
}

/// `XDG_<name>_DIR` from the user's `user-dirs.dirs`, or null.
String? _xdgUserDir(String name, String? home) {
  if (home == null) return null;
  try {
    final config = io.Platform.environment['XDG_CONFIG_HOME'];
    final base = config != null && config.isNotEmpty ? config : '$home/.config';
    final file = io.File('$base/user-dirs.dirs');
    if (!file.existsSync()) return null;
    return parseXdgUserDir(file.readAsStringSync(), name, home);
  } catch (e, st) {
    // The conventional name under home is the next candidate either way, so
    // the picker still opens somewhere sensible. Kept because a desktop that
    // writes this file unreadably is the one where Pictures will be wrong.
    LogService.caught(
      '[Picker] user-dirs.dirs could not be read: '
      '${LogService.describe(e, st)}',
    );
    return null;
  }
}
