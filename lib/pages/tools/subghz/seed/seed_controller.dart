import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../../services/logging.dart';
import 'faaccrack_recoverer.dart';
import 'seed_capture_format.dart';
import 'seed_models.dart';
import 'seed_sub_file.dart';

/// What the page is doing.
enum SeedStage { browsing, loading, searching, done }

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

  SeedStage _stage = SeedStage.browsing;
  List<SeedCaptureFile> _files = const [];
  SeedCapture? _capture;
  SeedResult? _result;
  double _progress = 0;
  bool _stopping = false;
  String? _error;
  String? _savedTo;
  List<String> _captureWarnings = const [];

  SeedStage get stage => _stage;
  List<SeedCaptureFile> get files => _files;
  SeedCapture? get capture => _capture;
  SeedResult? get result => _result;
  double get progress => _progress;
  bool get cancelled => _stopping;
  String? get error => _error;

  /// Where the recovered remote was written, once it has been.
  String? get savedTo => _savedTo;

  /// Lines the capture file had that could not be read. Shown rather than
  /// logged alone: a file half of whose hops were dropped may no longer have
  /// consecutive ones, and the search would then find nothing for a reason that
  /// is not about the remote.
  List<String> get captureWarnings => _captureWarnings;

  /// Whether the recovered remote can be written as a transmittable file.
  ///
  /// Three things have to hold, and the frequency is the one that is easy to
  /// forget: it is not recoverable from a fix and a hop, so a capture without
  /// it can be solved but not written.
  bool get canSave =>
      _result?.outcome == SeedOutcome.found &&
      _result?.frameHop != null &&
      _capture?.frequencyHz != null;

  /// Lists the captures the device is holding.
  Future<void> refresh() async {
    _stage = SeedStage.browsing;
    _error = null;
    notifyListeners();
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
      // is "nothing captured yet" rather than a failure - but it arrives as the
      // same error as a broken link, and the two cannot be told apart here. The
      // page says the neutral thing and the log keeps the detail.
      LogService.warn('[Seed] could not list $seedCaptureDir: $e');
      _files = const [];
    }
    notifyListeners();
  }

  /// Reads one capture and parses it.
  Future<void> open(SeedCaptureFile file) async {
    _stage = SeedStage.loading;
    _error = null;
    _result = null;
    _savedTo = null;
    _capture = null;
    _captureWarnings = const [];
    notifyListeners();

    try {
      final bytes = await _client.storageReadChunked(
        file.path,
        expectedSize: file.size,
        timeout: const Duration(minutes: 2),
      );
      final parsed = SeedCaptureFormat.parse(
        const Utf8Decoder(allowMalformed: true).convert(bytes),
        path: file.path,
      );
      _captureWarnings = List.unmodifiable(parsed.skipped);
      _capture = parsed.capture;
      if (parsed.capture == null) {
        _error = parsed.skipped.isEmpty ? 'unreadable' : parsed.skipped.first;
      }
    } catch (e) {
      LogService.error('[Seed] could not read ${file.path}: $e');
      _error = '$e';
    }
    _stage = _capture == null ? SeedStage.browsing : SeedStage.done;
    notifyListeners();
  }

  /// Runs the search over the loaded capture.
  ///
  /// Tries the whole capture first, then contiguous subsets. One missed press
  /// makes a capture unsolvable *entire* - the acceptance test needs every
  /// decrypted counter to be one from the last - while the presses either side
  /// of the gap are still consecutive among themselves. Without this a user
  /// with a nine-hop capture and one dropped frame is told no seed exists.
  Future<void> search() async {
    final capture = _capture;
    if (capture == null) return;

    _stage = SeedStage.searching;
    _stopping = false;
    _progress = 0;
    _result = null;
    _savedTo = null;
    _error = null;
    notifyListeners();

    LogService.warn(
      '[Seed] searching ${capture.manufacturer.label} '
      '${capture.fix.toRadixString(16)} with ${capture.hops.length} hop(s) '
      'on ${NativeFaaccrackRecoverer.variantName()}',
    );

    SeedResult? last;
    for (final window in _windows(capture.hops)) {
      if (_stopping) break;
      final attempt = await _recoverer.recover(
        manufacturer: capture.manufacturer,
        fix: capture.fix,
        hops: window,
        onProgress: (fraction) {
          _progress = fraction;
          notifyListeners();
        },
        isCancelled: () => _stopping,
      );
      last = attempt;
      // Only "nothing matched" is worth narrowing the window for. Everything
      // else is either an answer or a fault, and retrying a fault would just
      // repeat it once per subset.
      if (attempt.outcome != SeedOutcome.nothingMatched) break;
    }

    _result = last;
    _stage = SeedStage.done;
    notifyListeners();
  }

  /// The hop sets to try, longest first.
  ///
  /// The whole capture, then every contiguous run one shorter, and so on down
  /// to the fewest the engine accepts. Longest first because more hops mean a
  /// stronger answer, and contiguous because non-adjacent hops cannot have
  /// consecutive counters however many of them there are.
  @visibleForTesting
  static List<List<int>> windowsFor(List<int> hops) => _windows(hops);

  static List<List<int>> _windows(List<int> hops) {
    final windows = <List<int>>[];
    for (var length = hops.length; length >= SeedCapture.minHops; length--) {
      for (var start = 0; start + length <= hops.length; start++) {
        windows.add(hops.sublist(start, start + length));
      }
      // One full pass of a shorter length is already several searches; going
      // all the way down to pairs on a long capture would be dozens. The
      // engine sweeps the whole space each time, so this is bounded work the
      // user is waiting through.
      if (windows.length >= _maxWindows) break;
    }
    return windows;
  }

  /// Enough to drop a press or two from a typical capture without turning a
  /// failed search into a very long one.
  static const _maxWindows = 8;

  /// Asks the running search to stop. It lands within a claimed chunk, which is
  /// milliseconds - not the "pressed Stop and the bar kept going" the MIFARE
  /// engine had before #259.
  void stop() {
    _stopping = true;
    notifyListeners();
  }

  /// Writes the recovered remote to the Flipper as a transmittable `.sub`.
  ///
  /// Into `/ext/subghz`, so it appears under Sub-GHz -> Saved: a seed shown on
  /// screen and nowhere else leaves the user to do the file work by hand.
  Future<void> save() async {
    final capture = _capture;
    final result = _result;
    if (!canSave || capture == null || result == null) return;

    final name = SeedSubFile.fileName(
      manufacturer: capture.manufacturer,
      fix: capture.fix,
    );
    final path = '$seedSubGhzDir/$name';
    final contents = SeedSubFile.render(
      manufacturer: capture.manufacturer,
      fix: capture.fix,
      frameHop: result.frameHop!,
      seed: result.seed!,
      frequencyHz: capture.frequencyHz!,
    );

    try {
      await _client.storageWriteChunked(path, utf8.encode(contents));
      _savedTo = path;
    } catch (e) {
      LogService.error('[Seed] could not write $path: $e');
      _error = '$e';
    }
    notifyListeners();
  }
}
