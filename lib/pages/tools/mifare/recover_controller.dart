import 'dart:collection';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/logging.dart';
import '../../../services/progress_throttle.dart';
import 'existed_keys_storage.dart';
import 'hardnested_recoverer.dart';
import 'key_nonce_parser.dart';
import 'mfkey32_api.dart';
import 'mfkey32_models.dart';
import 'mfkey32_recoverer.dart';
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
    FlipperClient? client,
    MfKey32Api? mfApi,
    NestedApi? nestedApi,
    MfKey32Recoverer? mfRecoverer,
    NestedRecoverer? nestedRecoverer,
    StaticEncryptedRecoverer? staticRecoverer,
    HardnestedRecoverer? hardnestedRecoverer,
  }) : _client = client ?? FlipperOneClient().get(),
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
  late final ExistedKeysStorage _storage;

  late RecoverState _state;
  bool _running = false;
  // Set from dispose(): the page can be popped (Stop) while _run() is still in
  // flight. Once true we neither notify the disposed ChangeNotifier nor start
  // any further recovery or device write.
  bool _disposed = false;
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

  RecoverState get state => _state;
  bool get running => _running;

  /// Every recovery result gathered this run, in completion order.
  List<RecoverEntry> get entries => UnmodifiableListView(_entries);

  /// Total recovery units this run (reader keys + weak/static pairs + hardnested
  /// groups + one for the static-encrypted batch). Drives the "N of M" readout.
  int get totalUnits => _totalUnits;

  /// Units finished so far. Each unit runs to completion with no sub-progress,
  /// so the UI pairs this count with an animated bar rather than a percentage
  /// that would freeze between units.
  int get doneUnits => _doneUnits;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> start() async {
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
    _totalUnits = 0;
    _doneUnits = 0;

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

    // Plan the work up front so progress is meaningful across both logs.
    final readerNonces = readerText == null
        ? const <MfKey32Nonce>[]
        : dedupeReaderNonces(KeyNonceParser.parse(readerText));
    final tagNonces = tagText == null
        ? const <NestedNonce>[]
        : NestedNonceParser.parse(tagText);
    final weak = dedupeWeakNonces(tagNonces.where((n) => n.hasPair));
    final (staticSingles, hardGroups) = splitSingles(
      tagNonces.where((n) => !n.hasPair),
    );
    _totalUnits =
        readerNonces.length +
        weak.length +
        hardGroups.length +
        (staticSingles.isEmpty ? 0 : 1);
    _emit(const RecoverCalculating());

    await _recoverReader(readerNonces);
    await _recoverWeak(weak);
    for (final group in hardGroups) {
      if (_disposed) return;
      await _recoverHardnested(group);
    }
    if (staticSingles.isNotEmpty) await _recoverStatic(staticSingles);
    // The user can back out (Stop) mid-run; don't rewrite the user dict (a
    // read-modify-write over the shared client) after that point.
    if (_disposed) return;

    _emit(const RecoverUploading());
    final List<String> added;
    try {
      added = await _storage.upload();
    } catch (e, st) {
      LogService.error('[Recover] save keys failed: $e\n$st');
      _emit(const RecoverError(RecoverErrorType.readWrite));
      return;
    }

    _emit(
      RecoverSaved(
        keys: added,
        hasCandidates: _wroteCandidates,
        hasFailures: _hadFailure,
      ),
    );
  }

  // ---- reader (mfkey32) ----

  Future<void> _recoverReader(List<MfKey32Nonce> nonces) async {
    for (final n in nonces) {
      if (_disposed) return;
      final key = await _mfRecoverer.bruteforceKey(n);
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
      if (_disposed) return;
      await Future.wait(
        weak.skip(i).take(maxConcurrent).map((n) async {
          final key = await _nestedRecoverer.recoverKey(n);
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
    final parEnc = group.map((n) => n.samples[0].par).toList(growable: false);
    BigInt? key;
    String? note;
    try {
      key = await _hardnestedRecoverer.recoverKey(
        cuid: first.cuid,
        ntEnc: ntEnc,
        parEnc: parEnc,
      );
      // A null key here means the engine ran and found nothing; only a group
      // too small to attack (< 2 nonces) is a "collect more" situation.
      if (key == null) {
        note = group.length < 2
            ? 'Not recovered — only ${group.length} nonce collected; '
                  'collect more on the device and retry.'
            : 'Not recovered from ${group.length} nonces — no key found.';
      }
    } catch (e, st) {
      // A missing/broken native engine must not abort the whole run and discard
      // the reader/weak keys already recovered - degrade this group to a note
      // and carry on to the user-dict upload.
      LogService.error('[Recover] hardnested engine failed: $e\n$st');
      _hadFailure = true;
      note = 'Hardnested recovery is unavailable on this build.';
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

  // ---- tag: static-encrypted candidate dictionaries ----

  Future<void> _recoverStatic(List<NestedNonce> singles) async {
    final List<StaticCandidateDict> dicts;
    try {
      dicts = await _staticRecoverer.buildCandidateDicts(singles);
    } catch (e, st) {
      LogService.error('[Recover] static candidate gen failed: $e\n$st');
      _hadFailure = true;
      _entries.add(
        RecoverEntry(
          source: RecoverSource.tag,
          kind: RecoverKind.staticEncrypted,
          cuid: singles.first.cuid,
          note: 'Candidate generation failed.',
        ),
      );
      _tick();
      return;
    }

    for (final dict in dicts) {
      if (_disposed) return;
      if (dict.count == 0) {
        // Generation produced nothing (e.g. an allocation failure) and no file
        // was written - report it as a failure, not a 0-candidate "result".
        _hadFailure = true;
        _entries.add(
          RecoverEntry(
            source: RecoverSource.tag,
            kind: RecoverKind.staticEncrypted,
            cuid: dict.cuid,
            note: 'No candidate keys could be generated for this card.',
          ),
        );
        continue;
      }
      String? note;
      try {
        await _client.storageWriteChunked(cuidDictPath(dict.cuid), dict.body);
        _wroteCandidates = true;
      } catch (e, st) {
        LogService.error('[Recover] static dict write failed: $e\n$st');
        _hadFailure = true;
        note = 'Could not write the candidate dictionary to the device.';
      }
      _entries.add(
        RecoverEntry(
          source: RecoverSource.tag,
          kind: RecoverKind.staticEncrypted,
          cuid: dict.cuid,
          candidateCount: dict.count,
          note: note,
        ),
      );
    }
    _tick();
  }

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
    _tick();
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

  void _tick() {
    if (_disposed) return;
    _doneUnits++;
    notifyListeners();
  }

  void _emit(RecoverState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
