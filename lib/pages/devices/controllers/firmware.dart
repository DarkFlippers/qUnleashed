import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../components/config.dart';
import '../../../theme/theme.dart';
import '../firmware/directory.dart';
import '../firmware/repository.dart';
import '../firmware/update_settings.dart';

class FirmwareController extends ChangeNotifier {
  FirmwareController() {
    _repo.addListener(_onRepoChanged);
    unawaited(_restore());
    _repo.prefetchAll();
  }

  final FirmwareConfig config = QAppThemeController.instance.config;
  final FirmwareRepository _repo = FirmwareRepository.instance;
  final UpdateSettingsStore _settings = UpdateSettingsStore.instance;

  final Map<String, _Selection> _selections = {};

  bool fetchLoadingFor(FirmwareEntry entry) =>
      _repo.isLoading(entry) || _repo.directoryFor(entry) == null;

  List<FirmwareDirectoryChannel> channelsFor(FirmwareEntry entry) =>
      _channelsForDirectory(_repo.directoryFor(entry));

  String selectedChannelId(FirmwareEntry entry) {
    final selected = _selections[entry.shortName]?.channelId;
    if (selected != null && selected.isNotEmpty) return selected;
    return kCustomFirmwareChannelId;
  }

  UnleashedVariant selectedVariant(FirmwareEntry entry) =>
      _supportsVariantSelection(entry, selectedChannelId(entry))
      ? (_selections[entry.shortName]?.variant ?? UnleashedVariant.extraPacks)
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
    final dir = _repo.directoryFor(entry);
    return dir?.channelById(selectedChannelId(entry))?.latest?.version;
  }

  FirmwareVersion? latestFirmwareFor(FirmwareEntry entry) {
    final dir = _repo.directoryFor(entry);
    return dir?.channelById(selectedChannelId(entry))?.latest;
  }

  void ensureDirectory(FirmwareEntry entry) => _repo.ensure(entry);

  void setChannel(FirmwareEntry entry, String channelId) {
    final selection = _selectionFor(entry.shortName);
    selection.channelId = channelId;
    selection.userPicked = true;
    if (!_supportsVariantSelection(entry, channelId)) {
      selection.variant = UnleashedVariant.extraPacks;
    }
    _remember(entry);
    notifyListeners();
  }

  void setVariant(FirmwareEntry entry, UnleashedVariant variant) {
    _selectionFor(entry.shortName).variant = variant;
    _remember(entry);
    notifyListeners();
  }

  /// Records the choice for next time. [UpdateSettingsStore.remember] handles
  /// its own failures, so there is nothing here for a caller to answer.
  void _remember(FirmwareEntry entry) {
    final selection = _selectionFor(entry.shortName);
    unawaited(
      _settings.remember(
        entry.shortName,
        channelId: selection.channelId,
        variant: selection.variant,
      ),
    );
  }

  /// Applies the stored choices, then lets the fallback run for anything they
  /// did not cover.
  ///
  /// [UpdateSettingsStore.load] handles its own failures, so a read that did
  /// not work leaves every selection unset and the fallback below fills them
  /// in - which is the same place a first run starts from.
  Future<void> _restore() async {
    await _settings.load();
    for (final entry in config.firmwares) {
      final saved = _settings.selectionFor(entry.shortName);
      if (saved == null) continue;
      final selection = _selectionFor(entry.shortName);
      // A tap that landed while this was reading wins: the user is looking at
      // what they just chose, and replacing it under them would be worse than
      // forgetting it.
      if (selection.userPicked) continue;
      if (saved.channelId != null) {
        selection.channelId = saved.channelId;
        // A stored choice is a user choice, so the fallback must not treat it
        // as an unpicked default and quietly move off the custom channel.
        selection.userPicked = true;
      }
      if (saved.variant != null) selection.variant = saved.variant;
    }
    for (final entry in config.firmwares) {
      _applyChannelFallback(entry);
    }
    notifyListeners();
  }

  void _onRepoChanged() {
    for (final entry in config.firmwares) {
      _applyChannelFallback(entry);
    }
    notifyListeners();
  }

  void _applyChannelFallback(FirmwareEntry entry) {
    final selection = _selectionFor(entry.shortName);
    final channels = _channelsForDirectory(_repo.directoryFor(entry));
    final selected = selection.channelId;
    final hasReal = channels.any((c) => c.id != kCustomFirmwareChannelId);
    final needsFallback =
        selected == null ||
        !channels.any((channel) => channel.id == selected) ||
        (!selection.userPicked &&
            hasReal &&
            selected == kCustomFirmwareChannelId);
    if (!needsFallback) return;

    final fallback = channels.firstWhere(
      (channel) => channel.id == 'release',
      orElse: () => channels.firstWhere(
        (c) => c.id != kCustomFirmwareChannelId,
        orElse: () => channels.first,
      ),
    );
    selection.channelId = fallback.id;
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

  _Selection _selectionFor(String key) =>
      _selections.putIfAbsent(key, _Selection.new);

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }
}

class _Selection {
  String? channelId;
  UnleashedVariant? variant;
  bool userPicked = false;
}
