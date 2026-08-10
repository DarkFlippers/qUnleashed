import 'dart:collection';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

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
    _state = const MfKey32Error(MfKey32ErrorType.flipperConnection);
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

  late MfKey32State _state;
  bool _running = false;
  // Set from dispose(): the page can be popped (Stop) while _run() is still in
  // flight. Once true we neither notify the disposed ChangeNotifier nor start
  // any further recovery or device write.
  bool _disposed = false;
  final List<RecoverEntry> _entries = [];
  Set<String> _addedKeys = const {};

  int _totalUnits = 0;
  int _doneUnits = 0;

  MfKey32State get state => _state;
  bool get running => _running;

  /// Every recovery result gathered this run, in completion order.
  List<RecoverEntry> get entries => UnmodifiableListView(_entries);

  /// Total recovery units this run (reader keys + weak/static pairs + hardnested
  /// groups + one for the static-encrypted batch). The UI shows an indeterminate
  /// bar when this is <= 1, where a percentage would only ever read 0% then 100%.
  int get totalUnits => _totalUnits;

  /// Keys newly written to the user dictionary this run (i.e. not already in the
  /// user or system dict). Lets the UI tag each key new vs. already-known.
  Set<String> get addedKeys => _addedKeys;

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
      LogService.log('[Recover] Unexpected failure: $e\n$st');
      _emit(const MfKey32Error(MfKey32ErrorType.recoveryFailed));
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _run() async {
    _entries.clear();
    _addedKeys = const {};
    _totalUnits = 0;
    _doneUnits = 0;

    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    _emit(const MfKey32WaitingForFlipper());

    await _mfApi.checkBruteforceFileExist(_client);
    final hasReaderLog = _mfApi.isBruteforceFileExist;
    final hasTagLog = await _nestedApi.nonceFileExists(_client);
    if (!hasReaderLog && !hasTagLog) {
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return;
    }

    _emit(const MfKey32DownloadingRawFile(0));
    final String? readerText;
    final String? tagText;
    try {
      readerText = hasReaderLog ? await _download(pathNonceLog) : null;
      tagText = hasTagLog ? await _download(pathNestedLog) : null;
    } catch (e) {
      // The files were confirmed to exist above, so a failure here is a real
      // read error - surface it instead of silently proceeding as if the log
      // were empty (which would drop every key it held under a success screen).
      LogService.log('[Recover] download failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    try {
      await _storage.load();
    } catch (e) {
      LogService.log('[Recover] load keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
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
    _emit(const MfKey32Calculating(0));

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

    _emit(const MfKey32Uploading());
    try {
      _addedKeys = (await _storage.upload()).toSet();
    } catch (e) {
      LogService.log('[Recover] save keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    _emit(MfKey32Saved(_addedKeys.toList()));
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
      LogService.log('[Recover] hardnested engine failed: $e\n$st');
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
      LogService.log('[Recover] static candidate gen failed: $e\n$st');
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
      String? note;
      if (dict.count > 0) {
        try {
          await _client.storageWriteChunked(
            cuidDictPath(dict.cuid),
            dict.body,
          );
        } catch (e) {
          LogService.log('[Recover] static dict write failed: $e');
          note = 'Could not write the candidate dictionary to the device.';
        }
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

  /// Formats [key], records it against the user dict (a no-op for a null key),
  /// appends the summary entry and advances progress - the shared tail of the
  /// three single-key phases (reader / weak / hardnested).
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
    final isNew = _storage.onNewKey(
      FoundedKey(sectorName: sectorName, keyName: keyName, key: keyHex),
    );
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

  Future<String> _download(String path) async {
    final bytes = await _client.storageReadChunked(
      path,
      timeout: const Duration(minutes: 5),
    );
    return const Utf8Decoder().convert(bytes);
  }

  void _tick() {
    if (_disposed) return;
    _doneUnits++;
    if (_state is MfKey32Calculating && _totalUnits > 0) {
      _emit(MfKey32Calculating(_doneUnits / _totalUnits));
    } else {
      notifyListeners();
    }
  }

  void _emit(MfKey32State state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
