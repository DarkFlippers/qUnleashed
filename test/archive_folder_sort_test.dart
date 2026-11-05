import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/archive/models/key.dart';
import 'package:qunleashed/pages/archive/overview/category/sort.dart';

/// Ordering the archive by the folder a file lives in.
///
/// Sorting by name alone is what #122 is about: a copy of Flipper-IRDB puts
/// some ten thousand remotes in `/ext/infrared`, the folders are the only
/// categories they have, and by name `LED_Lighting/10-key_Candle`,
/// `Miscellaneous/1533` and `Car_Multimedia/2005_Volvo_XC-90` land next to
/// each other.
///
/// Most cases here are ones the plain `compareTo` of a joined path gets
/// wrong; the rest are ones the implementation is free to get wrong by
/// accident, and the first is simply the issue report itself.
ArchiveKey _key(String subFolder, String name, {ArchiveCategory? cat}) =>
    ArchiveKey(
      name: name,
      category: cat ?? ArchiveCategory.infrared,
      state: ArchiveKeyState.synced,
      subFolder: subFolder,
    );

/// `'<folder>/<name>'` per key, which is what the assertions read against.
List<String> _paths(List<ArchiveKey> keys) => [
  for (final k in keys)
    k.subFolder.isEmpty ? k.name : '${k.subFolder}/${k.name}',
];

void main() {
  test('groups by folder and orders each folder by name', () {
    final sorted = sortArchiveKeys(
      [
        _key('Miscellaneous', '1533'),
        _key('LED_Lighting', '10-key_Candle'),
        _key('Car_Multimedia', '2005_Volvo_XC-90'),
        _key('LED_Lighting', 'Aputure'),
        _key('Car_Multimedia', 'Alpine'),
      ],
      'folder',
      true,
    );

    expect(_paths(sorted), [
      'Car_Multimedia/2005_Volvo_XC-90',
      'Car_Multimedia/Alpine',
      'LED_Lighting/10-key_Candle',
      'LED_Lighting/Aputure',
      'Miscellaneous/1533',
    ]);
  });

  test('files at the category root come before its folders', () {
    final sorted = sortArchiveKeys(
      [_key('TV', 'Sony'), _key('', 'loose_remote')],
      'folder',
      true,
    );

    expect(_paths(sorted), ['loose_remote', 'TV/Sony']);
  });

  test('descending turns the folders around and leaves the names alone', () {
    final sorted = sortArchiveKeys(
      [
        _key('Audio', 'Denon'),
        _key('Audio', 'Bose'),
        _key('TV', 'Samsung'),
        _key('TV', 'LG'),
      ],
      'folder',
      false,
    );

    // Folders Z-A, names A-Z inside each. Reversing the comparator wholesale
    // would give Samsung before LG, and Denon before Bose.
    expect(_paths(sorted), [
      'TV/LG',
      'TV/Samsung',
      'Audio/Bose',
      'Audio/Denon',
    ]);
  });

  test('a sibling folder does not land inside a shorter one subtree', () {
    // The case `'/'` alone cannot order: it is 0x2F and the space sorts below
    // it, so comparing the joined paths puts `TV Shows` between `TV`'s own
    // file and `TV`'s subfolder, splitting the subtree the sort exists to
    // keep together. `-`, `.` and `&` all do the same.
    final sorted = sortArchiveKeys(
      [
        _key('TV Shows', 'Netflix'),
        _key('TV/Sony', 'KD-55'),
        _key('TV', 'Philips'),
        _key('TV-old', 'Trinitron'),
      ],
      'folder',
      true,
    );

    expect(_paths(sorted), [
      'TV/Philips',
      'TV/Sony/KD-55',
      'TV Shows/Netflix',
      'TV-old/Trinitron',
    ]);
  });

  test('folders group case-insensitively, as the name sort orders', () {
    final sorted = sortArchiveKeys(
      [_key('audio', 'b'), _key('Audio', 'a'), _key('BOILERS', 'c')],
      'folder',
      true,
    );

    expect(_paths(sorted), ['Audio/a', 'audio/b', 'BOILERS/c']);
  });

  test('the category directory leads, so mixed-category lists group by it', () {
    // Favourites and Deleted put every category in one table, where a `Cars`
    // under subghz and a `Cars` under nfc are two folders and not one.
    //
    // The folder and file names here are chosen to disagree with the
    // directory: on subFolder alone `Alpha` would precede `Zebra`, and on the
    // name tiebreak alone `alpha` would precede `zebra`. Only the directory
    // leading puts nfc first, so this cannot pass on either of them.
    final sorted = sortArchiveKeys(
      [
        _key('Alpha', 'zebra', cat: ArchiveCategory.subghz),
        _key('Zebra', 'alpha', cat: ArchiveCategory.nfc),
      ],
      'folder',
      true,
    );

    expect(sorted.map((k) => k.category), [
      ArchiveCategory.nfc, // nfc
      ArchiveCategory.subghz, // subghz
    ]);
  });

  test('the order does not depend on the order it was handed', () {
    final keys = [
      _key('B', 'two'),
      _key('A', 'one'),
      _key('B', 'one'),
      _key('A', 'two'),
    ];

    // Without the name tiebreak the two runs disagree. At this length
    // `List.sort` takes its insertion-sort path and keeps whatever order each
    // folder's files arrived in, so the two inputs come back differently
    // ordered; past 32 entries it stops keeping anything at all. Name is the
    // explicit tiebreak for both.
    expect(
      _paths(sortArchiveKeys(keys, 'folder', true)),
      _paths(sortArchiveKeys(keys.reversed.toList(), 'folder', true)),
    );
  });

  test('sorting by folder leaves the list it was given alone', () {
    final keys = [_key('B', 'two'), _key('A', 'one')];
    sortArchiveKeys(keys, 'folder', true);

    expect(_paths(keys), ['B/two', 'A/one']);
  });

  test('name sorting is untouched by the new key', () {
    final sorted = sortArchiveKeys(
      [_key('Zebra', 'apple'), _key('Apple', 'zebra')],
      'name',
      true,
    );

    expect(_paths(sorted), ['Zebra/apple', 'Apple/zebra']);
  });
}
