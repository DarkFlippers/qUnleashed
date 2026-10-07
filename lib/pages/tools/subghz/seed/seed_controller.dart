import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../../services/logging.dart';
import '../../mifare/mifare_native.dart';
import 'faaccrack_recoverer.dart';
import 'seed_capture_format.dart';
import 'seed_models.dart';
import 'seed_sub_file.dart';

/// What the page is doing.
enum SeedStage { idle, loading, searching }

/// Why something the user asked for did not happen.
///
/// An enum rather than an exception string, so the page can say it in the
/// user's language and so the set is exhaustive - what ADR 0008 asks for where
/// a failure needs differentiated UI. Each member is a different thing to do
/// next, which is the test for whether it earns one.
enum SeedFailure { disconnected, unreadableCapture, readFailed, saveFailed }

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
    _stage = SeedStage.idle;
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
    } catch (e) {
      // A device that has never run the capture app has no such folder, which
      // is "nothing captured yet". A dropped link is not, and saying so would
      // send a user to re-record a remote they already captured - so the two
      // are told apart by asking whether the link is still up, rather than by
      // reading an error string the firmware does not promise.
      LogService.warn('[Seed] could not list $seedCaptureDir: $e');
      _files = const [];
      if (!_client.isConnected) _error = SeedFailure.disconnected;
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

  /// Writes the recovered remote to the Flipper as a transmittable `.sub`.
  ///
  /// Into `/ext/subghz`, so it appears under Sub-GHz -> Saved: a seed shown on
  /// screen and nowhere else leaves the user to do the file work by hand.
  Future<void> save() => _task(_save);

  Future<void> _save() async {
    final capture = _capture;
    final result = _result;
    if (!canSave || capture == null || result == null) return;

    final name = SeedSubFile.fileName(
      manufacturer: capture.manufacturer,
      fix: capture.fix,
    );
    final path = '$seedSubGhzDir/$name';
    final contents = SeedSubFile.render(
      result: result,
      manufacturer: capture.manufacturer,
      fix: capture.fix,
      frequencyHz: capture.frequencyHz!,
      preset: capture.preset,
    );

    try {
      await _client.storageWriteChunked(path, utf8.encode(contents));
      _savedTo = path;
    } catch (e) {
      // Otherwise the user presses Save, nothing at all happens, the button is
      // still there, and the remote is not on their Flipper - with no way to
      // tell whether the app refused, the link dropped or the card is full.
      LogService.error('[Seed] could not write $path: $e');
      _error = SeedFailure.saveFailed;
    }
    _changed();
  }
}
