import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/pages/devices/controllers/firmware.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefsKey = 'firmware_update_settings_v1';

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

  final unleashed = QAppConfig.firmware.firmwares.firstWhere(
    (f) => f.shortName == 'unlshd',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await UpdateSettingsStore.instance.clear();
    for (final entry in QAppConfig.firmware.firmwares) {
      parserForEntry(entry).clearCache();
    }
  });

  void giveChannels(List<String> ids) {
    parserForEntry(unleashed).seedCache(
      FirmwareDirectory(channels: [for (final id in ids) channel(id)]),
    );
  }

  Future<void> store(String json) async {
    SharedPreferences.setMockInitialValues({prefsKey: json});
    await UpdateSettingsStore.instance.clear();
    SharedPreferences.setMockInitialValues({prefsKey: json});
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
      await store(
        jsonEncode({
          'unlshd': {'channel': 'development'},
        }),
      );

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'development');
      });
    });

    test('a remembered variant is used instead of the default', () async {
      giveChannels(['release', 'development']);
      await store(
        jsonEncode({
          'unlshd': {'channel': 'release', 'variant': 'compact'},
        }),
      );

      await withController((fw) async {
        expect(fw.selectedVariant(unleashed), UnleashedVariant.compact);
      });
    });

    // The custom channel is the one the fallback treats as "nobody has chosen
    // yet", so a remembered choice of it has to be marked as a real choice or
    // it is silently replaced on every launch.
    test('a remembered custom channel is not overridden', () async {
      giveChannels(['release', 'development']);
      await store(
        jsonEncode({
          'unlshd': {'channel': kCustomFirmwareChannelId},
        }),
      );

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), kCustomFirmwareChannelId);
      });
    });

    test('a channel that no longer exists falls back', () async {
      giveChannels(['release']);
      await store(
        jsonEncode({
          'unlshd': {'channel': 'development'},
        }),
      );

      await withController((fw) async {
        expect(fw.selectedChannelId(unleashed), 'release');
      });
    });

    test('choosing a channel records it', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setChannel(unleashed, 'development');
        await pumpEventQueue();
      });

      expect(
        UpdateSettingsStore.instance.selectionFor('unlshd')?.channelId,
        'development',
      );
    });

    test('choosing a variant records it', () async {
      giveChannels(['release', 'development']);

      await withController((fw) async {
        fw.setChannel(unleashed, 'release');
        fw.setVariant(unleashed, UnleashedVariant.compact);
        await pumpEventQueue();
      });

      expect(
        UpdateSettingsStore.instance.selectionFor('unlshd')?.variant,
        UnleashedVariant.compact,
      );
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
    test('a choice made while the read is in flight wins', () async {
      giveChannels(['release', 'development']);
      await store(
        jsonEncode({
          'unlshd': {'channel': 'release'},
        }),
      );

      final fw = FirmwareController();
      fw.setChannel(unleashed, 'development');
      await pumpEventQueue();

      expect(fw.selectedChannelId(unleashed), 'development');
      fw.dispose();
    });
  });
}
