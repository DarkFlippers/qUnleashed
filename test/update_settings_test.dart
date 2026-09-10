import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String key = 'firmware_update_settings_v1';

Future<String?> stored() async =>
    (await SharedPreferences.getInstance()).getString(key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = UpdateSettingsStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    // The store is a singleton and outlives any one controller, so a test that
    // did not clear it would inherit the previous test's choices.
    await store.clear();
  });

  group('remembering a choice', () {
    test('nothing is remembered before anything is chosen', () async {
      await store.load();

      expect(store.selectionFor('unlshd'), isNull);
    });

    test('a channel and a variant come back', () async {
      await store.remember(
        'unlshd',
        channelId: 'development',
        variant: UnleashedVariant.compact,
      );
      await store.clear();
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'unlshd': {'channel': 'development', 'variant': 'compact'},
        }),
      });
      await store.load();

      expect(store.selectionFor('unlshd')?.channelId, 'development');
      expect(store.selectionFor('unlshd')?.variant, UnleashedVariant.compact);
    });

    test('choices are kept per firmware', () async {
      await store.remember('unlshd', channelId: 'release', variant: null);
      await store.remember('roguemaster', channelId: 'dev', variant: null);

      expect(store.selectionFor('unlshd')?.channelId, 'release');
      expect(store.selectionFor('roguemaster')?.channelId, 'dev');
    });

    test('a later choice replaces the earlier one', () async {
      await store.remember(
        'unlshd',
        channelId: 'release',
        variant: UnleashedVariant.base,
      );
      await store.remember(
        'unlshd',
        channelId: 'development',
        variant: UnleashedVariant.compact,
      );

      expect(store.selectionFor('unlshd')?.channelId, 'development');
      expect(store.selectionFor('unlshd')?.variant, UnleashedVariant.compact);
    });

    test('a firmware with nothing chosen is not written out', () async {
      await store.remember('unlshd', channelId: null, variant: null);

      expect(await stored(), isNot(contains('unlshd')));
    });
  });

  group('reading what is on disk', () {
    Future<void> onDisk(Object value) async {
      await store.clear();
      SharedPreferences.setMockInitialValues({key: jsonEncode(value)});
      await store.load();
    }

    test('a variant this build no longer has keeps the channel', () async {
      // Dropping the whole entry would lose a perfectly good channel with it.
      await onDisk({
        'unlshd': {'channel': 'release', 'variant': 'quantum'},
      });

      expect(store.selectionFor('unlshd')?.channelId, 'release');
      expect(store.selectionFor('unlshd')?.variant, isNull);
    });

    test('an entry with only a channel reads back', () async {
      await onDisk({
        'unlshd': {'channel': 'release'},
      });

      expect(store.selectionFor('unlshd')?.channelId, 'release');
      expect(store.selectionFor('unlshd')?.variant, isNull);
    });

    test('an empty channel reads as no choice', () async {
      await onDisk({
        'unlshd': {'channel': ''},
      });

      expect(store.selectionFor('unlshd')?.channelId, isNull);
    });

    test('a malformed entry is skipped, not fatal', () async {
      await onDisk({
        'unlshd': 'not an object',
        'roguemaster': {'channel': 'dev'},
      });

      expect(store.selectionFor('unlshd'), isNull);
      expect(store.selectionFor('roguemaster')?.channelId, 'dev');
    });

    test('a value that is not JSON is ignored', () async {
      await store.clear();
      SharedPreferences.setMockInitialValues({key: 'not json at all'});

      await store.load();

      expect(store.selectionFor('unlshd'), isNull);
    });

    test('a JSON value that is not a map is ignored', () async {
      await onDisk(['unlshd']);

      expect(store.selectionFor('unlshd'), isNull);
    });
  });

  group('loading', () {
    test('reads once and serves later callers from memory', () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'unlshd': {'channel': 'release'},
        }),
      });
      await store.load();

      // A second read of the same store must not go back to disk, where the
      // value may since have changed under it.
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'unlshd': {'channel': 'development'},
        }),
      });
      await store.load();

      expect(store.selectionFor('unlshd')?.channelId, 'release');
    });

    test('remembering works without an explicit load first', () async {
      await store.remember('unlshd', channelId: 'release', variant: null);

      expect(store.selectionFor('unlshd')?.channelId, 'release');
      expect(await stored(), contains('release'));
    });
  });
}
