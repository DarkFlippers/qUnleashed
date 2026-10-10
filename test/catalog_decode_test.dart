import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/pages/apps/data/models/category.dart';

import 'kept_lines.dart';

/// Decoding a page of the apps catalogue.
///
/// Four list decodes in `catalog_api.dart` had the same shape:
/// `whereType<Map>().map(X.fromJson).toList()`. `whereType` filters out what
/// is not an object and does nothing about what is inside one, and `.toList()`
/// forces the lazy `.map`, so a throw arrives anyway — costing a page of 48
/// apps, up to 500 by uid, or the whole SDK list, which the catalogue context
/// turns into a disabled screen. #138.
///
/// They read entry by entry now, through one shared reader, and say once what
/// would not read.
void main() {
  setUp(recordKeptLines);

  late int logBase;

  setUp(() {
    clearKeptLines();
    // Read after clearing rather than trusting it: the history is a process
    // singleton and a line from the case before has been seen to arrive late.
    logBase = keptLines.length;
  });

  bool said(String fragment) =>
      keptLines.skip(logBase).any((l) => l.contains(fragment));

  Map<String, dynamic> card(String id) => {
    'id': id,
    'alias': id,
    'category_id': 'c',
    'author': 'someone',
    'created_at': 0,
    'updated_at': 0,
    'current_version': <String, dynamic>{
      'name': '1.0',
      'short_description': '',
    },
  };

  group('a list that reads cleanly', () {
    test('keeps every entry, in order', () {
      final out = readEach(
        [card('a'), card('b'), card('c')],
        AppCard.fromJson,
        'apps',
      );

      expect(out.map((c) => c.id), ['a', 'b', 'c']);
    });

    test('says nothing about it', () {
      readEach([card('a')], AppCard.fromJson, 'apps');

      expect(said('dropped'), isFalse);
    });

    test('reads an empty list as an empty list', () {
      expect(readEach([], AppCard.fromJson, 'apps'), isEmpty);
      expect(said('dropped'), isFalse);
    });
  });

  group('one entry that will not read', () {
    // The defect: a page of 48 apps where one has a renamed field used to
    // arrive as no apps at all.
    test('costs itself and nothing else', () {
      final out = readEach(
        [
          card('a'),
          {'id': 7},
          card('c'),
        ],
        AppCard.fromJson,
        'apps',
      );

      expect(out.map((c) => c.id), ['a', 'c']);
    });

    test('is counted once, against the whole list', () {
      readEach(
        [
          card('a'),
          {'id': 7},
          card('c'),
        ],
        AppCard.fromJson,
        'apps',
      );

      expect(said('dropped 1 of 3 apps'), isTrue);
    });

    // `whereType` used to drop these in silence, which is the same loss with
    // less evidence.
    test('includes an entry that is not an object at all', () {
      final out = readEach(
        [card('a'), 'not an object', 7, null],
        AppCard.fromJson,
        'apps',
      );

      expect(out, hasLength(1));
      expect(said('dropped 3 of 4 apps'), isTrue);
    });

    test('is named for the list it was in', () {
      readEach(
        [
          {'id': 7},
        ],
        AppCategory.fromJson,
        'categories',
      );

      expect(said('categories'), isTrue);
    });
  });

  group('a list that reads as nothing', () {
    // Every entry bad is a feed whose shape has changed, and the screen it
    // fills goes empty. That is worth one line, not fifty.
    test('says so once rather than per entry', () {
      readEach(
        [
          {'id': 1},
          {'id': 2},
          {'id': 3},
        ],
        AppCard.fromJson,
        'apps',
      );

      expect(said('dropped 3 of 3 apps'), isTrue);
      expect(
        keptLines.skip(logBase).where((l) => l.contains('dropped')),
        hasLength(1),
      );
    });
  });

  // The caller stores it and the screen reads it; nothing downstream should be
  // able to add to a decoded page.
  test('hands back a list the caller cannot change', () {
    final out = readEach([card('a')], AppCard.fromJson, 'apps');

    expect(() => out.add(out.first), throwsUnsupportedError);
  });
}
