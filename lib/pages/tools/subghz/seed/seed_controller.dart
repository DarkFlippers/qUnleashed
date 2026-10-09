import 'dart:async';
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

  /// The rows on screen were listed over a link that has since gone, so none of
  /// their paths can be acted on. Its own member because the thing to do next
  /// is to re-list, not to retry - which is what every other member asks for.
  listingStale,
}

/// What a stat said about one path.
///
/// Three states and not a bool, because the two callers want different things
/// from the third. A save treats "nobody answered" as its own outcome and asks
/// the user before overwriting on no information. A delete branches on
/// [present] alone - that is the one that keeps the row - and treats [unknown]
/// as good enough to drop it, saying so in the log and to the user rather than
/// reporting a failure a successful delete would not have earned.
///
/// The firmware reports absence by refusing the stat, so classifying it is the
/// boundary ADR 0008 describes. `flipperlib` has no `storageExists` to do it
/// once, which is why this lives here for now; #268 is the ticket, and
/// `_pathState` and this enum are what it retires.
enum _PathState { present, absent, unknown }

/// A capture file the device is holding, before it is read.
typedef SeedCaptureFile = ({String path, String name, int size});

/// Drives one seed recovery: list the captures, read one, search, write the
/// recovered remote back.
///
/// `ChangeNotifier` and `setState`, like the rest of the app (ADR 0001), with
/// the client passed in rather than reached for (ADR 0002).
class SeedController extends ChangeNotifier {
  SeedController({required this._client, FaaccrackRecoverer? recoverer})
    : _recoverer = recoverer ?? NativeFaaccrackRecoverer() {
    // [canDeleteCaptures] reads the liveness of a session binding, which
    // changes outside this notifier - so without this the delete icons stayed
    // enabled after the link dropped, and stayed dead after a reconnect, until
    // some unrelated rebuild. The two other controllers that hold a binding
    // across user actions both close this loop the same way.
    //
    // The stream is broadcast and an error on it does not end it (CLAUDE.md),
    // so onError notifies rather than tearing the subscription down: a link
    // that failed is exactly when the enabled state has changed.
    _link = _client.connectionStream.listen(
      (_) => _changed(),
      onError: (_) => _changed(),
    );
  }

  /// The Flipper this run belongs to. Passed in rather than reached for, and
  /// required rather than defaulted, so a recovery cannot silently run against
  /// a different device from the one the page was opened on (ADR 0002).
  final FlipperClient _client;
  final FaaccrackRecoverer _recoverer;

  SeedStage _stage = SeedStage.idle;
  SeedCapture? _capture;
  SeedResult? _result;
  double _progress = 0;
  bool _stopping = false;
  SeedFailure? _error;
  String? _savedTo;
  List<String> _captureWarnings = const [];
  bool _saving = false;
  SeedCaptureFile? _openedFile;

  /// The rows, and the link that named them, as one value.
  ///
  /// Together rather than in two fields because the whole point is that they
  /// agree: a path is only meaningful against the device that listed it. Two
  /// assignments could drift apart on either of [_refresh]'s failure branches.
  ({List<SeedCaptureFile> files, FlipperSessionBinding binding})? _listing;

  /// The path a delete is in flight for, so a second tap cannot send a second
  /// one.
  ///
  /// `savedTo` learned this lesson for the write; the delete is the half of
  /// this page that cannot be undone, and it is now two round trips rather than
  /// one, so the window is wider.
  String? _deleting;

  /// Whether the last delete removed a row without being able to confirm it.
  ///
  /// Not a [SeedFailure]: nothing failed, and reporting one would tell the user
  /// a delete that probably worked had not. But the row vanishing is the same
  /// thing they see for a verified delete, so without this the app would be
  /// keeping to itself that it acted on an ACK alone.
  bool _unconfirmed = false;
  StreamSubscription<dynamic>? _link;
  bool _disposed = false;

  @override
  void dispose() {
    // Every one of the three device operations outlives the page if the user
    // leaves mid-flight - a search most of all, since a stop takes a moment to
    // land. Without this, the notifyListeners() that follows throws inside a
    // future nobody is listening to.
    _disposed = true;
    _link?.cancel();
    super.dispose();
  }

  /// Notifies, unless the page has already gone.
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  SeedStage get stage => _stage;
  List<SeedCaptureFile> get files => _listing?.files ?? const [];
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

  /// Whether a listed capture can be deleted at all.
  ///
  /// Not a judgement about any one file - that question belongs to the confirm
  /// dialog, which is where the user can read the name. This is only whether
  /// the rows on screen were listed over a link that is still there.
  ///
  /// A delete under a dead binding would *fail* rather than reach another
  /// Flipper - flipperlib promises that much - so this is not what stops the
  /// wrong device being written to. It is what turns an exception naming
  /// nothing the user can act on into a refusal that names the remedy, which
  /// is to re-list rather than to retry.
  bool get canDeleteCaptures => _listing?.binding.isAlive ?? false;

  /// Whether the last delete dropped its row without confirmation.
  bool get deleteUnconfirmed => _unconfirmed;

  /// Whether a delete is in flight for [file].
  bool deleting(SeedCaptureFile file) => _deleting == file.path;

  /// Whether the engine is sweeping. The page gates everything that touches the
  /// device on it, so it is one name rather than three spellings of a compare.
  bool get searching => _stage == SeedStage.searching;

  /// Whether anything is in flight that a row action must not interleave with.
  ///
  /// A read carries a two-minute timeout and a listing twenty seconds, so
  /// "not searching" was never the whole question: deleting the row that is
  /// being read ends with the read reporting a failure for a file the list has
  /// already dropped.
  bool get busy => _stage != SeedStage.idle || _saving || _deleting != null;

  /// Lines the capture file had that could not be read. Shown rather than
  /// logged alone: a file half of whose hops were dropped can be left with a
  /// gap wider than [SeedCapture.maxCounterGap], and the search would then find
  /// nothing for a reason that is not about the remote.
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
      // The rows and the link together. A request made under a dead binding
      // fails rather than retargeting whatever is connected now - flipperlib
      // promises that - so holding the binding is what turns "these paths
      // belong to a Flipper that has gone" into a refusal this page can report
      // instead of an exception from a delete that was already sent.
      _listing = (
        files: List.unmodifiable(found),
        binding: _client.bindCurrentSession(),
      );
    } on FlipperRpcStorageNotExistException {
      // A device that has never run the capture app has no such folder. The
      // one failure that really is "nothing captured yet", and the firmware
      // says so by name rather than by an error string.
      _listing = (files: const [], binding: _client.bindCurrentSession());
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
  /// The engine tolerates a counter step up to [SeedCapture.maxCounterGap], so
  /// the ordinary missed press now solves on the first sweep and this ladder is
  /// the fallback rather than the mechanism. What still needs it is one shape: a
  /// gap wider than that, from a remote worked for a while out of range or a
  /// capture whose unreadable lines were dropped.
  ///
  /// It does not cover a capture whose counters do not run in one direction -
  /// the same frame twice, or a 16-bit counter that wrapped. A sub-run is not
  /// guaranteed to exclude the break, and nothing here can see where it is.
  ///
  /// Three windows, and that is worth spelling out because the first version of
  /// this ladder offered twelve. A window solves exactly when its own hops are
  /// within the tolerance, and a contiguous sub-run of such a run is too - so a
  /// *short* window inside a solvable run always solves if a longer one does.
  /// Meanwhile a sweep costs the same whatever the hop count: the engine scans
  /// the whole seed space either way, and extra hops only filter the candidates
  /// it finds. Length therefore buys confidence, not reach.
  ///
  /// So: the whole capture, for the strongest `hops_used` in one sweep; then
  /// the last [seedHopsConfident] hops, then the first. A single over-wide gap
  /// at position k leaves the suffix solvable when k is at or below n-3 and the
  /// prefix when k is at least 3, and for any capture of five or more those two
  /// ranges meet.
  ///
  /// Nothing shorter than [seedHopsConfident] is synthesised, and the whole
  /// capture is the one exception - that is the user's own data and the engine's
  /// documented minimum, so it is searched whatever its length. What this
  /// declines to do is *invent* a sub-confident window: it would cost two more
  /// whole-space sweeps, seventeen seconds each on a current phone, to reach an
  /// answer [canSave] refuses as unconfirmed - at the hop count where the
  /// engine's own false-positive estimate is worst. The shape it used to reach
  /// and nothing else does is an over-wide gap inside a three- or four-hop
  /// capture. #288
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

    // The freshest confident window, then the oldest. On a capture short enough
    // that the two cannot meet in the middle these leave an over-wide gap
    // uncovered, which is the exchange the doc comment above describes.
    if (seedHopsConfident < longest) {
      offer(hops.sublist(hops.length - seedHopsConfident));
      offer(hops.sublist(0, seedHopsConfident));
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
      // Its own failure rather than a write that fails, so the user is told
      // which rule and can act on it. For the non-ASCII arm the Flipper would
      // have refused the name too - the point is that it answers only
      // `ERROR_STORAGE_INVALID_NAME`, which names no character. The rule goes
      // in the log as well as the name: for a 63-character or non-ASCII name
      // it is not deducible from the name alone.
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
        final standing = switch (await _pathState(path)) {
          _PathState.present => SeedFailure.nameTaken,
          _PathState.absent => null,
          // Not "free". The page says something different about a name nobody
          // answered for than about one it has seen taken, because the user has
          // to decide whether to overwrite on no information.
          _PathState.unknown => SeedFailure.nameUnchecked,
        };
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

  /// Whether the device holds [path].
  ///
  /// Absence is the firmware *refusing* the stat rather than answering an empty
  /// one, so the ordinary case arrives as an exception and is not worth a log
  /// line. Anything else is a third answer rather than a second: not "absent",
  /// but "nobody said". Before the check existed at all a save clobbered
  /// silently (#264); folding "nobody said" into "absent" would bring half of
  /// that back, because the user would never be asked.
  Future<_PathState> _pathState(String path) async {
    try {
      await _client.storageStat(
        StatRequest(path: path),
        timeout: const Duration(seconds: 10),
      );
      return _PathState.present;
    } on FlipperRpcStorageNotExistException {
      return _PathState.absent;
    } catch (e) {
      LogService.warn('[Seed] could not stat $path: $e');
      return _PathState.unknown;
    }
  }

  /// Deletes [file] from the capture folder.
  ///
  /// Takes the file rather than reading [openedFile], so any row in the list
  /// can be tidied away. Keying it on this session's save left a capture that
  /// cannot be solved at all - unreadable, nothing matched, too few hops, no
  /// frequency to write back - with no way to be removed here, and that is the
  /// set the Flipper-side app fills the folder with.
  ///
  /// Runs under the session that produced the listing rather than [_task]'s
  /// "whichever is current", for the reason recorded in [_refresh].
  Future<void> deleteCapture(SeedCaptureFile file) {
    _error = null;
    _unconfirmed = false;
    final listing = _listing;
    if (listing == null) {
      // Defensive rather than a branch: [_listing] is null only before any
      // listing has completed, and then there are no rows to delete from. It
      // says so rather than returning silently, because a future caller that
      // reaches it would otherwise get nothing at all.
      LogService.error('[Seed] not deleting ${file.path}: nothing is listed');
      _error = SeedFailure.deleteFailed;
      _changed();
      return Future.value();
    }
    return listing.binding.run(() => _deleteCapture(file));
  }

  Future<void> _deleteCapture(SeedCaptureFile file) async {
    if (!files.any((f) => f.path == file.path)) {
      // The app refused this, not the device - the list no longer names the
      // path, which is a different thing from a delete that failed, and the log
      // is the only place that can tell them apart.
      LogService.warn('[Seed] not deleting ${file.path}: no row names it');
      _error = SeedFailure.deleteFailed;
      _changed();
      return;
    }
    if (_deleting != null) {
      // A second tap while the first is still in flight. Both would pass the
      // check above, because the row is only dropped at the end.
      LogService.warn('[Seed] already deleting $_deleting');
      return;
    }
    if (!canDeleteCaptures) {
      // The link these paths were listed over has gone. The delete would fail
      // rather than reach another device, but it would fail as an exception
      // naming nothing the user can act on; this names it, and the cure is to
      // re-list rather than to retry.
      LogService.error(
        '[Seed] not deleting ${file.path}: the link it was listed over is gone',
      );
      _error = SeedFailure.listingStale;
      _changed();
      return;
    }

    _deleting = file.path;
    _changed();

    SeedFailure? sendFailure;
    var certainlyGone = false;
    try {
      await _client.storageDelete(DeleteRequest(path: file.path));
    } on FlipperRpcStorageNotExistException {
      // Already gone. The firmware refuses a delete of a path it does not
      // hold, and `_refresh`'s catch deliberately leaves rows standing, so a
      // row routinely outlives the file it names - someone deleting the
      // capture from the Flipper's own browser is enough. Reporting a failure
      // here told the user their capture had survived when the one certain
      // fact was that it had not.
      LogService.warn('[Seed] ${file.path} was already gone');
      certainlyGone = true;
    } catch (e) {
      // Not decided yet. A timeout or a dropped link may have carried the
      // delete and lost only the ACK, so the stat below settles it rather than
      // this catch asserting a device state it does not know.
      LogService.error('[Seed] could not delete ${file.path}: $e');
      sendFailure = _failureForUnreachable();
    }

    // One question, asked once, whatever the send said: an ACK is not the file
    // being gone, and a failure is not the file being there. A stat of this
    // path rather than a re-listing of the folder - the question is about this
    // file, and this half of the page cannot be undone.
    if (!certainlyGone) {
      switch (await _pathState(file.path)) {
        case _PathState.absent:
          // Gone, whatever the send reported. A delete whose ACK was lost is
          // still a delete, and saying it failed would send the user looking
          // for a capture that is not there.
          break;
        case _PathState.present:
          LogService.error(
            '[Seed] ${file.path} survived a delete the device accepted',
          );
          _error = sendFailure ?? SeedFailure.deleteFailed;
          _deleting = null;
          _changed();
          return;
        case _PathState.unknown:
          if (sendFailure != null) {
            // Nothing landed and nothing could be checked. The row stays.
            _error = sendFailure;
            _deleting = null;
            _changed();
            return;
          }
          // The ACK came back and the device then stopped answering. The row
          // goes on the strength of the ACK - but the user is told it could
          // not be confirmed, rather than being shown the clean removal a
          // verified delete gets.
          LogService.warn(
            '[Seed] deleted ${file.path} but could not confirm it is gone',
          );
          _unconfirmed = true;
      }
    }

    if (_openedFile?.path == file.path) _openedFile = null;
    _deleting = null;
    _listing = (
      files: List.unmodifiable(files.where((f) => f.path != file.path)),
      binding: _listing!.binding,
    );
    _changed();
  }

  /// Which failure a dead or absent link earns.
  ///
  /// `_refresh` makes the same distinction, and for the same reason: "not
  /// connected" has a different thing to do next from "the device refused".
  SeedFailure _failureForUnreachable() =>
      _client.isConnected ? SeedFailure.deleteFailed : SeedFailure.disconnected;
}
