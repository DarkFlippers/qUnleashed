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

  /// Set once the controller is gone, so the stored-settings read - which is
  /// started in the constructor and cannot be cancelled - does not notify a
  /// disposed notifier. Leaving the devices page inside that window otherwise
  /// asserts in debug and profile builds.
  bool _disposed = false;

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
    selection.channelPicked = true;
    // The variant is deliberately left alone. selectedVariant already reports
    // the packaged one for a channel that has no variants, so overwriting it
    // here changed nothing on screen and only discarded what the user had
    // chosen - which then came back on the next launch, because the store
    // still held it.
    // Only the channel: the variant sitting in the selection may be a default
    // nobody chose, and writing it would make it look like one they did.
    unawaited(_settings.remember(entry.shortName, channelId: channelId));
    notifyListeners();
  }

  void setVariant(FirmwareEntry entry, UnleashedVariant variant) {
    final selection = _selectionFor(entry.shortName);
    selection.variant = variant;
    selection.variantPicked = true;
    unawaited(_settings.remember(entry.shortName, variant: variant));
    notifyListeners();
  }

  /// Applies the stored choices, then lets the fallback fill in the rest.
  ///
  /// [UpdateSettingsStore.load] handles its own failures, so a read that did
  /// not work leaves every selection unset and the fallback fills them in -
  /// which is where a first run starts from anyway.
  Future<void> _restore() async {
    await _settings.load();
    if (_disposed) return;
    for (final entry in config.firmwares) {
      final selection = _selectionFor(entry.shortName);
      // A tap that landed while this was reading wins, per field: the user is
      // looking at what they just chose, and replacing it under them would be
      // worse than forgetting it.
      if (!selection.channelPicked) {
        final channelId = _settings.channelFor(entry.shortName);
        if (channelId != null) {
          selection.channelId = channelId;
          // A stored choice is a user choice, so the fallback must not treat
          // it as an unpicked default and quietly move off the custom channel.
          selection.channelPicked = true;
        }
      }
      if (!selection.variantPicked) {
        // Assigned rather than ??=: the variant may already hold a default
        // that setChannel wrote when moving to a channel without variants, and
        // a stored choice should win over that.
        final variant = _settings.variantFor(entry.shortName);
        if (variant != null) selection.variant = variant;
      }
    }
    _applyFallbacks();
  }

  void _onRepoChanged() => _applyFallbacks();

  void _applyFallbacks() {
    for (final entry in config.firmwares) {
      _applyChannelFallback(entry);
    }
    notifyListeners();
  }

  void _applyChannelFallback(FirmwareEntry entry) {
    final selection = _selectionFor(entry.shortName);
    final directory = _repo.directoryFor(entry);
    // Nothing has been fetched yet, so the only channel on offer is the custom
    // one. A remembered channel cannot be checked against that, and replacing
    // it here is a decision the directory's arrival can never undo: the
    // replacement counts as picked, which is exactly what stops the clause
    // below from correcting it. The directory cache is in-memory only, so this
    // is every cold start, not an edge case.
    if (directory == null && selection.channelId != null) return;
    final channels = _channelsForDirectory(directory);
    final selected = selection.channelId;
    final match = _matchChannel(channels, selected);
    final hasReal = channels.any((c) => c.id != kCustomFirmwareChannelId);
    final needsFallback =
        match == null ||
        (!selection.channelPicked &&
            hasReal &&
            selected == kCustomFirmwareChannelId);
    if (!needsFallback) {
      // The feed renamed the channel the user picked. Keeping the choice under
      // the id the directory now uses means every later lookup finds it,
      // rather than the choice being quietly discarded on a rename.
      if (match.id != selected) selection.channelId = match.id;
      return;
    }

    final fallback = channels.firstWhere(
      (channel) => channel.id == 'release',
      orElse: () => channels.firstWhere(
        (c) => c.id != kCustomFirmwareChannelId,
        orElse: () => channels.first,
      ),
    );
    selection.channelId = fallback.id;
  }

  /// Finds [id] among [channels] the way the directory itself does - by the
  /// channel's aliases, not by an exact string match.
  static FirmwareDirectoryChannel? _matchChannel(
    List<FirmwareDirectoryChannel> channels,
    String? id,
  ) {
    if (id == null) return null;
    final normalized = FirmwareChannel.fromId(id);
    for (final channel in channels) {
      if (channel.id == id) return channel;
      if (normalized != null &&
          FirmwareChannel.fromId(channel.id) == normalized) {
        return channel;
      }
    }
    return null;
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
    _disposed = true;
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }
}

class _Selection {
  String? channelId;
  UnleashedVariant? variant;

  /// Tracked per field: a tap on one selector says nothing about the other,
  /// and treating it as though it did let a variant chosen mid-read be
  /// reverted on screen while still being written to disk.
  bool channelPicked = false;
  bool variantPicked = false;
}
