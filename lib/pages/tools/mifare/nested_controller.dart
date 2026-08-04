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
        FoundedKey;
import 'nested_api.dart';
import 'nested_models.dart';
import 'nested_nonce_parser.dart';
import 'nested_recoverer.dart';

/// Drives the nested key-recovery flow: download `.nested.log` from the Flipper,
/// recover weak-PRNG nested keys (two-sample lines) locally, and sync the
/// results back into the user dictionary.
///
/// Single-sample static-encrypted (FM11RF08S) lines are counted but not yet
/// solved — that path needs a per-card cross-sector solver and lands next.
class NestedController extends ChangeNotifier {
  NestedController({
    FlipperClient? client,
    NestedApi? api,
    NestedRecoverer? recoverer,
  })  : _client = client ?? FlipperOneClient().get(),
        _api = api ?? NestedApiImpl(),
        _recoverer = recoverer ?? NativeNestedRecoverer() {
    _state = const MfKey32Error(MfKey32ErrorType.flipperConnection);
    _existedKeysStorage = ExistedKeysStorage(_client);
  }

  final FlipperClient _client;
  final NestedApi _api;
  final NestedRecoverer _recoverer;
  late final ExistedKeysStorage _existedKeysStorage;

  late MfKey32State _state;
  String _rawNonceLog = '';
  bool _running = false;
  int _deferredStaticEncrypted = 0;

  MfKey32State get state => _state;
  FoundedInformation get foundedInformation =>
      _existedKeysStorage.foundedInformation;
  bool get running => _running;

  /// Number of static-encrypted nonces skipped this run (feature pending).
  int get deferredStaticEncrypted => _deferredStaticEncrypted;

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
    _deferredStaticEncrypted = 0;

    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    _emit(const MfKey32WaitingForFlipper());
    if (!await _prepare()) return;

    final nonces = NestedNonceParser.parse(_rawNonceLog);
    final pairs = nonces.where((n) => n.hasPair).toList(growable: false);
    _deferredStaticEncrypted = nonces.length - pairs.length;
    if (_deferredStaticEncrypted > 0) {
      LogService.log(
        '[Nested] Deferred $_deferredStaticEncrypted static-encrypted nonce(s)',
      );
    }

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
          LogService.log('[Nested] ${nonce.sectorName}/${nonce.keyName} = $key');
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
    _emit(MfKey32Saved(addedKeys));
  }

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
        key: key?.toRadixString(16).padLeft(12, '0').toUpperCase(),
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
