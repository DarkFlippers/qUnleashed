import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = UpdateSettingsStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    // The store is a singleton and outlives any one controller, so a test that
    // did not reset it would inherit the previous test's choices.
    store.reset();
  });

  /// Puts raw preferences in place and drops whatever the store had read.
  void onDisk(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    store.reset();
  }

  group('remembering a choice', () {
    test('nothing is remembered before anything is chosen', () async {
      await store.load();

      expect(store.channelFor('unlshd'), isNull);
      expect(store.variantFor('unlshd'), isNull);
    });

    test('a channel comes back', () async {
      await store.remember('unlshd', channelId: 'development');
      store.reset();
      await store.load();

      expect(store.channelFor('unlshd'), 'development');
    });

    test('a variant comes back', () async {
      await store.remember('unlshd', variant: UnleashedVariant.compact);
      store.reset();
      await store.load();

      expect(store.variantFor('unlshd'), UnleashedVariant.compact);
    });

    test('choices are kept per firmware', () async {
      await store.remember('unlshd', channelId: 'release');
      await store.remember('ofw', channelId: 'dev');
      store.reset();
      await store.load();

      expect(store.channelFor('unlshd'), 'release');
      expect(store.channelFor('ofw'), 'dev');
    });

    test('a later choice replaces the earlier one', () async {
      await store.remember('unlshd', channelId: 'release');
      await store.remember('unlshd', channelId: 'development');
      store.reset();
      await store.load();

      expect(store.channelFor('unlshd'), 'development');
    });

    // Each field is written on its own, so a tap on one selector cannot
    // persist whatever happened to be sitting in the other.
    test('recording a channel leaves the variant alone', () async {
      await store.remember('unlshd', variant: UnleashedVariant.compact);
      await store.remember('unlshd', channelId: 'development');
      store.reset();
      await store.load();

      expect(store.variantFor('unlshd'), UnleashedVariant.compact);
      expect(store.channelFor('unlshd'), 'development');
    });

    test('recording a variant leaves the channel alone', () async {
      await store.remember('unlshd', channelId: 'development');
      await store.remember('unlshd', variant: UnleashedVariant.base);

      store.reset();
      await store.load();

      expect(store.channelFor('unlshd'), 'development');
      expect(store.variantFor('unlshd'), UnleashedVariant.base);
    });

    test('recording nothing writes nothing', () async {
      await store.remember('unlshd');
      store.reset();
      await store.load();

      expect(store.channelFor('unlshd'), isNull);
    });
  });

  group('reading what is on disk', () {
    test('a variant this build no longer has keeps the channel', () async {
      onDisk({
        'firmware.update.unlshd.channel': 'release',
        'firmware.update.unlshd.variant': 'quantum',
      });

      await store.load();

      expect(store.channelFor('unlshd'), 'release');
      expect(store.variantFor('unlshd'), isNull);
    });

    // The reason each field is its own preference: one unreadable value must
    // cost that value, not everything stored beside it - and certainly not
    // everything, which is what a single re-written blob would have done.
    test('a value of the wrong type costs only itself', () async {
      onDisk({
        'firmware.update.unlshd.channel': 42,
        'firmware.update.unlshd.variant': 'compact',
        'firmware.update.ofw.channel': 'dev',
      });

      await store.load();

      expect(store.channelFor('unlshd'), isNull);
      expect(store.variantFor('unlshd'), UnleashedVariant.compact);
      expect(store.channelFor('ofw'), 'dev');
    });

    test('an empty value reads as no choice', () async {
      onDisk({'firmware.update.unlshd.channel': ''});

      await store.load();

      expect(store.channelFor('unlshd'), isNull);
    });

    test('a key naming a field this build does not know is ignored', () async {
      onDisk({
        'firmware.update.unlshd.mystery': 'whatever',
        'firmware.update.unlshd.channel': 'release',
      });

      await store.load();

      expect(store.channelFor('unlshd'), 'release');
    });

    test('other preferences are left alone', () async {
      onDisk({'theme.mode': 'dark', 'firmware.update.unlshd.channel': 'rel'});

      await store.load();

      expect(store.channelFor('unlshd'), 'rel');
      expect(store.channelFor('theme'), isNull);
    });
  });

  group('loading', () {
    test('reads once and serves later callers from memory', () async {
      onDisk({'firmware.update.unlshd.channel': 'release'});
      await store.load();

      // A second read of the same store must not go back to disk, where the
      // value may since have changed under it.
      SharedPreferences.setMockInitialValues({
        'firmware.update.unlshd.channel': 'development',
      });
      await store.load();

      expect(store.channelFor('unlshd'), 'release');
    });

    test('remembering works without an explicit load first', () async {
      await store.remember('unlshd', channelId: 'release');

      expect(store.channelFor('unlshd'), 'release');
    });
  });
}
