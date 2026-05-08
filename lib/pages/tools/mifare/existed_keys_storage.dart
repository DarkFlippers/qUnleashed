import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import 'mfkey32_models.dart';

const flipperDictUserPath = '/ext/nfc/assets/mf_classic_dict_user.nfc';
const flipperDictPath = '/ext/nfc/assets/mf_classic_dict.nfc';

class ExistedKeysStorage {
  ExistedKeysStorage(this._client);

  final FlipperClient _client;
  FoundedInformation _foundedInformation = const FoundedInformation();
  final Set<String> _flipperKeys = {};
  final Set<String> _userDict = {};
  final List<String> _userKeys = [];

  FoundedInformation get foundedInformation => _foundedInformation;

  Future<void> load() async {
    final foundedUserDict = await _loadDict(flipperDictUserPath);
    _userDict.addAll(foundedUserDict);
    _userKeys.addAll(foundedUserDict);
    final foundedDict = await _loadDict(flipperDictPath);
    _flipperKeys.addAll(foundedDict);
  }

  Future<List<String>> upload() async {
    final text = '${_userKeys.join('\n')}\n';
    await _client.storageWriteChunked(
      flipperDictUserPath,
      utf8.encode(text),
    );
    return _userKeys.where((key) => !_userDict.contains(key)).toSet().toList();
  }

  void onNewKey(FoundedKey foundedKey) {
    final key = foundedKey.key;
    DuplicatedSource? existed;
    if (key != null && _flipperKeys.contains(key)) {
      existed = DuplicatedSource.flipper;
    } else if (key != null && _userDict.contains(key)) {
      existed = DuplicatedSource.user;
    }

    final keys = List<FoundedKey>.of(_foundedInformation.keys)..add(foundedKey);
    final uniqueKeys = Set<String>.of(_foundedInformation.uniqueKeys);
    final duplicated =
        Map<String, DuplicatedSource>.of(_foundedInformation.duplicated);

    if (existed == null && key != null) {
      uniqueKeys.add(key);
      _userKeys.add(key);
    } else if (existed != null && key != null) {
      duplicated[key] = existed;
    }

    _foundedInformation = _foundedInformation.copyWith(
      keys: keys,
      uniqueKeys: uniqueKeys,
      duplicated: duplicated,
    );
  }

  Future<List<String>> _loadDict(String path) async {
    try {
      final batch = await _client.storageRead(
        ReadRequest(path: path),
        timeout: const Duration(minutes: 5),
      );
      final bytes = <int>[];
      for (final response in batch.items) {
        if (response.hasFile()) bytes.addAll(response.file.data);
      }
      return const Utf8Decoder()
          .convert(bytes)
          .split('\n')
          .where((line) => !line.startsWith('/') && line.isNotEmpty)
          .toList();
    } catch (e) {
      LogService.log('[MfKey32] failed load dict $path: $e');
      return const [];
    }
  }
}
