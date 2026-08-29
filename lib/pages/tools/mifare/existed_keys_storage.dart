import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import '../../../services/logging.dart';

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
  final Set<String> _flipperKeys = {};
  final Set<String> _userDict = {};
  // The write-back set for the user dict (seeded from it, then extended with new
  // keys). A Set so a key recovered from several sectors in one run - or already
  // duplicated in the loaded dict - is written once. Insertion order preserved.
  final Set<String> _userKeys = {};

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
    // _userKeys is seeded from the user dict and only grows, so an empty delta
    // means the dict is unchanged - skip the write-back entirely (no pointless
    // device write, and no spurious write error on a run that found nothing new).
    final added = _userKeys.where((key) => !_userDict.contains(key)).toList();
    if (added.isEmpty) return added;
    // Let write failures propagate so the caller surfaces an error instead of
    // reporting a false "keys added" success.
    await _writer(
      flipperDictUserPath,
      utf8.encode('${_userKeys.join('\n')}\n'),
    );
    return added;
  }

  /// Registers a newly recovered [key], folding it into the user-dict write-back
  /// set only when it's new to both the user and system dictionaries. Returns
  /// whether it was new - so the caller can tag the result during the run rather
  /// than waiting for the end-of-run set.
  bool registerKey(String key) {
    final isNew = !_flipperKeys.contains(key) && !_userDict.contains(key);
    if (isNew) _userKeys.add(key);
    return isNew;
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
      LogService.error(
        '[ExistedKeysStorage] optional dict $path load failed: $e',
      );
      return const [];
    }
  }
}
