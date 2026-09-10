import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/pages/devices/controllers/firmware.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

FirmwareDirectoryChannel channel(String id) => FirmwareDirectoryChannel(
  id: id,
  title: id,
  description: '',
  versions: const [
    FirmwareVersion(version: '1.0.0', changelog: '', timestamp: 0, files: []),
  ],
);

/// Runs [body] once the controller has read its stored choices.
///
/// The read is asynchronous, so anything asserted before it lands is asserting
/// against the fallback rather than against what was remembered.
Future<void> withController(
  Future<void> Function(FirmwareController fw) body,
) async {
  final fw = FirmwareController();
  await pumpEventQueue();
  try {
    await body(fw);
  } finally {
    fw.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = UpdateSettingsStore.instance;
  final unleashed = QAppConfig.firmware.firmwares.firstWhere(
    (f) => f.shortName == 'unlshd',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    settings.reset();
    for (final entry in QAppConfig.firmware.firmwares) {
      parserForEntry(entry).clearCache();
    }
  });

  void giveChannels(List<String> ids) {
    parserForEntry(unleashed).seedCache(
      FirmwareDirectory(channels: [for (final id in ids) channel(id)]),
    );
  }

  /// Leaves a choice on disk as a previous run would have, then drops what the
  /// store read so the next controller has to go and fetch it.
  Future<void> alreadyChose({
    String? channel,
    UnleashedVariant? variant,
  }) async {
    await settings.remember('unlshd', channelId: channel, variant: variant);
    settings.reset();
  }

  group('remembering the update settings', () {
    test('with nothing stored it settles on the release channel', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'release');
      });
    });

    test('a remembered channel is used instead of the default', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'development');

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'development');
      });
    });

    test('a remembered variant is used instead of the default', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'release', variant: UnleashedVariant.compact);

      await withController((fw) async {
        expect(fw.selectedVariant(unleashed), UnleashedVariant.compact);
      });
    });

    // The custom channel is the one the fallback treats as "nobody has chosen
    // yet", so a remembered choice of it has to be marked as a real choice or
    // it is silently replaced on every launch.
    test('a remembered custom channel is not overridden', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: kCustomFirmwareChannelId);

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), kCustomFirmwareChannelId);
      });
    });

    test('a channel that no longer exists falls back', () async {
      giveChannels(['release']);
      await alreadyChose(channel: 'development');

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'release');
      });
    });

    // The real cold start. The directory cache is in-memory only, so on first
    // launch the channel list holds nothing but the custom entry until a
    // network round trip finishes - and validating a remembered channel
    // against that list replaces it with custom, which counts as a choice and
    // so is never corrected when the real channels arrive. Every other test
    // here seeds the directory first, which is warmer than any real launch.
    test('a remembered channel survives the directory arriving late', () async {
      await alreadyChose(channel: 'development');

      final fw = FirmwareController();
      await pumpEventQueue();
      giveChannels(['release', 'development']);
      await FirmwareRepository.instance.refresh();
      await pumpEventQueue();

      expect(fw.selectedChannelId(unleashed), 'development');
      fw.dispose();
    });

    test('choosing a channel records it', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setChannel(unleashed, 'development');
        await pumpEventQueue();
      });

      expect(settings.channelFor('unlshd'), 'development');
    });

    test('choosing a variant records it', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setChannel(unleashed, 'release');
        fw.setVariant(unleashed, UnleashedVariant.compact);
        await pumpEventQueue();
      });

      expect(settings.variantFor('unlshd'), UnleashedVariant.compact);
    });

    // A variant tap must not persist whatever channel the fallback happened to
    // pick, or a user who never touched the channel selector is quietly opted
    // out of following the default from then on.
    test('choosing a variant does not record an unchosen channel', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setVariant(unleashed, UnleashedVariant.compact);
        await pumpEventQueue();
      });

      expect(settings.channelFor('unlshd'), isNull);
    });

    test('what was chosen survives into the next controller', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setChannel(unleashed, 'development');
        await pumpEventQueue();
      });
      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'development');
      });
    });

    // The read is asynchronous, so a tap can land first. Replacing what the
    // user is looking at with a stale stored value would be worse than
    // forgetting it.
    test('a channel chosen while the read is in flight wins', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'release');

      final fw = FirmwareController();
      fw.setChannel(unleashed, 'development');
      await pumpEventQueue();

      expect(fw.selectedChannelId(unleashed), 'development');
      fw.dispose();
    });

    // Tracked per field: a channel tap says nothing about the variant, so a
    // variant chosen in the same window has to be honoured on its own.
    test('a variant chosen while the read is in flight wins', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'release', variant: UnleashedVariant.base);

      final fw = FirmwareController();
      fw.setVariant(unleashed, UnleashedVariant.compact);
      await pumpEventQueue();

      expect(fw.selectedVariant(unleashed), UnleashedVariant.compact);
      fw.dispose();
    });

    // The read is started in the constructor and cannot be cancelled, so
    // leaving the page inside that window used to notify a disposed notifier.
    test('leaving the page before the read lands is not an error', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'development');

      FirmwareController().dispose();

      await pumpEventQueue();
    });
  });
}
