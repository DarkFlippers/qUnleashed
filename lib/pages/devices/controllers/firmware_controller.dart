import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../config.dart';
import '../../../services/update/firmware_directory.dart';
import '../../../services/update/unleashed_parser.dart';
import '../../../services/update/update_service.dart';
import '../../../theme/theme.dart';
import '../firmware/firmware_source.dart';

class FirmwareController extends ChangeNotifier {
  FirmwareController() {
    _serviceSub = UpdateService.instance.onUpdated.listen(
      (_) => _reloadFromService(),
    );
  }

  final FirmwareConfig config = QAppThemeController.instance.config;

  final Map<String, _EntryState> _entries = {};
  StreamSubscription<void>? _serviceSub;
  bool _disposed = false;

  bool fetchLoadingFor(FirmwareEntry entry) {
    final state = _entries[entry.shortName];
    return state == null || state.fetching || !state.resolved;
  }

  List<FirmwareDirectoryChannel> channelsFor(FirmwareEntry entry) =>
      _channelsForDirectory(_entries[entry.shortName]?.directory);

  String selectedChannelId(FirmwareEntry entry) {
    final selected = _entries[entry.shortName]?.channelId;
    if (selected != null && selected.isNotEmpty) return selected;
    return kCustomFirmwareChannelId;
  }

  UnleashedVariant selectedVariant(FirmwareEntry entry) =>
      _supportsVariantSelection(entry, selectedChannelId(entry))
      ? (_entries[entry.shortName]?.variant ?? UnleashedVariant.extraPacks)
      : UnleashedVariant.extraPacks;

  bool hasVariants(FirmwareEntry entry) =>
      _supportsVariantSelection(entry, selectedChannelId(entry));

  String? latestVersionFor(FirmwareEntry entry) {
    final parser = parserForEntry(entry);
    if (entry.shortName == 'unlshd' && parser is UnleashedParser) {
      return parser.getDisplayVersion(
        selectedChannelId(entry),
        variant: selectedVariant(entry),
      );
    }
    final dir = _entries[entry.shortName]?.directory;
    return dir?.channelById(selectedChannelId(entry))?.latest?.version;
  }

  FirmwareVersion? latestFirmwareFor(FirmwareEntry entry) {
    final dir = _entries[entry.shortName]?.directory;
    return dir?.channelById(selectedChannelId(entry))?.latest;
  }

  void ensureDirectory(FirmwareEntry entry) {
    final state = _stateFor(entry.shortName);
    if (state.resolved || state.fetching) return;
    state.fetching = true;
    _fetchDirectory(entry);
  }

  void setChannel(FirmwareEntry entry, String channelId) {
    final state = _stateFor(entry.shortName);
    state.channelId = channelId;
    state.userPicked = true;
    if (!_supportsVariantSelection(entry, channelId)) {
      state.variant = UnleashedVariant.extraPacks;
    }
    _notify();
  }

  void setVariant(FirmwareEntry entry, UnleashedVariant variant) {
    _stateFor(entry.shortName).variant = variant;
    _notify();
  }

  Future<void> _fetchDirectory(FirmwareEntry entry) async {
    final key = entry.shortName;

    final cached = UpdateService.instance.directoryForSource(key);
    if (cached != null) {
      await Future<void>.value();
      if (_disposed) return;
      _setDirectory(key, cached);
      _cancelRetry(key);
      _notify();
      return;
    }

    await UpdateService.instance.checkIfNeeded();
    if (_disposed) return;

    final dir = UpdateService.instance.directoryForSource(key);
    if (dir != null) {
      final summary = dir.channels
          .map((ch) => '${ch.id}(${ch.title})')
          .join(', ');
      LogService.log('[FirmwareController] $key channels: $summary');
    }
    _setDirectory(key, dir);
    if (dir == null) {
      _scheduleRetry(entry);
    } else {
      _cancelRetry(key);
    }
    _notify();
  }

  void _reloadFromService() {
    if (_disposed) return;
    for (final entry in config.firmwares) {
      final dir = UpdateService.instance.directoryForSource(entry.shortName);
      if (dir != null) {
        _setDirectory(entry.shortName, dir);
        _cancelRetry(entry.shortName);
      }
    }
    _notify();
  }

  void _setDirectory(String key, FirmwareDirectory? dir) {
    final state = _stateFor(key);
    state.directory = dir;
    state.resolved = true;
    state.fetching = false;
    _applyChannelFallback(key, dir);
  }

  void _applyChannelFallback(String key, FirmwareDirectory? dir) {
    final state = _stateFor(key);
    final channels = _channelsForDirectory(dir);
    final selected = state.channelId;
    final hasReal = channels.any((c) => c.id != kCustomFirmwareChannelId);
    final needsFallback =
        selected == null ||
        !channels.any((channel) => channel.id == selected) ||
        (!state.userPicked && hasReal && selected == kCustomFirmwareChannelId);
    if (!needsFallback) return;

    final fallback = channels.firstWhere(
      (channel) => channel.id == 'release',
      orElse: () => channels.firstWhere(
        (c) => c.id != kCustomFirmwareChannelId,
        orElse: () => channels.first,
      ),
    );
    state.channelId = fallback.id;
  }

  List<FirmwareDirectoryChannel> _channelsForDirectory(FirmwareDirectory? dir) {
    final real = (dir?.channels ?? const <FirmwareDirectoryChannel>[])
        .where((channel) => channel.hasVersions)
        .toList();
    return [...real, buildCustomChannel()];
  }

  bool _supportsVariantSelection(FirmwareEntry entry, String channelId) {
    if (entry.shortName != 'unlshd') return false;
    final channel = FirmwareChannel.fromId(channelId);
    return channel == FirmwareChannel.release ||
        channel == FirmwareChannel.development;
  }

  void _scheduleRetry(FirmwareEntry entry) {
    final state = _stateFor(entry.shortName);
    if (state.retryTimer != null) return;
    state.retryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_disposed) {
        timer.cancel();
        state.retryTimer = null;
        return;
      }
      if (state.fetching) return;
      state.fetching = true;
      _fetchDirectory(entry);
    });
  }

  void _cancelRetry(String key) {
    final state = _entries[key];
    state?.retryTimer?.cancel();
    state?.retryTimer = null;
  }

  _EntryState _stateFor(String key) =>
      _entries.putIfAbsent(key, _EntryState.new);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _serviceSub?.cancel();
    for (final state in _entries.values) {
      state.retryTimer?.cancel();
    }
    super.dispose();
  }
}

class _EntryState {
  FirmwareDirectory? directory;
  bool resolved = false;
  bool fetching = false;
  String? channelId;
  UnleashedVariant? variant;
  bool userPicked = false;
  Timer? retryTimer;
}
