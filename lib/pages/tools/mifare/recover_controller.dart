import '../../../services/localization/l10n.dart';

import 'dart:collection';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/logging.dart';
import '../../../services/progress_throttle.dart';
import 'cuid_dict_format.dart';
import 'existed_keys_storage.dart';
import 'hardnested_recoverer.dart';
import 'known_key_filter.dart';
import 'key_nonce_parser.dart';
import 'mfkey32_api.dart';
import 'mfkey32_models.dart';
import 'mfkey32_recoverer.dart';
import 'mifare_native.dart';
import 'nested_api.dart';
import 'nested_models.dart';
import 'nested_nonce_parser.dart';
import 'nested_recoverer.dart';
import 'recover_models.dart';
import 'recover_routing.dart';
import 'static_encrypted_recoverer.dart';

/// Unified "Recover MIFARE Keys" flow: pulls whichever of `.mfkey32.log`
/// (reader) and `.nested.log` (tag) exist, auto-routes each entry to the right
/// attack (mfkey32 / nested — weak or static nonce / static-encrypted /
/// hardnested), and syncs every resolved key into the user dictionary.
/// Static-encrypted nonces can't be resolved to one key offline, so they
/// instead produce a per-card candidate dictionary for on-device verification.
class RecoverController extends ChangeNotifier {
  RecoverController({
    required this._client,
    MfKey32Api? mfApi,
    NestedApi? nestedApi,
    MfKey32Recoverer? mfRecoverer,
    NestedRecoverer? nestedRecoverer,
    StaticEncryptedRecoverer? staticRecoverer,
    HardnestedRecoverer? hardnestedRecoverer,
    KnownKeyFilter Function(Iterable<String> keys)? knownKeyFilter,
  }) : _knownKeyFilter = knownKeyFilter ?? nativeKnownKeyFilter,
       _mfApi = mfApi ?? MfKey32ApiImpl(),
       _nestedApi = nestedApi ?? NestedApiImpl(),
       _mfRecoverer = mfRecoverer ?? NativeMfKey32Recoverer(),
       _nestedRecoverer = nestedRecoverer ?? NativeNestedRecoverer(),
       _staticRecoverer = staticRecoverer ?? NativeStaticEncryptedRecoverer(),
       _hardnestedRecoverer =
           hardnestedRecoverer ?? NativeHardnestedRecoverer() {
    _state = const RecoverError(RecoverErrorType.flipperConnection);
    _storage = ExistedKeysStorage(_client);
  }

  final FlipperClient _client;
  final MfKey32Api _mfApi;
  final NestedApi _nestedApi;
  final MfKey32Recoverer _mfRecoverer;
  final NestedRecoverer _nestedRecoverer;
  final StaticEncryptedRecoverer _staticRecoverer;
  final HardnestedRecoverer _hardnestedRecoverer;
  final KnownKeyFilter Function(Iterable<String> keys) _knownKeyFilter;
  late final ExistedKeysStorage _storage;

  late RecoverState _state;
  bool _running = false;
  // Set from dispose(): the page can be popped while _run() is still in
  // flight. Once true we neither notify the disposed ChangeNotifier nor start
  // any further recovery or device write.
  bool _disposed = false;
  // Set from stop(): the user asked the run to end but the page is still here.
  //
  // Deliberately not the same flag as _disposed, which is the whole point of
  // this one. Backing out of the page has to abandon the keys - the dictionary
  // write is a read-modify-write over a client the page no longer owns - while
  // Stop must keep them, which is the only reason to offer it.
  //
  // The two part company in the one place that decides whether the run's work
  // survives, the _saveKeys() at the end of _run(), and in the reporting path:
  // _emit and _tick check only _disposed, because a cancelled run still has a
  // page to report what it managed to. See _stopping.
  bool _cancelled = false;
  final List<RecoverEntry> _entries = [];
  // Set true once a per-card static-encrypted candidate dictionary is actually
  // written, so the summary can distinguish "candidates saved" from "nothing".
  bool _wroteCandidates = false;
  // Set true when a step fails (an engine was unavailable, or candidates could
  // not be generated/written) though the run still completes - the summary then
  // shows a partial-failure headline instead of a clean success.
  bool _hadFailure = false;

  int _totalUnits = 0;
  int _doneUnits = 0;
  // Rebuilt per run from the dictionaries this run loaded, and released when
  // the next run replaces it or the page goes: it holds native memory, which
  // outlives the isolate that took it.
  KnownKeyFilter _known = const NoKnownKeys();
  int _skippedKnown = 0;

  RecoverState get state => _state;
  bool get running => _running;

  /// True from [stop] until the *next* run clears it.
  ///
  /// Outlives the run it stopped, deliberately - nothing needs it cleared on
  /// the way out, and clearing it there would race the unwind. The page only
  /// consults it while [canStop], so the stale-true window is never shown.
  ///
  /// The page reads it to stop offering Stop a second time: an attack notices
  /// the request at its next bounded check, which on a hardnested bucket is not
  /// immediate, and a button that stays live through that reads as one that did
  /// nothing.
  bool get cancelled => _cancelled;

  /// Whether there is anything left for [stop] to stop.
  ///
  /// Narrower than [running] on purpose. `_running` stays true through the
  /// dictionary write at the end of a run, and [retrySave] sets it for an
  /// operation that is *nothing but* that write - and the write deliberately
  /// does not consult [_stopping], because Stop has to keep the keys. So a
  /// button gated on `running` alone would appear over the save and do nothing
  /// when pressed, which is the exact failure offering Stop is meant to avoid.
  bool get canStop => _running && !_saving;
  // Set around the dictionary write, which is the one part of a run that Stop
  // must not interrupt and cannot usefully be offered during.
  bool _saving = false;

  /// Asks the run to stop at the next step, keeping every key it has found.
  ///
  /// Honoured per step, not instantly, and the step differs by attack: the
  /// hardnested attack polls [_stopping] through its `isCancelled` callback and
  /// returns [HardnestedOutcome.stopped]; the reader loop checks once per nonce;
  /// the weak loop once per batch of four.
  ///
  /// The one thing it does interrupt mid-step is the static-encrypted candidate
  /// upload, which is cancelled in flight - that card's half-written dictionary
  /// is removed from the device and the card gets a row saying so. No *key* is
  /// ever lost to it: a candidate dictionary is regenerated from the same log on
  /// the next run, and _run() still reaches its own dictionary write.
  void stop() {
    if (!_running || _disposed || _cancelled) return;
    _cancelled = true;
    notifyListeners();
  }

  /// Whether the run should wind up: the user asked, or the page is gone.
  ///
  /// The check every unit boundary makes. [_emit] and [_tick] deliberately do
  /// not use it - a cancelled run still has a page to report to, and reporting
  /// what it managed is the point.
  bool get _stopping => _disposed || _cancelled;

  /// Every recovery result gathered this run, in completion order.
  List<RecoverEntry> get entries => UnmodifiableListView(_entries);

  /// Total recovery units this run (reader keys + weak/static pairs + hardnested
  /// groups + one for the static-encrypted batch). Drives the "N of M" readout.
  int get totalUnits => _totalUnits;

  /// True when a failed dictionary save left the previous keys in a copy on the
  /// device. Only meaningful alongside [RecoverErrorType.saveFailed].
  bool get dictBackupKept => _storage.backupKept;

  /// True when the dictionary was overwritten with no copy behind it, because
  /// the copy itself failed. Only meaningful alongside
  /// [RecoverErrorType.saveFailed].
  bool get dictBackupFailed => _storage.backupFailed;

  /// Units finished so far. Most units run to completion with no sub-progress,
  /// so the UI pairs this count with an animated bar rather than a percentage
  /// that would freeze between them. Two report more: a hardnested unit carries
  /// a brute-force fraction on [RecoverCalculating], and the static-encrypted
  /// device write reports through [RecoverUploading]. Both are long enough that
  /// an unmoving readout reads as a hang.
  int get doneUnits => _doneUnits;

  @override
  void dispose() {
    _disposed = true;
    _known.dispose();
    super.dispose();
  }

  /// Runs a whole recovery as one task.
  ///
  /// It reads the nonce and dictionary files off the card's Flipper, works for
  /// as long as cracking takes and writes the candidate keys back. All of that
  /// is about one device, so it stays with the one it began on: keys recovered
  /// from a card read by one Flipper have no meaning written into another's
  /// dictionary.
  Future<void> start() =>
      _client.runTask(FlipperRequestPriority.background, _start);

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    try {
      await _run();
    } catch (e, st) {
      LogService.error('[Recover] Unexpected failure: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.recoveryFailed));
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _run() async {
    _entries.clear();
    _wroteCandidates = false;
    _hadFailure = false;
    // Cleared here, not in stop(): a Stop from the previous run must not end
    // this one before it starts.
    _cancelled = false;
    _totalUnits = 0;
    _doneUnits = 0;
    _skippedKnown = 0;

    if (!_client.isConnected) {
      _emit(const RecoverError(RecoverErrorType.flipperConnection));
      return;
    }

    _emit(const RecoverWaitingForDevice());

    final bool hasReaderLog;
    final bool hasTagLog;
    try {
      await _mfApi.checkBruteforceFileExist(_client);
      hasReaderLog = _mfApi.isBruteforceFileExist;
      hasTagLog = await _nestedApi.nonceFileExists(_client);
    } catch (e, st) {
      // A device RPC failure here (disconnect, BLE drop) is a connection
      // problem - not the catch-all "recovery unavailable" error below.
      LogService.error('[Recover] file-existence probe failed: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.flipperConnection));
      return;
    }
    if (!hasReaderLog && !hasTagLog) {
      _emit(const RecoverError(RecoverErrorType.notFoundFile));
      return;
    }

    _emit(const RecoverDownloading());
    final readerSize = hasReaderLog ? await _fileSize(pathNonceLog) : 0;
    final tagSize = hasTagLog ? await _fileSize(pathNestedLog) : 0;
    final totalBytes =
        (hasReaderLog && readerSize == 0) || (hasTagLog && tagSize == 0)
        ? 0
        : readerSize + tagSize;
    final throttle = ProgressThrottle();
    var doneBytes = 0;
    void report(int fileBytes) {
      if (totalBytes == 0) return;
      final progress = ((doneBytes + fileBytes) / totalBytes).clamp(0.0, 1.0);
      if (throttle.shouldEmit(progress)) _emit(RecoverDownloading(progress));
    }

    final String? readerText;
    final String? tagText;
    try {
      readerText = hasReaderLog
          ? await _download(
              pathNonceLog,
              expectedSize: readerSize,
              onProgress: (p) => report((p * readerSize).round()),
            )
          : null;
      doneBytes += readerSize;
      tagText = hasTagLog
          ? await _download(
              pathNestedLog,
              expectedSize: tagSize,
              onProgress: (p) => report((p * tagSize).round()),
            )
          : null;
    } catch (e, st) {
      // The files were confirmed to exist above, so a failure here is a real
      // read error - surface it instead of silently proceeding as if the log
      // were empty (which would drop every key it held under a success screen).
      LogService.error('[Recover] download failed: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.readWrite));
      return;
    }

    try {
      await _storage.load();
    } catch (e, st) {
      LogService.error('[Recover] load keys failed: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.readWrite));
      return;
    }

    // dispose() has already run if the page went while the dictionaries were
    // loading, and it will not run again - so a filter built now would hold its
    // native buffer until the process ends.
    if (_disposed) return;
    _known.dispose();
    try {
      _known = _knownKeyFilter(_storage.knownKeys);
    } catch (e, st) {
      // A build without the engine still runs; it just does the work it could
      // have skipped. Degrading here must never cost a key.
      LogService.warn(
        '[Recover] known-key filter unavailable: ${LogService.describe(e, st)}',
      );
      _known = const NoKnownKeys();
    }

    // Plan the work up front so progress is meaningful across both logs.
    final readerNonces = readerText == null
        ? const <MfKey32Nonce>[]
        : dedupeReaderNonces(KeyNonceParser.parse(readerText));
    final tagLog = NestedNonceParser.parse(tagText ?? '');
    final tagNonces = tagLog.nonces;
    if (tagLog.droppedLines > 0) _reportDroppedNonces(tagLog);
    final weak = dedupeNestedNonces(tagNonces.where((n) => n.hasPair));
    final (allStaticSingles, hardGroups) = splitSingles(
      tagNonces.where((n) => !n.hasPair),
    );
    // Worth most here: a static-encrypted sector key whose key is already known
    // would otherwise cost tens of thousands of generated candidates and a
    // megabyte uploaded to the device, for a key the card already opens with.
    final split = splitKnownStatic(
      // Deduped first: without it a card read five times reports five identical
      // skipped rows and counts one sector key as five.
      dedupeNestedNonces(allStaticSingles),
      (n) => _known.nestedMatch(
        cuid: n.cuid,
        nt: n.samples[0].nt,
        ks: n.samples[0].ks,
      ),
    );
    final staticSingles = split.attack;
    split.known.forEach((n, key) {
      _skippedKnown++;
      _recordKey(
        source: RecoverSource.tag,
        kind: RecoverKind.staticEncrypted,
        cuid: n.cuid,
        sectorName: n.sectorName,
        keyName: n.keyName,
        key: key,
        counted: false,
      );
    });
    // One unit per card, not one for the whole batch. A 4K card is forty
    // sectors and a run can hold several cards; counting them as a single step
    // left the readout still for the longest stretch of the run.
    final staticCards = staticSingles.map((n) => n.cuid).toSet().length;
    _totalUnits =
        readerNonces.length + weak.length + hardGroups.length + staticCards;
    _emit(const RecoverCalculating());

    await _recoverReader(readerNonces);
    await _recoverWeak(weak);
    for (final group in hardGroups) {
      // break, not return: a stopped run still has to reach the write below,
      // which is the difference between Stop and backing out of the page.
      if (_stopping) break;
      await _recoverHardnested(group);
    }
    if (!_stopping && staticSingles.isNotEmpty) {
      await _recoverStatic(staticSingles, cards: staticCards);
    }
    // Backing out of the page is the one case that abandons the keys: the dict
    // write is a read-modify-write over a client this page no longer owns.
    // A Stop falls through to it, which is the whole point of having it.
    if (_disposed) return;

    await _saveKeys();
  }

  /// Writes the recovered keys to the device and reports the run.
  ///
  /// Its own method because it is the only part worth retrying alone: the keys
  /// are already in memory, so a failed write of a dictionary measured in
  /// kilobytes should not cost the hours of cracking that produced it.
  Future<void> _saveKeys() async {
    // Closes the Stop button for the duration: see [canStop].
    _saving = true;
    _emit(const RecoverUploading());
    final List<String> added;
    try {
      added = await _storage.upload();
    } catch (e, st) {
      LogService.error('[Recover] save keys failed: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.saveFailed));
      return;
    } finally {
      _saving = false;
    }

    _emit(
      RecoverSaved(
        keys: added,
        hasCandidates: _wroteCandidates,
        hasFailures: _hadFailure,
        skippedKnown: _skippedKnown,
        // Still set here: _cancelled is cleared by the next _run(), not on the
        // way out of this one, precisely so the summary can say so.
        stopped: _cancelled,
      ),
    );
  }

  /// Retries only the device write, keeping everything this run recovered.
  ///
  /// `_storage` still holds the keys - it is only ever added to - so this is
  /// the whole of what failed. Starting the run over would re-download both
  /// logs, re-read both dictionaries and re-run every attack, a hardnested one
  /// among them, to redo a write of a few kilobytes.
  Future<void> retrySave() =>
      _client.runTask(FlipperRequestPriority.background, () async {
        if (_running || _disposed) return;
        _running = true;
        try {
          await _saveKeys();
        } catch (e, st) {
          LogService.error('[Recover] save retry failed: $e\n$st');
          _emit(const RecoverError(RecoverErrorType.saveFailed));
        } finally {
          _running = false;
          if (!_disposed) notifyListeners();
        }
      });

  // ---- reader (mfkey32) ----

  Future<void> _recoverReader(List<MfKey32Nonce> nonces) async {
    for (final n in nonces) {
      if (_stopping) return;
      // Already in a dictionary: record it as known and skip the attack. The
      // row reads the same either way, so the only visible difference is that
      // the run gets there sooner.
      final known = _known.readerMatch(
        uid: n.uid,
        nt: n.nt0,
        nr: n.nr0,
        ar: n.ar0,
      );
      if (known != null) _skippedKnown++;
      final key = known ?? await _mfRecoverer.bruteforceKey(n);
      _recordKey(
        source: RecoverSource.reader,
        kind: RecoverKind.mfkey32,
        cuid: n.uid,
        sectorName: n.sectorName,
        keyName: n.keyName,
        key: key,
      );
    }
  }

  // ---- tag: two-sample nested (weak PRNG or static nonce) ----

  Future<void> _recoverWeak(List<NestedNonce> weak) async {
    // Recovery is memory-heavy (~50 MB per isolate); cap concurrency.
    const maxConcurrent = 4;
    for (var i = 0; i < weak.length; i += maxConcurrent) {
      if (_stopping) return;
      await Future.wait(
        weak.skip(i).take(maxConcurrent).map((n) async {
          final known = _known.nestedMatch(
            cuid: n.cuid,
            nt: n.samples[0].nt,
            ks: n.samples[0].ks,
          );
          if (known != null) _skippedKnown++;
          final key = known ?? await _nestedRecoverer.recoverKey(n);
          _recordKey(
            source: RecoverSource.tag,
            kind: weakKind(n),
            cuid: n.cuid,
            sectorName: n.sectorName,
            keyName: n.keyName,
            key: key,
          );
        }),
      );
    }
  }

  // ---- tag: hardnested ----

  Future<void> _recoverHardnested(List<NestedNonce> group) async {
    final first = group.first;
    // The firmware stores the plaintext nonce nt and keystream ks = nt_enc ^ nt,
    // so the encrypted nonce is recovered as nt ^ ks (this holds for any nt);
    // par is the encrypted-parity nibble as-is.
    final ntEnc = group
        .map((n) => n.samples[0].nt ^ n.samples[0].ks)
        .toList(growable: false);
    // Non-null for every single-sample nonce: the parser drops a lone sample
    // that has no usable parity, and this group came out of splitSingles.
    final parEnc = group.map((n) => n.par!).toList(growable: false);
    BigInt? key;
    String? note;
    try {
      final result = await _hardnestedRecoverer.recoverKey(
        cuid: first.cuid,
        ntEnc: ntEnc,
        parEnc: parEnc,
        // The one attack long enough that the page has to say something while
        // it runs: the counter alone sat still for the whole of it.
        onProgress: (fraction) {
          // Not a ProgressThrottle, which the two transfers use: its 0.002
          // minimum delta would swallow every single-permille step, and on an
          // attack that reports in tenths of a percent for hours that is every
          // step there is. The poll is already time-limited at 500 ms, so all
          // that is left to suppress is two polls reading the same figure.
          //
          // Compared against the state rather than a field holding the last
          // value: the thing compared is then the thing on screen, so _tick
          // clearing the phase cannot leave a shadow copy saying a figure is
          // already shown when it no longer is.
          if (_disposed) return;
          if (_state case RecoverCalculating(fraction: final shown)
              when shown == fraction) {
            return;
          }
          _emit(
            RecoverCalculating(
              label: l10n.mfHardnestedPhase,
              fraction: fraction,
            ),
          );
        },
        isCancelled: () => _stopping,
      );
      key = result.key;
      switch (result.outcome) {
        case HardnestedOutcome.found:
          break;
        case HardnestedOutcome.engineBusy:
          // Not the card's fault and not unknown: two attacks were started at
          // once, which the serial walk above is supposed to prevent.
          LogService.error(
            '[Recover] hardnested refused: another attack is already running',
          );
          _hadFailure = true;
          note = l10n.mfHardnestedFailed;
        case HardnestedOutcome.engineFault:
          // The engine's own fault, not an answer about the card. Logged
          // because an unknown status means this build and the native side
          // disagree, which nothing else would record.
          LogService.error(
            '[Recover] hardnested engine returned an unknown '
            'status for ${first.sectorName}/${first.keyName}',
          );
          _hadFailure = true;
          note = l10n.mfHardnestedFailed;
        case HardnestedOutcome.stopped:
          // The user's own doing, so not a failure - _hadFailure is left alone
          // and the nonces are still on the card for the next run.
          //
          // Clears the phase without _tick(): no unit was finished, so nothing
          // should claim one, but the label and percentage this attack was
          // reporting would otherwise sit on screen - at whatever figure Stop
          // caught it - through the dictionary write that follows.
          _emit(const RecoverCalculating());
          // Recorded rather than dropped. This is the sector the user watched
          // for however long before pressing Stop; returning without a row left
          // it missing from the summary entirely, which reads as though it was
          // never attempted.
          _recordKey(
            source: RecoverSource.tag,
            kind: RecoverKind.hardnested,
            cuid: first.cuid,
            sectorName: first.sectorName,
            keyName: first.keyName,
            key: null,
            note: l10n.mfHardnestedStopped,
            counted: false,
          );
          return;
        case HardnestedOutcome.outOfMemory:
          _hadFailure = true;
          note = l10n.mfHardnestedOutOfMemory;
        case HardnestedOutcome.noKey:
          // Ran and found nothing; only a group too small to attack is a
          // "collect more" situation.
          note = group.length < 2
              ? l10n.mfNotRecoveredFewNonces(group.length)
              : l10n.mfNotRecoveredNoKey(group.length);
      }
    } catch (e, st) {
      // A missing/broken native engine must not abort the whole run and discard
      // the reader/weak keys already recovered - degrade this group to a note
      // and carry on to the user-dict upload.
      LogService.error('[Recover] hardnested engine failed: $e\n$st');
      _hadFailure = true;
      // Only a load failure means the build is at fault; anything else is this
      // group failing, and saying otherwise sends the user after the wrong fix.
      note = e is NativeEngineUnavailable
          ? l10n.mfHardnestedUnavailable
          : l10n.mfHardnestedFailed;
    }
    _recordKey(
      source: RecoverSource.tag,
      kind: RecoverKind.hardnested,
      cuid: first.cuid,
      sectorName: first.sectorName,
      keyName: first.keyName,
      key: key,
      note: note,
    );
  }

  /// Surfaces unparseable `.nested.log` lines. A corrupt line is dropped rather
  /// than guessed at — a wrong parity generates the wrong half of the candidate
  /// space, and a wrong sector files correct candidates under an index the
  /// device never tries them against — but dropping one silently would leave
  /// those sector keys unattacked with nothing on screen to say so, and a log
  /// the app cannot read at all would finish as "no new keys".
  void _reportDroppedNonces(NestedLog log) {
    final dropped = log.droppedLines;
    LogService.error('[Recover] dropped $dropped corrupt .nested.log line(s)');
    _hadFailure = true;
    _entries.add(
      RecoverEntry(
        source: RecoverSource.tag,
        kind: RecoverKind.corruptLog,
        note: log.nonces.isEmpty
            ? l10n.mfLogAllDropped(dropped)
            : l10n.mfLogPartlyDropped(dropped),
      ),
    );
  }

  // ---- tag: static-encrypted candidate dictionaries ----

  /// Every static-encrypted row shares its source and kind; only the cuid, the
  /// count and the note vary, so those are what a reader should see.
  void _addStaticEntry({int? cuid, int? candidateCount, String? note}) =>
      _entries.add(
        RecoverEntry(
          source: RecoverSource.tag,
          kind: RecoverKind.staticEncrypted,
          cuid: cuid,
          candidateCount: candidateCount,
          note: note,
        ),
      );

  /// [cards] is the number of units `_run` planned for this batch, passed in
  /// rather than recomputed so the denominator and the ticks cannot drift.
  Future<void> _recoverStatic(
    List<NestedNonce> singles, {
    required int cards,
  }) async {
    // Named rather than left under "Recovering keys": generation is the half of
    // this step that reports nothing - one isolate call covering every card,
    // with only the device write after it carrying a percentage.
    _emit(RecoverCalculating(label: l10n.mfGenerating));
    final List<StaticCandidateDict> dicts;
    try {
      dicts = await _staticRecoverer.buildCandidateDicts(singles);
    } catch (e, st) {
      LogService.error('[Recover] static candidate gen failed: $e\n$st');
      _hadFailure = true;
      // Run-level, with no cuid: the throw comes from setting up the engine,
      // not from any one card, and every card in the batch lost its dictionary.
      // Naming the first one would blame a card that was probably fine.
      _addStaticEntry(note: _staticFailureNote(e));
      _tick(cards);
      return;
    }

    // Across every card, so a run with two dictionaries reads as one upload
    // rather than two bars that each start again at zero.
    final totalBytes = dicts.fold<int>(
      0,
      (sum, dict) => sum + (dict.body?.bytes.length ?? 0),
    );
    final throttle = ProgressThrottle();
    var doneBytes = 0;

    for (final dict in dicts) {
      if (_stopping) return;
      // This card's unit, whatever becomes of it. Inside the loop so the
      // readout advances through the phase rather than jumping by N at the end.
      // One dict per card - buildStaticDicts groups by cuid - so this ends on
      // the same total the catch path above accounts for in one go.
      _tick();
      final body = dict.body;
      if (body == null) {
        // This one card failed; the rest of the batch still has dictionaries.
        _hadFailure = true;
        _addStaticEntry(cuid: dict.cuid, note: _staticFailureNote(dict.error!));
        continue;
      }
      if (body.isEmpty) {
        // Every sector key came back with nothing, so there is no file to
        // write - report which ones rather than a bare "nothing generated".
        _hadFailure = true;
        _addStaticEntry(
          cuid: dict.cuid,
          note: l10n.mfNoCandidates(_nameKeys(body.skippedKeys)),
        );
        continue;
      }
      try {
        await _client.storageWriteChunked(
          cuidDictPath(dict.cuid),
          body.bytes,
          // Reported, because this is the one step of a run whose duration the
          // user cannot guess from the work: a dictionary is tens of thousands
          // of entries, and over BLE that is minutes during which every other
          // readout holds still. Scaled across all the cards, so a second
          // dictionary does not send the bar back to zero. Within one card it
          // can still go backwards: a link drop restarts that upload from the
          // beginning, and the bytes really are being sent again.
          onProgress: (fraction) {
            // No _disposed check: _emit already has one. totalBytes cannot be
            // zero here - an empty body never reaches this write - but a
            // division that produced NaN would reach the bar silently.
            if (totalBytes == 0) return;
            final overall =
                ((doneBytes + fraction * body.bytes.length) / totalBytes).clamp(
                  0.0,
                  1.0,
                );
            if (throttle.shouldEmit(overall)) _emit(RecoverUploading(overall));
          },
          // Stop means stop: without this the write runs to completion against
          // a device the user has walked away from, or long after they asked it
          // to end. The firmware's stream is closed cleanly, and the
          // half-written file deleted where the link outlived the cancel.
          isCancelled: () => _stopping,
        );
        _wroteCandidates = true;
      } on FlipperWriteCancelledException {
        // Our own cancel coming back, from either flag - and the two want
        // different things, which this used to miss. On a dispose there is
        // nothing left to report to. On a Stop the page is still there, and
        // returning silently is how this card came to vanish from the summary
        // altogether: no row, _wroteCandidates left false, so even the
        // "verify these on the device" footnote went missing. The user had
        // watched that upload run.
        //
        // Not a failure, so _hadFailure is left alone - the candidates are
        // regenerated from the same log on the next run. And still a return:
        // every card behind this one would be cancelled the same way.
        if (!_disposed) {
          // No candidateCount: that row reads "N candidate keys -> <file>",
          // and the file was deleted on the way out.
          _addStaticEntry(cuid: dict.cuid, note: l10n.mfCandidatesStopped);
          notifyListeners();
        }
        return;
      } catch (e, st) {
        LogService.error('[Recover] static dict write failed: $e\n$st');
        _hadFailure = true;
        // No candidateCount: that row reads "N candidate keys -> <file>", and
        // there is no file on the device to point at.
        _addStaticEntry(
          cuid: dict.cuid,
          note: l10n.mfWriteFailed(body.entries),
        );
        continue;
      } finally {
        // On every attempted card, not only the ones that landed: a card
        // counted in the denominator and never in the numerator leaves the bar
        // short of full for the rest of the run, and the >= 1.0 shortcut that
        // would have corrected it never fires.
        doneBytes += body.bytes.length;
      }
      if (!body.isComplete) _hadFailure = true;
      _addStaticEntry(
        cuid: dict.cuid,
        candidateCount: body.entries,
        note: _dictGapNote(body),
      );
    }
  }

  /// Names the sector keys the written dictionary cannot recover, so a card
  /// that comes back partly unread is explained here rather than looking like
  /// an attack that simply failed on the device.
  static String? _dictGapNote(CuidDictBody body) {
    final parts = <String>[
      if (body.skippedKeys.isNotEmpty)
        l10n.mfGapSkipped(_nameKeys(body.skippedKeys)),
      if (body.cappedKeys.isNotEmpty)
        l10n.mfGapCapped(_nameKeys(body.cappedKeys)),
    ];
    if (parts.isEmpty) return null;
    return l10n.mfGapSuffix(parts.join('; '));
  }

  /// Names the affected sector keys, summarising a long list so one bad card
  /// cannot turn the note into a wall of text.
  static String _nameKeys(List<String> keys) {
    const limit = 6;
    if (keys.length <= limit) return keys.join(', ');
    return l10n.mfKeysAndMore(keys.take(limit).join(', '), keys.length - limit);
  }

  /// Separates the failures worth acting on differently. Everything else stays
  /// deliberately vague: the exception and its stack are already logged, and
  /// `ArgumentError` in particular is shared by the FFI allocator, a missing
  /// symbol and a refused dictionary entry, so it cannot name a cause on its
  /// own — which is why the engine lookup raises [NativeEngineUnavailable].
  static String _staticFailureNote(Object error) => switch (error) {
    NativeEngineUnavailable() => l10n.mfCandidatesUnavailable,
    OutOfMemoryError() => l10n.mfOutOfMemory,
    _ => l10n.mfCandidatesFailed,
  };

  // ---- helpers ----

  /// Formats [key], registers it against the user dict when present (deciding
  /// new-vs-known now), appends the summary entry and advances progress - the
  /// shared tail of the three single-key phases (reader / weak / hardnested).
  void _recordKey({
    required RecoverSource source,
    required RecoverKind kind,
    required int cuid,
    required String sectorName,
    required String keyName,
    BigInt? key,
    String? note,
    // A key found in the dictionary rather than cracked was never planned as a
    // unit, so it must not advance a counter sized without it.
    bool counted = true,
  }) {
    final keyHex = key == null ? null : formatMifareKey(key.toInt());
    final isNew = keyHex == null ? null : _storage.registerKey(keyHex);
    _entries.add(
      RecoverEntry(
        source: source,
        kind: kind,
        cuid: cuid,
        sectorName: sectorName,
        keyName: keyName,
        key: keyHex,
        isNew: isNew,
        note: note,
      ),
    );
    if (counted) _tick();
  }

  Future<String> _download(
    String path, {
    int expectedSize = 0,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await _client.storageReadChunked(
      path,
      expectedSize: expectedSize,
      onProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );
    return const Utf8Decoder().convert(bytes);
  }

  Future<int> _fileSize(String path) async {
    try {
      final batch = await _client.storageStat(StatRequest(path: path));
      final response = batch.firstOrNull;
      return response != null && response.hasFile() ? response.file.size : 0;
    } catch (e) {
      LogService.error('[Recover] stat $path failed: $e');
      return 0;
    }
  }

  /// Finishes [units] of the run's planned work.
  ///
  /// Takes a count so the paths that finish several at once - a static batch
  /// whose generation threw, losing every card together - say so in one call
  /// and one rebuild, rather than a loop whose only job is to add N.
  void _tick([int units = 1]) {
    if (_disposed) return;
    _doneUnits += units;
    // The unit that the label and fraction described is over, so they go with
    // it. Without this a hardnested group that ended at 47% sat there through
    // the next group's table decompression, which reports nothing. Through
    // _emit rather than assigning _state, so that stays the only writer.
    if (_state is RecoverCalculating) {
      _emit(const RecoverCalculating());
    } else {
      notifyListeners();
    }
  }

  void _emit(RecoverState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
