// End-to-end test of the embedded VirtualFlipper: loads the real engine
// library over FFI, boots the real firmware, performs the expansion-protocol
// handshake through _VirtualFlipperTransport and runs live RPC (ping +
// device info) — the exact path the app takes when the user picks
// "VirtualFlipper" in the connection dialog.
//
// Runs on a macOS host with the flipengine build present; skipped elsewhere.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseDir = VirtualFlipperEngine.resolveBaseDir();

  test('VirtualFlipper: connect + RPC ping + device info', () async {
    if (baseDir == null || !Platform.isMacOS) {
      markTestSkipped('flipengine build not present');
      return;
    }

    // Work on throwaway copies of the images (APFS clones are instant and the
    // sd image stays sparse).
    final work = Directory.systemTemp.createTempSync('vflip');
    Directory('${work.path}/build').createSync();
    Directory('${work.path}/assets').createSync();
    Link(
      '${work.path}/build/libflipengine_engine.dylib',
    ).createSync('$baseDir/build/libflipengine_engine.dylib');
    for (final img in ['flash.img', 'sdcard.img']) {
      final rc = Process.runSync('cp', [
        '-c',
        '$baseDir/assets/$img',
        '${work.path}/assets/$img',
      ]);
      expect(rc.exitCode, 0, reason: 'cp -c $img: ${rc.stderr}');
    }
    VirtualFlipperEngine.overrideBaseDir = work.path;

    final client = FlipperClient();
    final device = FlipperDevice(
      id: 'virtual-flipper',
      name: 'VirtualFlipper',
      link: FlipperLink.virtual,
      source: const VirtualFlipperDiscoveredDevice(),
    );

    await client.connect(device);
    expect(client.isConnected, isTrue);
    expect(client.mode, FlipperMode.rpc);

    final ping = await client.ping(PingRequest(data: [1, 2, 3, 4]));
    expect(ping.items, isNotEmpty);
    expect(ping.items.first.data, [1, 2, 3, 4]);

    final info = await client.awaitDeviceInfo();
    expect(info, isNotEmpty);
    // The firmware reports itself — proof the RPC session is the real thing.
    expect(info.keys.join(','), contains('hardware'));
    // ignore: avoid_print
    print(
      '[test] device info: '
      'name=${info['hardware_name']} fw=${info['firmware_version']} '
      '(${info.length} keys)',
    );

    await client.disconnect();
    expect(client.isConnected, isFalse);

    // Reconnect: the firmware's expansion worker must have re-armed detection.
    await client.connect(device);
    expect(client.isConnected, isTrue);
    final ping2 = await client.ping(PingRequest(data: [9, 9]));
    expect(ping2.items.first.data, [9, 9]);
    await client.disconnect();

    VirtualFlipperEngine.instance.shutdown();
  });
}
