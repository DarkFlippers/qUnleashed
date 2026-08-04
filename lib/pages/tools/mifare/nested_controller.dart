import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'existed_keys_storage.dart';
import 'mfkey32_models.dart'
    show
        MfKey32State,
        MfKey32WaitingForFlipper,
        MfKey32DownloadingRawFile,
        MfKey32Calculating,
        MfKey32Uploading,
        MfKey32Saved,
        MfKey32Error,
        MfKey32ErrorType,
        FoundedInformation,
        FoundedKey,
        formatMifareKey;
import 'nested_api.dart';
import 'nested_models.dart';
import 'nested_nonce_parser.dart';
import 'nested_recoverer.dart';
import 'static_encrypted_recoverer.dart';

/// Why the static-encrypted candidate step failed. The weak-key result (if any)
/// is still saved and reported regardless.
enum StaticCandidateError { generationFailed, writeFailed }

/// Drives the nested key-recovery flow: download `.nested.log` from the Flipper,
/// recover weak-PRNG nested keys (two-sample lines) locally and sync them into
/// the user dictionary.
///
/// Single-sample static-encrypted (FM11RF08S) lines can't be resolved to a
/// unique key offline, so for those we generate a per-CUID candidate dictionary
/// (`mf_classic_dict_<cuid>.nfc`) that the device verifies against the tag. That
/// step is supplementary: if it fails, the recovered weak keys are still saved
/// and reported, and the static failure is surfaced separately via [staticError].
class NestedController extends ChangeNotifier {
  NestedController({
    FlipperClient? client,
    NestedApi? api,
    NestedRecoverer? recoverer,
    StaticEncryptedRecoverer? staticRecoverer,
  }) : _client = client ?? FlipperOneClient().get(),
       _api = api ?? NestedApiImpl(),
       _recoverer = recoverer ?? NativeNestedRecoverer(),
       _staticRecoverer = staticRecoverer ?? NativeStaticEncryptedRecoverer() {
    _state = const MfKey32Error(MfKey32ErrorType.flipperConnection);
    _existedKeysStorage = ExistedKeysStorage(_client);
  }

  final FlipperClient _client;
  final NestedApi _api;
  final NestedRecoverer _recoverer;
  final StaticEncryptedRecoverer _staticRecoverer;
  late final ExistedKeysStorage _existedKeysStorage;

  late MfKey32State _state;
  String _rawNonceLog = '';
  bool _running = false;
  List<({int cuid, int count})> _staticCandidateSummary = const [];
  StaticCandidateError? _staticError;

  MfKey32State get state => _state;
  FoundedInformation get foundedInformation =>
      _existedKeysStorage.foundedInformation;
  bool get running => _running;

  /// Per-CUID candidate dictionaries written this run (cuid, candidate count).
  /// These need on-device verification against the tag. A count of 0 means the
  /// card's nonces were processed but yielded no candidates.
  List<({int cuid, int count})> get staticCandidateSummary =>
      _staticCandidateSummary;

  /// Set when the static-encrypted candidate step failed. The weak-key result
  /// (if any) is still saved and reported regardless.
  StaticCandidateError? get staticError => _staticError;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run();
    } catch (e, st) {
      LogService.log('[Nested] Unexpected failure: $e\n$st');
      _emit(const MfKey32Error(MfKey32ErrorType.recoveryFailed));
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _run() async {
    LogService.log('[Nested] Start calculation');
    _staticCandidateSummary = const [];
    _staticError = null;

    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    _emit(const MfKey32WaitingForFlipper());
    if (!await _prepare()) return;

    final nonces = NestedNonceParser.parse(_rawNonceLog);
    final pairs = nonces.where((n) => n.hasPair).toList(growable: false);
    final singles = nonces.where((n) => !n.hasPair).toList(growable: false);

    _emit(const MfKey32Calculating(0));
    // Recovery is memory-heavy (~50 MB transient per isolate) and a fully
    // collected card yields dozens of pairs, so cap how many run concurrently
    // to keep peak memory bounded instead of spawning one isolate per pair.
    const maxConcurrent = 4;
    var completed = 0;
    for (var offset = 0; offset < pairs.length; offset += maxConcurrent) {
      await Future.wait(
        pairs.skip(offset).take(maxConcurrent).map((nonce) async {
          final key = await _recoverer.recoverKey(nonce);
          LogService.log(
            '[Nested] ${nonce.sectorName}/${nonce.keyName} = $key',
          );
          completed++;
          _onFoundKey(nonce, key, pairs.length, completed);
        }),
      );
    }

    _emit(const MfKey32Uploading());
    late final List<String> addedKeys;
    try {
      addedKeys = await _existedKeysStorage.upload();
    } catch (e) {
      LogService.log('[Nested] When save keys: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    // Static-encrypted candidates are supplementary — a failure here must not
    // erase the weak-key result that was just saved, so it never throws out.
    if (singles.isNotEmpty) {
      await _generateAndWriteStaticDicts(singles);
    }

    _emit(MfKey32Saved(addedKeys));
  }

  /// Generates FM11RF08S candidate keys for single-sample nonces and writes each
  /// card's candidates to `mf_classic_dict_<cuid>.nfc`, where the device's own
  /// dictionary attack can confirm the real keys against the tag. Records a
  /// per-card summary (incrementally, so a mid-way failure keeps what was
  /// written) and reports any failure via [staticError] rather than throwing.
  Future<void> _generateAndWriteStaticDicts(List<NestedNonce> singles) async {
    final List<StaticCandidateDict> dicts;
    try {
      dicts = await _staticRecoverer.buildCandidateDicts(singles);
    } catch (e, st) {
      LogService.log('[Nested] Candidate generation failed: $e\n$st');
      _staticError = StaticCandidateError.generationFailed;
      return;
    }

    // The summary reflects what was generated per card, independent of the write
    // outcome (a write failure is reported separately via [staticError]).
    _staticCandidateSummary = List.unmodifiable([
      for (final dict in dicts) (cuid: dict.cuid, count: dict.count),
    ]);

    for (final dict in dicts) {
      if (dict.count == 0) continue; // surfaced with count 0; nothing to write
      try {
        await _client.storageWriteChunked(_cuidDictPath(dict.cuid), dict.body);
      } catch (e) {
        LogService.log(
          '[Nested] Candidate dict write failed (${dict.cuid}): $e',
        );
        _staticError = StaticCandidateError.writeFailed;
        return; // written dicts + summary survive; weak keys still saved
      }
    }
  }

  static String _cuidDictPath(int cuid) =>
      '/ext/nfc/assets/mf_classic_dict_${cuid.toRadixString(16).padLeft(8, '0')}.nfc';

  Future<bool> _prepare() async {
    if (!await _api.nonceFileExists(_client)) {
      LogService.log('[Nested] Not found $pathNestedLog');
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return false;
    }

    _emit(const MfKey32DownloadingRawFile(0));
    try {
      final raw = await _downloadNonceLog();
      if (raw == null) {
        _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
        return false;
      }
      _rawNonceLog = raw;
      _emit(const MfKey32DownloadingRawFile(0.99));
    } catch (e) {
      LogService.log('[Nested] Failed to download $pathNestedLog: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return false;
    }

    try {
      await _existedKeysStorage.load();
    } catch (e) {
      LogService.log('[Nested] When load keys: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return false;
    }
    return true;
  }

  Future<String?> _downloadNonceLog() async {
    try {
      final bytes = await _client.storageReadChunked(
        pathNestedLog,
        timeout: const Duration(minutes: 5),
      );
      return const Utf8Decoder().convert(bytes);
    } catch (e) {
      LogService.log('[Nested] download nonce log failed: $e');
      return null;
    }
  }

  void _onFoundKey(NestedNonce nonce, BigInt? key, int total, int completed) {
    _existedKeysStorage.onNewKey(
      FoundedKey(
        sectorName: nonce.sectorName,
        keyName: nonce.keyName,
        key: key == null ? null : formatMifareKey(key.toInt()),
      ),
    );
    // Update progress and publish the new key in a single rebuild.
    if (_state is MfKey32Calculating) {
      _state = MfKey32Calculating(completed / total);
    }
    notifyListeners();
  }

  void _emit(MfKey32State state) {
    _state = state;
    notifyListeners();
  }
}
