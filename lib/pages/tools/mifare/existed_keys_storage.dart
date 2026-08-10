import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import 'mfkey32_models.dart';

const flipperDictUserPath = '/ext/nfc/assets/mf_classic_dict_user.nfc';
const flipperDictPath = '/ext/nfc/assets/mf_classic_dict.nfc';

/// Per-card static-encrypted candidate dictionary. A single source of truth for
/// the name so the device write and the UI label can never drift apart.
String cuidDictFileName(int cuid) => 'mf_classic_dict_${formatCuid(cuid)}.nfc';
String cuidDictPath(int cuid) => '/ext/nfc/assets/${cuidDictFileName(cuid)}';

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
  // The write-back set for the user dict (seeded from it, then extended with new
  // keys). A Set so a key recovered from several sectors in one run - or already
  // duplicated in the loaded dict - is written once. Insertion order preserved.
  final Set<String> _userKeys = {};

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
    return _userKeys.where((key) => !_userDict.contains(key)).toList();
  }

  /// Records [foundedKey] and folds its key into the user-dict write-back set.
  /// Returns whether the key is new to the user + system dictionaries (true),
  /// already known (false), or null when there is no key - so the caller can
  /// tag the result immediately rather than waiting for the end-of-run set.
  bool? onNewKey(FoundedKey foundedKey) {
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

    return key == null ? null : existed == null;
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
