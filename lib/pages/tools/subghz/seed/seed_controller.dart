import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../../services/logging.dart';
import '../../../../services/native.dart';
import 'faaccrack_recoverer.dart';
import 'seed_capture_format.dart';
import 'seed_models.dart';
import 'seed_sub_file.dart';

/// What the page is doing.
enum SeedStage { idle, listing, loading, searching }

/// Why something the user asked for did not happen.
///
/// An enum rather than an exception string, so the page can say it in the
/// user's language and so the set is exhaustive - what ADR 0008 asks for where
/// a failure needs differentiated UI. Each member is a different thing to do
/// next, which is the test for whether it earns one.
enum SeedFailure {
  disconnected,
  unreadableCapture,
  readFailed,
  listFailed,
  invalidName,
  nameTaken,
  nameUnchecked,
  saveFailed,
  deleteFailed,
}

/// A capture file the device is holding, before it is read.
typedef SeedCaptureFile = ({String path, String name, int size});

/// Drives one seed recovery: list the captures, read one, search, write the
/// recovered remote back.
///
/// `ChangeNotifier` and `setState`, like the rest of the app (ADR 0001), with
/// the client passed in rather than reached for (ADR 0002).
class SeedController extends ChangeNotifier {
  SeedController({required this._client, FaaccrackRecoverer? recoverer})
    : _recoverer = recoverer ?? NativeFaaccrackRecoverer();

  /// The Flipper this run belongs to. Passed in rather than reached for, and
  /// required rather than defaulted, so a recovery cannot silently run against
  /// a different device from the one the page was opened on (ADR 0002).
  final FlipperClient _client;
  final FaaccrackRecoverer _recoverer;

  SeedStage _stage = SeedStage.idle;
  List<SeedCaptureFile> _files = const [];
  SeedCapture? _capture;
  SeedResult? _result;
  double _progress = 0;
  bool _stopping = false;
  SeedFailure? _error;
  String? _savedTo;
  List<String> _captureWarnings = const [];
  bool _saving = false;
  SeedCaptureFile? _openedFile;
  FlipperSessionBinding? _savedBinding;
  bool _disposed = false;

  @override
  void dispose() {
    // Every one of the three device operations outlives the page if the user
    // leaves mid-flight - a search most of all, since a stop takes a moment to
    // land. Without this, the notifyListeners() that follows throws inside a
    // future nobody is listening to.
    _disposed = true;
    super.dispose();
  }

  /// Notifies, unless the page has already gone.
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  SeedStage get stage => _stage;
  List<SeedCaptureFile> get files => _files;
  SeedCapture? get capture => _capture;
  SeedResult? get result => _result;
  double get progress => _progress;
  bool get cancelled => _stopping;
  SeedFailure? get error => _error;

  /// Where the recovered remote was written, once it has been.
  String? get savedTo => _savedTo;

  /// Whether a save is in flight.
  ///
  /// [savedTo] cannot answer this: it is set only once the write has landed, so
  /// between the stat and the last frame it is still null and a second press
  /// starts a second, independent write of the same file.
  bool get saving => _saving;

  /// The capture currently open, or null when none is.
  SeedCaptureFile? get openedFile => _openedFile;

  /// Whether the open capture can be offered for deletion.
  ///
  /// Only after it has been written somewhere else. Offering to delete the
  /// one copy of a capture that has not been solved and saved is offering to
  /// destroy the only record of a remote the user may not have again.
  bool get canDeleteCapture => _openedFile != null && _savedTo != null;

  /// Lines the capture file had that could not be read. Shown rather than
  /// logged alone: a file half of whose hops were dropped may no longer have
  /// consecutive ones, and the search would then find nothing for a reason that
  /// is not about the remote.
  List<String> get captureWarnings => _captureWarnings;

  /// Whether the recovered remote can be written as a transmittable file.
  ///
  /// Four things have to hold. The frequency is the one that is easy to forget:
  /// it is not recoverable from a fix and a hop, so a capture without it can be
  /// solved but not written. The hop count is the one that matters most: the
  /// native header draws the confidence line at [seedHopsConfident] and says an
  /// answer below it should be shown "rather than offered for transmission", and
  /// a two-hop false positive is exactly what it calls conceivable.
  ///
  /// `round_trip_ok` is not independent protection here. It checks that the
  /// plaintext layout was right for the protocol, not that the key is right, so
  /// a wrong seed from too few hops still arrives as a success.
  bool get canSave =>
      _result?.outcome == SeedOutcome.found &&
      _result?.frameHop != null &&
      // Checked because `render` dereferences it. Without this the throw
      // escapes `_save`, escapes `runTask`, and lands in a discarded future as
      // an `[uncaught]` naming no operation - with the page unchanged.
      _result?.seed != null &&
      (_result?.hopsUsed ?? 0) >= seedHopsConfident &&
      _capture?.frequencyHz != null;

  /// Runs a device operation as one task on this Flipper's session, after
  /// clearing whatever failed last.
  ///
  /// The session binding is what every other device-touching controller here
  /// does: with auto-reconnect on, work that spans minutes is otherwise free to
  /// finish against whichever device happens to be live by then. The clearing
  /// is ADR 0008's rule that a failure is cleared at the start of the operation
  /// that could replace it - and one wrapper rather than four preludes, because
  /// the fourth copy was the one that forgot.
  Future<void> _task(Future<void> Function() body) {
    _error = null;
    return _client.runTask(FlipperRequestPriority.background, body);
  }

  /// Lists the captures the device is holding.
  Future<void> refresh() => _task(_refresh);

  Future<void> _refresh() async {
    // A stage, so the toolbar can say it is working: the answer is usually
    // identical to what is already on screen, and without a word of it the
    // button re-read the folder and looked dead.
    _stage = SeedStage.listing;
    _changed();
    try {
      final batch = await _client.storageList(
        ListRequest(path: seedCaptureDir),
        timeout: const Duration(seconds: 20),
      );
      final found = <SeedCaptureFile>[];
      for (final response in batch.items) {
        for (final file in response.file) {
          if (file.type != File_FileType.FILE) continue;
          if (!file.name.endsWith(seedCaptureExtension)) continue;
          found.add((
            path: '$seedCaptureDir/${file.name}',
            name: file.name,
            size: file.size,
          ));
        }
      }
      // Newest first: the capture someone just took is the one they want.
      // The name carries the timestamp, so sorting by it is sorting by time
      // without trusting the device's clock to have been set.
      found.sort((a, b) => b.name.compareTo(a.name));
      _files = List.unmodifiable(found);
    } on FlipperRpcStorageNotExistException {
      // A device that has never run the capture app has no such folder. The
      // one failure that really is "nothing captured yet", and the firmware
      // says so by name rather than by an error string.
      _files = const [];
    } catch (e) {
      // Everything else - an SD not mounted, a busy session, the 20 s timeout
      // on a congested link - is a question that went unanswered. Reporting it
      // as an empty folder sends the user to re-record a remote they already
      // captured, which is exactly what this catch exists to prevent; and the
      // list is left standing rather than wiped, because the rows on screen
      // are still the last thing the device actually said.
      LogService.error('[Seed] could not list $seedCaptureDir: $e');
      _error = _client.isConnected
          ? SeedFailure.listFailed
          : SeedFailure.disconnected;
    } finally {
      _stage = SeedStage.idle;
    }
    _changed();
  }

  /// Reads one capture and parses it.
  Future<void> open(SeedCaptureFile file) => _task(() => _open(file));

  Future<void> _open(SeedCaptureFile file) async {
    _stage = SeedStage.loading;
    _error = null;
    _result = null;
    _savedTo = null;
    _capture = null;
    _openedFile = file;
    _captureWarnings = const [];
    _changed();

    try {
      final bytes = await _client.storageReadChunked(
        file.path,
        expectedSize: file.size,
        timeout: const Duration(minutes: 2),
      );
      final parsed = SeedCaptureFormat.parse(
        const Utf8Decoder(allowMalformed: true).convert(bytes),
      );
      _captureWarnings = List.unmodifiable(parsed.skipped);
      _capture = parsed.capture;
      if (parsed.skipped.isNotEmpty) {
        // warn, not info: info const-folds away in release, so a file whose
        // hops were half dropped would otherwise reach a user as "no seed
        // found" with nothing anywhere saying why.
        LogService.warn('[Seed] ${file.name}: ${parsed.skipped.join('; ')}');
      }
      if (parsed.capture == null) _error = SeedFailure.unreadableCapture;
    } catch (e) {
      LogService.error('[Seed] could not read ${file.path}: $e');
      _error = SeedFailure.readFailed;
    }
    _stage = SeedStage.idle;
    _changed();
  }

  /// Loads a capture directly, for tests that exercise the search without a
  /// device. `open()` is the real path and goes through the Flipper.
  @visibleForTesting
  void debugSetCapture(SeedCapture capture) {
    _capture = capture;
    _stage = SeedStage.idle;
  }

  /// Runs the search over the loaded capture, retrying over the windows a
  /// missed press can leave - see [windows].
  ///
  /// Not bound to a session, unlike the three operations above: the sweep runs
  /// in an isolate on this machine and issues no requests, so there would be
  /// nothing for a session to hold.
  Future<void> search() async {
    final capture = _capture;
    if (capture == null) return;

    _stage = SeedStage.searching;
    _stopping = false;
    _progress = 0;
    _result = null;
    _savedTo = null;
    _error = null;
    _changed();

    LogService.warn(
      '[Seed] searching ${capture.manufacturer.label} '
      '${capture.fix.toRadixString(16)} with ${capture.hops.length} hop(s) '
      'on ${NativeFaaccrackRecoverer.variantName()}',
    );

    // Never null by the time it is read: a search that visibly runs and ends
    // with nothing on screen is worse than one that says what happened.
    var last = seedResult(SeedOutcome.engineFault);
    try {
      for (final window in windows(capture.hops)) {
        if (_stopping) {
          // The stop landed between windows rather than inside one, so the
          // engine never saw it and `last` still holds the previous window's
          // answer. Without this the user who pressed Stop is told "no seed
          // matched this capture" and sent to re-record a remote that is fine.
          last = seedResult(SeedOutcome.stopped);
          break;
        }
        // Each window is a fresh sweep from zero, so the bar has to go back.
        _progress = 0;
        final attempt = await _recoverer.recover(
          manufacturer: capture.manufacturer,
          fix: capture.fix,
          hops: window,
          onProgress: (fraction) {
            _progress = fraction;
            _changed();
          },
          isCancelled: () => _stopping,
        );
        last = attempt;
        // Only "nothing matched" is worth narrowing the window for. Everything
        // else is either an answer or a fault, and retrying a fault would just
        // repeat it once per subset.
        if (attempt.outcome != SeedOutcome.nothingMatched) break;
      }
    } on NativeEngineUnavailable catch (e) {
      // The library did not load, or an entry point is missing from it - a
      // packaging fault that has shipped in this repo before. Without this the
      // throw escapes a discarded future, the page sits on "Searching..."
      // forever with a dead Stop button, and the only trace is an uncaught
      // zone error naming no operation.
      LogService.error('[Seed] engine unavailable, search did not start: $e');
      last = seedResult(SeedOutcome.engineUnavailable);
    } catch (e, st) {
      LogService.error(
        '[Seed] search failed for ${capture.fix.toRadixString(16)}: $e\n$st',
      );
      last = seedResult(SeedOutcome.engineFault);
    } finally {
      _result = last;
      _stage = SeedStage.idle;
      _changed();
    }
  }

  /// The hop sets to try.
  ///
  /// A capture with one missed press cannot solve *entire* - the acceptance
  /// test needs every decrypted counter to be one from the last - while the
  /// presses either side of the gap are still consecutive among themselves.
  ///
  /// Three windows are enough, and that is worth spelling out because the first
  /// version of this ladder offered twelve. A window solves exactly when its
  /// hops are consecutive, and a contiguous sub-run of a consecutive run is
  /// also consecutive - so a *short* window inside a gap-free run always solves
  /// if a longer one does. Meanwhile a sweep costs the same whatever the hop
  /// count: the engine scans the whole seed space either way, and extra hops
  /// only filter the candidates it finds. Length therefore buys confidence, not
  /// reach.
  ///
  /// So: the whole capture, for the strongest `hops_used` in one sweep; then
  /// the last [seedHopsConfident] hops, then the first. A single gap at
  /// position k leaves the suffix solvable when k is at or below n-3 and the
  /// prefix when k is at least 3, and for any capture of five or more those two
  /// ranges meet - every single-gap capture is covered in at most three sweeps
  /// instead of twelve.
  ///
  /// Suffix before prefix, which is not cosmetic: the counter and the rebuilt
  /// frame come from the window's *last* hop, so a prefix that solves first
  /// writes a remote several presses behind the counter the receiver has
  /// already seen. That is a `.sub` the firmware accepts and the gate ignores.
  @visibleForTesting
  static List<List<int>> windows(List<int> hops) {
    final found = <List<int>>[];

    void offer(List<int> window) {
      if (window.length < SeedCapture.minHops) return;
      if (window.length > SeedCapture.maxHops) return;
      for (final existing in found) {
        if (existing.length == window.length &&
            existing.first == window.first) {
          return;
        }
      }
      found.add(window);
    }

    // The freshest end of an over-long capture, for the same counter reason.
    final longest = hops.length < SeedCapture.maxHops
        ? hops.length
        : SeedCapture.maxHops;
    offer(hops.sublist(hops.length - longest));

    // The confident pair alone leaves a gap uncovered only on a capture short
    // enough that the two windows cannot meet in the middle - which is
    // n <= 2*seedHopsConfident - 2, so five windows instead of three for the
    // shortest captures and three for everything else.
    final lengths = <int>[
      seedHopsConfident,
      if (longest <= 2 * seedHopsConfident - 2) SeedCapture.minHops,
    ];
    for (final length in lengths) {
      if (length >= longest) continue;
      offer(hops.sublist(hops.length - length));
      offer(hops.sublist(0, length));
    }
    return found;
  }

  /// Asks the running search to stop. It lands within a claimed chunk, which is
  /// milliseconds - not the "pressed Stop and the bar kept going" the MIFARE
  /// engine had before #259.
  void stop() {
    _stopping = true;
    _changed();
  }

  /// The name to offer for the recovered remote, without the extension.
  ///
  /// Null when there is nothing to save, so the page cannot open a name dialog
  /// for a recovery that [canSave] would refuse.
  String? get suggestedName {
    final capture = _capture;
    if (!canSave || capture == null) return null;
    return SeedSubFile.baseName(
      manufacturer: capture.manufacturer,
      fix: capture.fix,
    );
  }

  /// Writes the recovered remote to the Flipper as a transmittable `.sub`.
  ///
  /// Into `/ext/subghz`, so it appears under Sub-GHz -> Saved: a seed shown on
  /// screen and nowhere else leaves the user to do the file work by hand.
  ///
  /// [baseName] comes from the user and carries no extension. Both guards live
  /// here rather than in the page: the name rules, and - because the write
  /// opens with CREATE_ALWAYS - whether anything is already there. A caller
  /// that skipped the second one would silently destroy a `.sub` the user
  /// recorded by hand, so it cannot be the caller's to skip. The firmware puts
  /// the same check inside its own save scene (`validator_is_file`).
  ///
  /// [replace] is the answer to [SeedFailure.nameTaken] or
  /// [SeedFailure.nameUnchecked] coming back: the page asks, and calls again.
  Future<void> save(String baseName, {bool replace = false}) =>
      _task(() => _save(baseName, replace: replace));

  Future<void> _save(String baseName, {required bool replace}) async {
    final capture = _capture;
    final result = _result;
    if (!canSave || capture == null || result == null) return;

    final problem = SeedSubFile.checkBaseName(baseName);
    if (problem != null) {
      // Its own failure, because "the Flipper refused this" is not true and
      // leaves the user with nothing to change. The rule goes in the log, not
      // just the name: for a 63-character or non-ASCII name it is not
      // deducible from the name alone.
      LogService.error('[Seed] refused "$baseName": ${problem.name}');
      _error = SeedFailure.invalidName;
      _changed();
      return;
    }

    final path = SeedSubFile.pathFor(baseName);
    _saving = true;
    _changed();
    try {
      if (!replace) {
        final standing = await _occupant(path);
        if (standing != null) {
          _error = standing;
          return;
        }
      }
      // Inside the try: `render` refuses an outcome that is not `found` and
      // dereferences the seed and the rebuilt frame. `canSave` covers all
      // three, but a throw from here would otherwise leave the page untouched.
      final contents = SeedSubFile.render(
        result: result,
        manufacturer: capture.manufacturer,
        fix: capture.fix,
        frequencyHz: capture.frequencyHz!,
        preset: capture.preset,
      );
      await _client.storageWriteChunked(path, utf8.encode(contents));
      _savedTo = path;
      // Held so the delete that may follow goes to the Flipper this file was
      // written to. The two are separate tasks with a confirm dialog between
      // them, and `runTask` binds whatever session is current when it is
      // called - which, with auto-reconnect on or a cable swapped meanwhile,
      // need not be this one.
      _savedBinding = _client.bindCurrentSession();
    } catch (e) {
      // Otherwise the user presses Save, nothing at all happens, the button is
      // still there, and the remote is not on their Flipper - with no way to
      // tell whether the app refused, the link dropped or the card is full.
      LogService.error('[Seed] could not write $path: $e');
      _error = SeedFailure.saveFailed;
    } finally {
      _saving = false;
      _changed();
    }
  }

  /// The failure to report when [path] is not free, or null when it is.
  ///
  /// A free path is the firmware *refusing* the stat rather than answering an
  /// empty one, so the ordinary case arrives as an exception and is not worth a
  /// log line. Any other failure is a different answer again - not "free", but
  /// "nobody asked" - and it gets its own member, because the page has to say
  /// something different about it than it would about a file it has seen.
  Future<SeedFailure?> _occupant(String path) async {
    try {
      await _client.storageStat(
        StatRequest(path: path),
        timeout: const Duration(seconds: 10),
      );
      return SeedFailure.nameTaken;
    } on FlipperRpcStorageNotExistException {
      return null;
    } catch (e) {
      LogService.warn('[Seed] could not stat $path: $e');
      return SeedFailure.nameUnchecked;
    }
  }

  /// Deletes the capture the recovery came from.
  ///
  /// Offered after a save because the capture has then done its job - it is a
  /// fix and a list of hops, worth keeping only until the remote it describes
  /// exists as a `.sub`. The Flipper-side app does not clean up after itself,
  /// so the folder otherwise fills with files whose remotes are already saved.
  ///
  /// Refuses while [canDeleteCapture] is false rather than trusting the caller,
  /// for the same reason [save] re-checks its name: this one deletes the only
  /// copy of something the user may not be able to capture again.
  /// Runs under the session the remote was saved over rather than
  /// [_task]'s "whichever is current", for the reason recorded in [_save].
  Future<void> deleteCapture() {
    _error = null;
    final binding = _savedBinding;
    if (binding == null) return Future.value();
    return binding.run(_deleteCapture);
  }

  Future<void> _deleteCapture() async {
    final file = _openedFile;
    if (!canDeleteCapture || file == null) return;
    if (!(_savedBinding?.isAlive ?? false)) {
      // The link that carried the save is gone, so this delete would land on
      // whatever is connected now - a device whose copy of the remote was
      // never written.
      LogService.error(
        '[Seed] not deleting ${file.path}: the link it was saved over is gone',
      );
      _error = SeedFailure.deleteFailed;
      _changed();
      return;
    }

    try {
      await _client.storageDelete(DeleteRequest(path: file.path));
    } catch (e) {
      // The remote is already saved, so this is not a lost recovery - but
      // silence would leave the capture in the list looking undeleted with
      // nothing saying why. `_openedFile` is left alone so the offer can be
      // taken again.
      LogService.error('[Seed] could not delete ${file.path}: $e');
      _error = SeedFailure.deleteFailed;
      _changed();
      return;
    }
    // Dropped from the list here rather than by re-listing the folder: the
    // answer is already known, and a second round trip is the slowest call
    // this page makes over BLE.
    _openedFile = null;
    _files = List.unmodifiable(_files.where((f) => f.path != file.path));
    _changed();
  }
}
