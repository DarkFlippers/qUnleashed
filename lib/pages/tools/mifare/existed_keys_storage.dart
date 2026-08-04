import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import 'mfkey32_models.dart';

const flipperDictUserPath = '/ext/nfc/assets/mf_classic_dict_user.nfc';
const flipperDictPath = '/ext/nfc/assets/mf_classic_dict.nfc';

typedef DictReader = Future<List<int>> Function(String path);
typedef DictWriter = Future<void> Function(String path, List<int> data);

class ExistedKeysStorage {
  ExistedKeysStorage(FlipperClient client)
    : this.withSeams(
        reader: (path) => client.storageReadChunked(
          path,
          timeout: const Duration(minutes: 5),
        ),
        writer: (path, data) => client.storageWriteChunked(path, data),
      );

  /// Test seam: inject the device read/write directly instead of a FlipperClient.
  ExistedKeysStorage.withSeams({
    required DictReader reader,
    required DictWriter writer,
  }) : _reader = reader,
       _writer = writer;

  final DictReader _reader;
  final DictWriter _writer;
  FoundedInformation _foundedInformation = const FoundedInformation();
  final Set<String> _flipperKeys = {};
  final Set<String> _userDict = {};
  final List<String> _userKeys = [];

  FoundedInformation get foundedInformation => _foundedInformation;

  Future<void> load() async {
    // The user dict is read-modify-written by upload(): load() seeds _userKeys
    // from it and upload() writes the whole set back. So a *real* read failure
    // here must abort the run — proceeding with a truncated set would erase the
    // user's saved keys. Only a genuinely missing file counts as "empty".
    final foundedUserDict = await _loadDict(
      flipperDictUserPath,
      abortOnReadError: true,
    );
    _userDict.addAll(foundedUserDict);
    _userKeys.addAll(foundedUserDict);
    // The system dict is read-only (duplicate detection only), so a transient
    // failure degrades dedup rather than failing the whole run.
    final foundedDict = await _loadDict(
      flipperDictPath,
      abortOnReadError: false,
    );
    _flipperKeys.addAll(foundedDict);
  }

  Future<List<String>> upload() async {
    final text = '${_userKeys.join('\n')}\n';
    // Let write failures propagate so the caller surfaces an error instead of
    // reporting a false "keys added" success.
    await _writer(flipperDictUserPath, utf8.encode(text));
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
    final duplicated = Map<String, DuplicatedSource>.of(
      _foundedInformation.duplicated,
    );

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

  Future<List<String>> _loadDict(
    String path, {
    required bool abortOnReadError,
  }) async {
    try {
      final bytes = await _reader(path);
      return const Utf8Decoder()
          .convert(bytes)
          .split('\n')
          .where((line) => !line.startsWith('/') && line.isNotEmpty)
          .toList();
    } on FlipperRpcStorageNotExistException {
      // No such file yet — a legitimately empty dictionary (e.g. first run).
      return const [];
    } catch (e) {
      // A real read failure. For the user dict this must abort the run so
      // upload() can't overwrite it with a partial set; the system dict is
      // best-effort and degrades to empty.
      if (abortOnReadError) rethrow;
      LogService.log(
        '[ExistedKeysStorage] optional dict $path load failed: $e',
      );
      return const [];
    }
  }
}
