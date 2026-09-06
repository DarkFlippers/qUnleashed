import 'dart:async';
// The protobuf bindings export their own DateTime, so the core one is reached
// through a prefix; the plain import keeps the rest of dart:core unprefixed.
import 'dart:core';
import 'dart:core' as core;

import 'package:flipperlib/flipperlib.dart';

import '../../components/format.dart';
import '../logging.dart';
import 'device_settings.dart';

/// Background device-info collection cycle: an initial burst of info requests
/// followed by periodic battery polling and reactive storage refresh.
///
/// Safe to call [start] multiple times — each call cancels the previous cycle
/// via the generation counter. The cycle binds to the device that is connected
/// at start time and dies as soon as it stops being the active one (an
/// activation swap restarts collection for the new device).
class DeviceInfoWatchService {
  DeviceInfoWatchService._();

  static final DeviceInfoWatchService instance = DeviceInfoWatchService._();

  int _gen = 0;
  int _freezeCount = 0;

  void start(FlipperClient client) {
    final gen = ++_gen;
    unawaited(_runCollection(gen, client));
  }

  void stop() {
    _gen++;
  }

  void freeze() => _freezeCount++;

  void unfreeze() {
    if (_freezeCount > 0) _freezeCount--;
  }

  Future<void> _runCollection(int gen, FlipperClient client) async {
    final device = client.connectedDevice;
    if (device == null) return;

    bool alive() =>
        gen == _gen &&
        client.isConnected &&
        identical(client.connectedDevice, device);

    void emit(Map<String, String> data) {
      if (!alive()) return;
      client.publishDeviceInfoPatch(data);
    }

    // Phase 1: initial burst

    final infoWasFetched = client.deviceInfoFetched;

    // Device info is requested automatically on entering RPC mode. Individual
    // fields are emitted as they arrive; wait for the complete snapshot before
    // queueing lower-priority requests.
    try {
      await client.awaitDeviceInfo().timeout(const Duration(seconds: 20));
    } catch (e) {
      LogService.log('[watchInfo] device info: $e');
    }
    if (!alive()) return;

    // A completed request publishes its snapshot itself. Re-emit only when
    // collection starts after that broadcast was missed.
    if (infoWasFetched) {
      final cached = Map<String, String>.from(client.deviceInfoCache);
      if (cached.isNotEmpty) emit(cached);
    }
    if (!alive()) return;

    // Battery (full)
    try {
      final batch = await client.powerInfo(
        priority: FlipperRequestPriority.background,
      );
      emit({for (final item in batch.items) 'power.${item.key}': item.value});
    } catch (e) {
      LogService.log('[watchInfo] battery initial: $e');
    }
    if (!alive()) return;

    // Protobuf version
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!alive()) return;
    try {
      final v = await client.protobufVersion(
        timeout: const Duration(seconds: 15),
      );
      final major = v.single.major;
      final minor = v.single.minor;
      emit({
        'protobuf_version': '$major.$minor',
        'protobuf_version_major': '$major',
        'protobuf_version_minor': '$minor',
      });
    } catch (e) {
      LogService.log('[watchInfo] protobuf: $e');
    }
    if (!alive()) return;

    // DateTime
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!alive()) return;
    try {
      final response = await client.getDateTime(
        timeout: const Duration(seconds: 15),
      );
      final dt = response.single.datetime;
      emit({
        'datetime':
            '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
            '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}',
      });
    } catch (e) {
      LogService.log('[watchInfo] datetime: $e');
    }
    if (!alive()) return;

    // Storage /ext — staggered so battery enters RPC queue first. This is the
    // only unconditional storage-info fetch; afterwards it refreshes purely
    // reactively (see phase 2).
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!alive()) return;
    Future<void> fetchExtInfo(String stage) async {
      try {
        final response = await client.storageInfo(
          InfoRequest(path: '/ext/'),
          priority: FlipperRequestPriority.background,
        );
        final extData = _storageResponseToMap(
          response.single,
          'storage.sdcard',
        );
        if (extData.isNotEmpty) emit(extData);
      } catch (e) {
        LogService.log('[watchInfo] storage /ext $stage: $e');
      }
    }

    await fetchExtInfo('initial');
    if (!alive()) return;

    // Storage /int — slow (storageDu), fire-and-forget so periodic loop starts
    unawaited(() async {
      if (!alive()) return;
      try {
        final bytes = await client.storageDu(
          '/int',
          priority: FlipperRequestPriority.background,
        );
        if (alive()) {
          emit({
            'storage.internal.used_bytes': '$bytes',
            'storage.internal.used': _formatBytes(bytes),
          });
        }
      } catch (e) {
        LogService.log('[watchInfo] storage /int: $e');
      }
    }());

    // The last of the startup commands: the phone's clock goes to the device,
    // so a Flipper that lost its time comes back right after connecting.
    await DeviceSettings.instance.load();
    if (!alive()) return;
    if (DeviceSettings.instance.syncTimeOnStart) {
      final now = core.DateTime.now();
      try {
        await client.setDateTime(
          SetDateTimeRequest(
            datetime: DateTime(
              hour: now.hour,
              minute: now.minute,
              second: now.second,
              day: now.day,
              month: now.month,
              year: now.year,
              weekday: now.weekday,
            ),
          ),
          timeout: const Duration(seconds: 15),
        );
        emit({
          'datetime':
              '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
              '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}',
        });
      } catch (e) {
        LogService.log('[watchInfo] set datetime: $e');
      }
      if (!alive()) return;
    }

    // Phase 2: periodic battery poll + reactive storage refresh.
    //
    // Storage info is never polled on a timer after the phase-1 snapshot: it
    // refreshes only in response to completed mutating storage operations
    // (client.storageMutations), debounced and rate-limited:
    //  - the refresh runs 1 s after the last completion, so a burst of
    //    operations (e.g. write + delete + rename of a safe replace)
    //    produces exactly one refresh;
    //  - refreshes are at least 5 s apart;
    //  - nothing is sent while another storage RPC is in flight — the timer
    //    just re-checks later instead of queueing behind a long transfer.
    const storageQuietDelay = Duration(seconds: 1);
    const storageMinInterval = Duration(seconds: 5);
    // (Stopwatch, not DateTime: the protobuf bindings shadow dart:core
    // DateTime.)
    final clock = Stopwatch()..start();
    Duration? lastRefreshAt;
    Timer? refreshTimer;

    void scheduleStorageRefresh() {
      if (!alive()) return;
      var delay = storageQuietDelay;
      final last = lastRefreshAt;
      if (last != null) {
        final untilAllowed = last + storageMinInterval - clock.elapsed;
        if (untilAllowed > delay) delay = untilAllowed;
      }
      refreshTimer?.cancel();
      refreshTimer = Timer(delay, () {
        if (!alive()) return;
        if (_freezeCount > 0 ||
            client.storageBusy ||
            client.mode != FlipperMode.rpc ||
            client.cliExclusive) {
          // The link is occupied; check again after another quiet window.
          scheduleStorageRefresh();
          return;
        }
        lastRefreshAt = clock.elapsed;
        unawaited(fetchExtInfo('refresh'));
      });
    }

    final mutationSub = client.storageMutations.listen(
      (_) => scheduleStorageRefresh(),
    );

    var tick = 0;
    const interval = Duration(seconds: 5);
    const fullEvery = 12;

    try {
      while (alive()) {
        await Future<void>.delayed(interval);
        if (!alive()) break;
        if (_freezeCount > 0) continue;
        // A CLI session owns the transport: polling would only throw
        // "RPC switch blocked" every tick and spam the log. Skip quietly and
        // resume once the client is back in RPC mode.
        if (client.mode != FlipperMode.rpc || client.cliExclusive) continue;
        // Frozen while storage operations run: a battery poll queued behind
        // a long transfer would only time out and spam errors.
        if (client.storageBusy) continue;
        tick++;

        if (tick % fullEvery == 0) {
          try {
            final batch = await client.powerInfo(
              priority: FlipperRequestPriority.background,
            );
            emit({
              for (final item in batch.items) 'power.${item.key}': item.value,
            });
          } catch (e) {
            LogService.log('[watchInfo] battery full: $e');
            if (!alive()) break;
          }
        } else {
          try {
            final batch = await client.propertyGet(
              GetRequest(key: 'pwrinfo.battery.current'),
              priority: FlipperRequestPriority.background,
            );
            final partial = {
              for (final item in batch.items)
                'power.${item.key.replaceAll('.', '_')}': item.value,
            };
            if (partial.isNotEmpty) emit(partial);
          } catch (e) {
            LogService.log('[watchInfo] battery current: $e');
            if (!alive()) break;
          }
        }
      }
    } finally {
      refreshTimer?.cancel();
      await mutationSub.cancel();
    }
  }
}

Map<String, String> _storageResponseToMap(
  InfoResponse response,
  String prefix,
) {
  final total = response.totalSpace.toInt();
  final free = response.freeSpace.toInt();
  final used = total >= free ? total - free : 0;

  return {
    '$prefix.total': _formatBytes(total),
    '$prefix.free': _formatBytes(free),
    '$prefix.used': _formatBytes(used),
    '$prefix.free_percent': _formatPercent(free, total),
    '$prefix.used_percent': _formatPercent(used, total),
    '$prefix.total_bytes': '$total',
    '$prefix.available_bytes': '$free',
    '$prefix.used_bytes': '$used',
  };
}

String _formatBytes(int bytes) =>
    formatBytesScaled(bytes, maxUnit: 4, coarseAt: 100);

String _formatPercent(int value, int total) {
  if (total <= 0) return '0%';
  return '${(value * 100 / total).toStringAsFixed(1)}%';
}

String _pad(int n) => n.toString().padLeft(2, '0');
