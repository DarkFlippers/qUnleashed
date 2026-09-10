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

  /// Seeds a directory for [entry], defaulting to Unleashed.
  ///
  /// Every firmware gets one by default. Leaving any unseeded means the
  /// controller goes to the network for it - a dozen live requests per run -
  /// and the resulting notify runs a fallback pass *before* the stored
  /// settings are read, which quietly pre-satisfies assertions that the
  /// default channel is release.
  void giveChannels(List<String> ids, {FirmwareEntry? entry}) {
    for (final f in entry == null ? QAppConfig.firmware.firmwares : [entry]) {
      parserForEntry(f).seedCache(
        FirmwareDirectory(channels: [for (final id in ids) channel(id)]),
      );
    }
  }

  /// Leaves a choice on disk as a previous run would have, then drops what the
  /// store read so the next controller has to go and fetch it.
  Future<void> alreadyChose({
    String shortName = 'unlshd',
    String? channel,
    UnleashedVariant? variant,
  }) async {
    await settings.remember(shortName, channelId: channel, variant: variant);
    settings.reset();
  }

  group('remembering the update settings', () {
    test('with nothing stored it settles on the release channel', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        // Every firmware, not just the first: the fallback loops them all, and
        // asserting only on the first would let it be narrowed unnoticed.
        for (final entry in QAppConfig.firmware.firmwares) {
          expect(
            fw.selectedChannelId(entry),
            'release',
            reason: entry.shortName,
          );
        }
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
      addTearDown(fw.dispose);
      await pumpEventQueue();
      giveChannels(['release', 'development']);
      FirmwareRepository.instance.directoryChanged();
      await pumpEventQueue();

      expect(fw.selectedChannelId(unleashed), 'development');
    });

    test('the seeded directory is what the controller offers', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        expect(fw.channelsFor(unleashed).map((c) => c.id), [
          'release',
          'development',
          kCustomFirmwareChannelId,
        ]);
      });
    });

    // Both the restore and the fallback loop every firmware, and every other
    // assertion here is on the first one - so narrowing either loop to `.first`
    // would go unnoticed.
    test('every firmware is restored, not just the first', () async {
      final other = QAppConfig.firmware.firmwares.firstWhere(
        (f) => f.shortName != 'unlshd',
      );
      giveChannels(['release', 'development']);
      await alreadyChose(shortName: other.shortName, channel: 'development');

      await withController((fw) async {
        expect(fw.selectedChannelId(other), 'development');
        expect(fw.selectedChannelId(unleashed), 'release');
      });
    });

    // The directory matches channel ids through their aliases, so a feed that
    // renames one must not silently discard what the user picked.
    test('a channel the feed now spells differently is kept', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'dev');

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'development');
      });
    });

    // selectedVariant already reports the packaged variant for a channel that
    // has no variants, so moving through one must not discard the choice -
    // which is what made the screen and the next launch disagree.
    test('a variant survives a channel that has none', () async {
      giveChannels(['release', 'release-candidate']);
      await alreadyChose(channel: 'release', variant: UnleashedVariant.compact);

      await withController((fw) async {
        fw.setChannel(unleashed, 'release-candidate');
        expect(fw.selectedVariant(unleashed), UnleashedVariant.extraPacks);

        fw.setChannel(unleashed, 'release');
        expect(fw.selectedVariant(unleashed), UnleashedVariant.compact);
      });
    });

    test('a stored variant is not offered on a channel without them', () async {
      giveChannels(['release-candidate', 'release']);
      await alreadyChose(
        channel: 'release-candidate',
        variant: UnleashedVariant.compact,
      );

      await withController((fw) async {
        expect(fw.hasVariants(unleashed), isFalse);
        expect(fw.selectedVariant(unleashed), UnleashedVariant.extraPacks);
      });
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
      addTearDown(fw.dispose);
      fw.setChannel(unleashed, 'development');
      await pumpEventQueue();

      expect(fw.selectedChannelId(unleashed), 'development');
    });

    // Tracked per field: a channel tap says nothing about the variant, so a
    // variant chosen in the same window has to be honoured on its own.
    test('a variant chosen while the read is in flight wins', () async {
      giveChannels(['release', 'development']);
      await alreadyChose(channel: 'release', variant: UnleashedVariant.base);

      final fw = FirmwareController();
      addTearDown(fw.dispose);
      fw.setVariant(unleashed, UnleashedVariant.compact);
      await pumpEventQueue();

      expect(fw.selectedVariant(unleashed), UnleashedVariant.compact);
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
