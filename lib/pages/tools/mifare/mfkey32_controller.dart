import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'existed_keys_storage.dart';
import 'key_nonce_parser.dart';
import 'mfkey32_models.dart';
import 'mfkey32_recoverer.dart';

const pathNonceLog = '/ext/nfc/.mfkey32.log';

class MfKey32Controller extends ChangeNotifier {
  MfKey32Controller({
    FlipperClient? client,
    MfKey32Recoverer? recoverer,
  })  : _client = client ?? FlipperOneClient().get(),
        _recoverer = recoverer ?? NativeMfKey32Recoverer() {
    _state = _client.isConnected
        ? const MfKey32WaitingForFlipper()
        : const MfKey32Error(MfKey32ErrorType.flipperConnection);
  }

  final FlipperClient _client;
  final MfKey32Recoverer _recoverer;

  late MfKey32State _state;
  FoundedInformation _foundedInformation = const FoundedInformation();
  bool _running = false;

  MfKey32State get state => _state;
  FoundedInformation get foundedInformation => _foundedInformation;
  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _startCalculation();
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _startCalculation() async {
    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    if (!await _hasNonceLog()) {
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return;
    }

    _emit(const MfKey32DownloadingRawFile(0));
    final rawText = await _downloadNonceLog();
    if (rawText == null) {
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return;
    }
    _emit(const MfKey32DownloadingRawFile(1));

    final nonces = KeyNonceParser.parse(rawText);
    final existedKeysStorage = ExistedKeysStorage(_client);

    try {
      await existedKeysStorage.load();
    } catch (e) {
      LogService.log('[MfKey32] load keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    _emit(const MfKey32Calculating(0));
    for (var i = 0; i < nonces.length; i++) {
      final nonce = nonces[i];
      BigInt? key;
      try {
        key = await _recoverer.bruteforceKey(nonce);
      } catch (e) {
        LogService.log('[MfKey32] bruteforce failed: $e');
        _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
        return;
      }

      existedKeysStorage.onNewKey(FoundedKey(
        sectorName: nonce.sectorName,
        keyName: nonce.keyName,
        key: key?.toRadixString(16).padLeft(12, '0').toUpperCase(),
      ));
      _foundedInformation = existedKeysStorage.foundedInformation;
      _emit(MfKey32Calculating(nonces.isEmpty ? 1 : (i + 1) / nonces.length));
    }

    _emit(const MfKey32Uploading());
    late final List<String> addedKeys;
    try {
      addedKeys = await existedKeysStorage.upload();
    } catch (e) {
      LogService.log('[MfKey32] upload keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }
    try {
      await _client.storageDelete(
        DeleteRequest(path: pathNonceLog),
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      LogService.log('[MfKey32] delete nonce log failed: $e');
    }
    _emit(MfKey32Saved(addedKeys));
  }

  Future<bool> _hasNonceLog() async {
    try {
      await _client.storageMd5sum(
        Md5sumRequest(path: pathNonceLog),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (e) {
      LogService.log('[MfKey32] nonce log md5 failed: $e');
      return false;
    }
  }

  Future<String?> _downloadNonceLog() async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: pathNonceLog),
        timeout: const Duration(minutes: 5),
      );
      final bytes = <int>[];
      for (final response in batch.items) {
        if (response.hasFile()) bytes.addAll(response.file.data);
      }
      return const Utf8Decoder().convert(bytes);
    } catch (e) {
      LogService.log('[MfKey32] download nonce log failed: $e');
      return null;
    }
  }

  void _emit(MfKey32State state) {
    _state = state;
    notifyListeners();
  }
}
