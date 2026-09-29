import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/pages/apps/icons/icon_resolver.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/services/storage/paths.dart';

/// Fetching the catalogue's app icons, and what it says when it cannot.
///
/// The queue drains in the background behind the apps list. Every icon used
/// to fail on its own in silence, which is fine for one and wrong for all of
/// them: a catalogue that moved its images, or a link that is down, fails
/// every icon for one reason and the screen just stays grey.
///
/// Counted once for the drain rather than once per icon - a hundred lines for
/// one cause is a log nobody reads. ADR 0008.
AppCard card(String alias, String icon) => AppCard.fromJson({
  'id': alias,
  'alias': alias,
  'category_id': 'c',
  'author': 'someone',
  'created_at': 0,
  'updated_at': 0,
  'current_version': <String, dynamic>{
    'name': '1.0',
    'short_description': '',
    'icon_uri': icon,
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late int logBase;

  setUp(() {
    root = Directory.systemTemp.createTempSync('icon_resolver_test');
    debugUseDocumentsRoot(root);
    LogService.clearHistory();
    logBase = LogService.history.length;
    addTearDown(() {
      debugUseDocumentsRoot(null);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  bool said(String fragment) =>
      LogService.history.skip(logBase).any((l) => l.contains(fragment));

  Iterable<String> lines(String fragment) =>
      LogService.history.skip(logBase).where((l) => l.contains(fragment));

  /// Lets the queue drain. Every address below is unroutable, so each attempt
  /// ends in a connection failure rather than a wait.
  Future<void> drain() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  group('icons that will not come', () {
    test('are reported once for the batch, with the count', () async {
      IconResolver.instance.warmFromCatalog([
        card('a', 'http://127.0.0.1:1/a.png'),
        card('b', 'http://127.0.0.1:1/b.png'),
        card('c', 'http://127.0.0.1:1/c.png'),
      ]);
      await drain();

      expect(said('could not fetch 3 of 3'), isTrue);
      expect(lines('could not fetch'), hasLength(1));
    });

    test('name the total they were part of', () async {
      IconResolver.instance.warmFromCatalog([
        card('d', 'http://127.0.0.1:1/d.png'),
      ]);
      await drain();

      expect(said('of 1 catalogue icon'), isTrue);
    });
  });

  group('what never reaches the queue', () {
    // An SVG is not a Flipper icon and is skipped before any fetch, so it
    // cannot be one of the failures either.
    test('is an svg', () async {
      IconResolver.instance.warmFromCatalog([
        card('e', 'https://example.invalid/e.svg'),
      ]);
      await drain();

      expect(said('could not fetch'), isFalse);
    });

    test('is an entry with no icon at all', () async {
      IconResolver.instance.warmFromCatalog([card('f', '')]);
      await drain();

      expect(said('could not fetch'), isFalse);
    });

    test('is nothing at all', () async {
      IconResolver.instance.warmFromCatalog(const []);
      await drain();

      expect(said('[Icons]'), isFalse);
    });
  });
}
