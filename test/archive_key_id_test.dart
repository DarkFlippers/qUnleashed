// The string that says which file a key is, which the three overview pages and
// the controller each composed for themselves. #375.
//
// It is one function now, and that is what makes this file worth writing: a
// mutation to the spelling survived the entire suite before it existed.
// Everything that reads the id goes through the same code within a run - the
// selection sets, `_keys`, the favourites - so a different spelling is
// self-consistent and invisible to every behavioural test in the suite.
//
// What it is *not* invisible to is a user. The favourites file on disk is
// keyed by this string (`ArchiveController._favorites`, written by
// `writeFavorites`), so a release that spells it differently reads every
// stored star as a file it has never seen and the archive comes up unstarred.
// That is why the id has its own cases rather than being left to the pages
// that use it, and why they are written as literals.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';

ArchiveKey key({String subFolder = ''}) => ArchiveKey(
  name: 'card',
  category: ArchiveCategory.nfc,
  state: ArchiveKeyState.synced,
  subFolder: subFolder,
);

void main() {
  test('a file at the root of its category dir', () {
    expect(
      archiveKeyId(flipperDir: 'nfc', name: 'card', extension: 'nfc'),
      'nfc/card.nfc',
    );
  });

  test('a file in a sub-folder, with one separator and not two', () {
    expect(
      archiveKeyId(
        flipperDir: 'nfc',
        name: 'card',
        extension: 'nfc',
        subFolder: 'work',
      ),
      'nfc/work/card.nfc',
    );
  });

  /// The getter forwarding every part. `ArchiveKey.id` *is* a call to
  /// `archiveKeyId`, so this cannot catch the two disagreeing - it catches the
  /// getter dropping a part on the way, `subFolder` being the one with a
  /// default to drop it into. A literal, not the function again, which is both
  /// shorter and stricter.
  test('the getter forwards every part it is holding', () {
    expect(key().id, 'nfc/card.nfc');
    expect(key(subFolder: 'work').id, 'nfc/work/card.nfc');
  });

  /// Not the remote path, which is the distinction the getter's own doc makes.
  /// `remotePath` maps the dir through [ArchiveCategory.remoteDirOf] and can
  /// be overridden outright - the file manager wraps an arbitrary on-device
  /// file in a key for emulation that way - so it identifies a place on the
  /// Flipper rather than a row in the archive.
  test('and it is not the remote path', () {
    expect(key().remotePath, '/ext/nfc/card.nfc');
    expect(key().id, 'nfc/card.nfc');
  });
}
