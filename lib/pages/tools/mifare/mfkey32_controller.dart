import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'existed_keys_storage.dart';
import 'key_nonce_parser.dart';
import 'mfkey32_api.dart';
import 'mfkey32_models.dart';
import 'mfkey32_recoverer.dart';

const _totalPercent = 1.0;

class MfKey32Controller extends ChangeNotifier {
  MfKey32Controller({
    FlipperClient? client,
    MfKey32Api? mfKey32Api,
    MfKey32Recoverer? recoverer,
  })  : _client = client ?? FlipperOneClient().get(),
        _mfKey32Api = mfKey32Api ?? MfKey32ApiImpl(),
        _recoverer = recoverer ?? NativeMfKey32Recoverer() {
    _state = const MfKey32Error(MfKey32ErrorType.flipperConnection);
    _existedKeysStorage = ExistedKeysStorage(_client);
  }

  final FlipperClient _client;
  final MfKey32Api _mfKey32Api;
  final MfKey32Recoverer _recoverer;
  late final ExistedKeysStorage _existedKeysStorage;

  late MfKey32State _state;
  FoundedInformation _foundedInformation = const FoundedInformation();
  String _fileWithNonce = '';
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
    LogService.log('[MfKey32ViewModel] Start calculation');
    _foundedInformation = const FoundedInformation();

    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    _emit(const MfKey32WaitingForFlipper());

    if (!await _prepare()) {
      LogService.log('[MfKey32ViewModel] Failed prepare');
      return;
    }

    final nonces = KeyNonceParser.parse(_fileWithNonce);
    _emit(const MfKey32Calculating(0));
    await Future.wait(nonces.map((nonce) async {
      final key = await _recoverer.bruteforceKey(nonce);
      LogService.log('[MfKey32ViewModel] Key for nonce $nonce = $key');
      _onFoundKey(nonce, key, nonces.length);
    }));

    _emit(const MfKey32Uploading());
    late final List<String> addedKeys;
    try {
      addedKeys = await _existedKeysStorage.upload();
    } catch (e) {
      LogService.log('[MfKey32ViewModel] When save keys: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }
    await _deleteBruteforceApp();
    _emit(MfKey32Saved(addedKeys));
  }

  Future<bool> _prepare() async {
    LogService.log('[MfKey32ViewModel] Flipper connected');

    if (!_mfKey32Api.isBruteforceFileExist) {
      LogService.log('[MfKey32ViewModel] Not found $pathNonceLog');
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
    }

    await _mfKey32Api.checkBruteforceFileExist(_client);

    if (!_mfKey32Api.isBruteforceFileExist) {
      return false;
    }

    _emit(const MfKey32DownloadingRawFile(0));

    try {
      final rawText = await _downloadNonceLog();
      if (rawText == null) {
        _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
        return false;
      }
      _fileWithNonce = rawText;
      _emit(const MfKey32DownloadingRawFile(0.99));
    } catch (e) {
      LogService.log('[MfKey32ViewModel] Not found $pathNonceLog: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return false;
    }
    try {
      await _existedKeysStorage.load();
    } catch (e) {
      LogService.log('[MfKey32ViewModel] When load keys: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return false;
    }
    LogService.log('[MfKey32ViewModel] File download sucs');

    return true;
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

  Future<void> _deleteBruteforceApp() async {
    try {
      await _client.storageDelete(
        DeleteRequest(path: pathNonceLog),
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      LogService.log('[MfKey32ViewModel] #deleteBruteforceApp could not delete: $e');
    }
    await _mfKey32Api.checkBruteforceFileExist(_client);
  }

  void _onFoundKey(MfKey32Nonce nonce, BigInt? key, int totalCount) {
    final perNoncePercent = _totalPercent / totalCount;
    final currentState = _state;
    if (currentState is MfKey32Calculating) {
      _emit(MfKey32Calculating(currentState.percent + perNoncePercent));
    }
    final foundedKey = FoundedKey(
      sectorName: nonce.sectorName,
      keyName: nonce.keyName,
      key: key?.toRadixString(16).padLeft(12, '0').toUpperCase(),
    );
    _existedKeysStorage.onNewKey(foundedKey);
    _foundedInformation = _existedKeysStorage.foundedInformation;
    notifyListeners();
  }

  void _emit(MfKey32State state) {
    _state = state;
    notifyListeners();
  }
}
