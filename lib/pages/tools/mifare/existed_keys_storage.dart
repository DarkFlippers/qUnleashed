import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';

import '../../../services/logging.dart';

const flipperDictUserPath = '/ext/nfc/assets/mf_classic_dict_user.nfc';
const flipperDictPath = '/ext/nfc/assets/mf_classic_dict.nfc';

/// Where the user dictionary is copied before it is overwritten.
///
/// Not a temp-and-rename: the firmware's rename cannot replace an existing
/// file, so that shape would have to delete the original first and would leave
/// a window where neither copy exists. A copy alongside has no such window, and
/// the file it leaves behind is one the user can find.
const flipperDictUserBackupPath =
    '/ext/nfc/assets/mf_classic_dict_user.nfc.bak';

typedef DictReader = Future<List<int>> Function(String path);
typedef DictWriter = Future<void> Function(String path, List<int> data);
typedef DictDeleter = Future<void> Function(String path);

class ExistedKeysStorage {
  /// Reads and writes the key dictionaries on the device.
  ///
  /// No task declared here: every caller is already inside one - the recovery
  /// run - and these calls inherit its binding, so one declared here would
  /// bind the same session a second time and say nothing extra.
  ExistedKeysStorage(FlipperClient client)
    : this.withSeams(
        reader: (path) => client.storageReadChunked(
          path,
          timeout: const Duration(minutes: 5),
        ),
        writer: (path, data) => client.storageWriteChunked(path, data),
        deleter: (path) =>
            client.storageDelete(DeleteRequest(path: path)).then((_) {}),
      );

  /// Test seam: inject the device read/write directly instead of a FlipperClient.
  ExistedKeysStorage.withSeams({
    required this._reader,
    required this._writer,
    DictDeleter? deleter,
  }) : _deleter = deleter ?? _noDelete;

  static Future<void> _noDelete(String path) async {}

  final DictReader _reader;
  final DictWriter _writer;
  final DictDeleter _deleter;
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

  /// True when [upload] overwrote the user dictionary and left a copy of the
  /// previous contents behind, because the write did not finish.
  ///
  /// The caller shows this: a dictionary built up over months is worth more
  /// than one run's keys, and the copy is the only way back to it.
  bool get backupKept => _backupKept;
  bool _backupKept = false;

  /// True when the copy could not be made, so the overwrite went ahead with
  /// nothing standing behind it.
  ///
  /// The worse of the two states and the one worth saying loudest: if the write
  /// then fails, the firmware has already truncated the file and there is no
  /// copy anywhere. "Tap Retry" and "stop and check the card" are different
  /// instructions.
  bool get backupFailed => _backupFailed;
  bool _backupFailed = false;

  Future<List<String>> upload() async {
    // _userKeys is seeded from the user dict and only grows, so an empty delta
    // means the dict is unchanged - skip the write-back entirely (no pointless
    // device write, and no spurious write error on a run that found nothing new).
    // Reset per attempt: the Retry button makes a second upload() reachable,
    // and a flag left true by an earlier run would point the next failure at a
    // copy this run never made.
    _backupKept = false;
    _backupFailed = false;
    final added = _userKeys.where((key) => !_userDict.contains(key)).toList();
    if (added.isEmpty) return added;

    // Copy what is there before overwriting it. The firmware opens the target
    // with CREATE_ALWAYS, so the write's first frame truncates the file - and a
    // write that then fails on a frame the one-shot restart cannot recover
    // leaves the user with neither their old keys nor the new ones. Only worth
    // doing when there is something to lose.
    if (_userDict.isNotEmpty) {
      try {
        await _writer(
          flipperDictUserBackupPath,
          utf8.encode('${_userDict.join('\n')}\n'),
        );
        _backupKept = true;
      } catch (e) {
        // Best-effort: a device that will not take the copy is unlikely to take
        // the write either, and failing here would turn a recoverable run into
        // a lost one for the sake of a precaution.
        _backupFailed = true;
        LogService.warn('[Recover] user dict backup failed: $e');
      }
    }

    // Let write failures propagate so the caller surfaces an error instead of
    // reporting a false "keys added" success - with the copy left in place.
    await _writer(
      flipperDictUserPath,
      utf8.encode('${_userKeys.join('\n')}\n'),
    );

    // The write landed, so the copy is only clutter now. Cleared only once the
    // delete returns: a copy still on the card is better described as kept than
    // as gone.
    if (_backupKept) {
      try {
        await _deleter(flipperDictUserBackupPath);
        _backupKept = false;
      } catch (e) {
        LogService.warn('[Recover] user dict backup cleanup failed: $e');
      }
    }
    return added;
  }

  /// Every key the device already holds, user dictionary and stock alike.
  ///
  /// The set a nonce is tried against before it is attacked - both dictionaries,
  /// because a key being stock rather than the user's own makes no difference to
  /// whether cracking it again is wasted work.
  Iterable<String> get knownKeys => {..._flipperKeys, ..._userDict};

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
