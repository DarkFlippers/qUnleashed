import 'dart:async';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../models/firmware_config.dart';
import '../models/firmware_directory.dart';
import '../models/ofw_parser.dart';
import '../models/unleashed_parser.dart';
import '../../../theme.dart';
import '../../../widgets/device_shell.dart';
import 'firmware_changelog_page.dart';
import 'firmware_update_button.dart';

class FirmwareCarouselCard extends StatefulWidget {
  const FirmwareCarouselCard({
    super.key,
    required this.deviceVersion,
  });

  final String? deviceVersion;

  @override
  State<FirmwareCarouselCard> createState() => _FirmwareCarouselCardState();
}

class _FirmwareCarouselCardState extends State<FirmwareCarouselCard> {
  final _controller = PageController();
  final _themeController = QAppThemeController.instance;
  final FlipperClient _client = FlipperOneClient().get();

  int _page = 0;
  FirmwareConfig? _config;

  final Map<String, FirmwareParser> _parsers = {};
  final Map<String, FirmwareDirectory?> _directories = {};
  final Set<String> _fetching = {};
  final Map<String, Timer> _retryTimers = {};

  final Map<String, String> _channelIdByEntry = {};
  final Map<String, UnleashedVariant> _variantByEntry = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      await _themeController.loadConfig();
      final config = _themeController.config ?? await FirmwareConfig.load();
      if (!mounted) return;
      setState(() => _config = config);
      if (config.firmwares.isNotEmpty) {
        _syncPageToTheme(config);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _config = const FirmwareConfig(firmwares: []));
      }
    }
  }

  @override
  void didUpdateWidget(covariant FirmwareCarouselCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final config = _config;
    if (config != null) {
      _syncPageToTheme(config);
    }
  }

  FirmwareParser _parserFor(FirmwareEntry entry) {
    return _parsers.putIfAbsent(entry.shortName, () {
      return switch (entry.shortName) {
        'ofw' => OfwParser.instance,
        'unlshd' => UnleashedParser.instance,
        _ => OfwParser.instance,
      };
    });
  }

  void _ensureDirectory(FirmwareEntry entry) {
    final key = entry.shortName;
    if (_directories.containsKey(key) || _fetching.contains(key)) return;
    _fetching.add(key);
    _fetchDirectory(entry);
  }

  void _scheduleRetry(FirmwareEntry entry) {
    final key = entry.shortName;
    if (_retryTimers.containsKey(key)) return;
    _retryTimers[key] = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        _retryTimers.remove(key);
        return;
      }
      if (_fetching.contains(key)) return;
      _fetching.add(key);
      _fetchDirectory(entry);
    });
  }

  void _cancelRetry(String key) {
    _retryTimers.remove(key)?.cancel();
  }

  Future<void> _fetchDirectory(FirmwareEntry entry) async {
    final parser = _parserFor(entry);
    FirmwareDirectory? dir;
    try {
      dir = await parser.fetch();
      final channelSummary = dir.channels
          .map((channel) => '${channel.id}(${channel.title})')
          .join(', ');
      LogService.log(
        '[FirmwareCarousel] ${entry.shortName} channels from ${parser.directoryUrl}: $channelSummary',
      );
    } catch (_) {
      dir = null;
    }
    if (!mounted) return;
    setState(() {
      _directories[entry.shortName] = dir;
      _fetching.remove(entry.shortName);
      final selectedChannelId = _channelIdByEntry[entry.shortName];
      final channels = _channelsForEntry(dir);
      if (selectedChannelId == null || !channels.any((channel) => channel.id == selectedChannelId)) {
        final fallbackChannel = channels.firstWhere(
          (channel) => channel.id == 'release',
          orElse: () => channels.first,
        );
        _channelIdByEntry[entry.shortName] = fallbackChannel.id;
      }
    });
    if (dir == null) {
      _scheduleRetry(entry);
    } else {
      _cancelRetry(entry.shortName);
    }
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    final config = _config;
    if (config == null || page >= config.firmwares.length) return;
    _themeController.setActiveFirmware(config.firmwares[page]);
    _ensureDirectory(config.firmwares[page]);
  }

  void _goToPage(int page) {
    final config = _config;
    if (config == null || config.firmwares.isEmpty) return;
    final targetPage = page.clamp(0, config.firmwares.length - 1);
    if (targetPage == _page) return;
    _controller.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncPageToTheme(FirmwareConfig config) {
    if (config.firmwares.isEmpty) return;
    final active = _themeController.activeFirmware;
    final index = active == null
        ? 0
        : config.firmwares.indexWhere((entry) => entry.shortName == active.shortName);
    final targetPage = index < 0 ? 0 : index;
    _page = targetPage;
    _themeController.setActiveFirmware(config.firmwares[targetPage]);
    _ensureDirectory(config.firmwares[targetPage]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(targetPage);
    });
  }

  String _selectedChannelId(FirmwareEntry entry) {
    final selected = _channelIdByEntry[entry.shortName];
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    final channels = _channelsFor(entry);
    if (channels.isEmpty) {
      return 'release';
    }
    final fallback = channels.firstWhere(
      (channel) => channel.id == 'release',
      orElse: () => channels.first,
    );
    return fallback.id;
  }

  UnleashedVariant _selectedVariant(FirmwareEntry entry) =>
      _supportsVariantSelection(entry, _selectedChannelId(entry))
          ? (_variantByEntry[entry.shortName] ?? UnleashedVariant.base)
          : UnleashedVariant.base;

  bool _hasVariants(FirmwareEntry entry) =>
      _supportsVariantSelection(entry, _selectedChannelId(entry));

  bool _supportsVariantSelection(FirmwareEntry entry, String channelId) {
    if (entry.shortName != 'unlshd') return false;
    return FirmwareChannel.fromId(channelId) == FirmwareChannel.release;
  }

  List<FirmwareDirectoryChannel> _channelsFor(FirmwareEntry entry) {
    final dir = _directories[entry.shortName];
    return _channelsForEntry(dir);
  }

  List<FirmwareDirectoryChannel> _channelsForEntry(FirmwareDirectory? dir) {
    return (dir?.channels ?? const <FirmwareDirectoryChannel>[])
        .where((channel) => channel.hasVersions)
        .toList();
  }

  String? _latestVersionFor(FirmwareEntry entry) {
    final dir = _directories[entry.shortName];
    if (dir == null) return null;
    final ch = dir.channelById(_selectedChannelId(entry));
    return ch?.latest?.version;
  }

  FirmwareVersion? _latestFirmwareFor(FirmwareEntry entry) {
    final dir = _directories[entry.shortName];
    if (dir == null) return null;
    return dir.channelById(_selectedChannelId(entry))?.latest;
  }

  @override
  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    if (config == null) {
      return const FlipperPageCard(title: 'Firmware Update', child: _LoadingRow());
    }
    if (config.firmwares.isEmpty) {
      return const SizedBox.shrink();
    }

    final entry = config.firmwares[_page.clamp(0, config.firmwares.length - 1)];
    final loading = _fetching.contains(entry.shortName) ||
        !_directories.containsKey(entry.shortName);
    final latestVersion = _latestVersionFor(entry);
    final latestFirmware = _latestFirmwareFor(entry);
    final hasChangelog = (latestFirmware?.changelog.trim().isNotEmpty ?? false);

    final body = <Widget>[];

    if (config.isSingle) {
      body.add(_FirmwareSlide(
        entry: entry,
        fetchLoading: loading,
        latestVersion: latestVersion,
      ));
    } else {
      body.add(SizedBox(
        height: 110,
        child: Row(
          children: [
            _CarouselNavButton(
              icon: Icons.chevron_left,
              enabled: _page > 0,
              onTap: () => _goToPage(_page - 1),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: config.firmwares.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, i) {
                  final firmware = config.firmwares[i];
                  return _FirmwareSlide(
                    entry: firmware,
                    fetchLoading: _fetching.contains(firmware.shortName) ||
                        !_directories.containsKey(firmware.shortName),
                    latestVersion: _latestVersionFor(firmware),
                  );
                },
              ),
            ),
            _CarouselNavButton(
              icon: Icons.chevron_right,
              enabled: _page < config.firmwares.length - 1,
              onTap: () => _goToPage(_page + 1),
            ),
          ],
        ),
      ));
    }

    body.add(
      _FirmwareControls(
        entry: entry,
        fetchLoading: loading,
        channelId: _selectedChannelId(entry),
        channels: _channelsFor(entry),
        variant: _selectedVariant(entry),
        showVariant: _hasVariants(entry),
        onChannelChanged: (channelId) => setState(() {
          _channelIdByEntry[entry.shortName] = channelId;
          if (!_supportsVariantSelection(entry, channelId)) {
            _variantByEntry[entry.shortName] = UnleashedVariant.base;
          }
        }),
        onVariantChanged: (v) => setState(() => _variantByEntry[entry.shortName] = v),
      ),
    );

    body.add(FirmwareUpdateButton(
      key: ValueKey(
        '${entry.shortName}:${_selectedChannelId(entry)}:${_selectedVariant(entry).name}:${latestVersion ?? ''}:${widget.deviceVersion ?? ''}',
      ),
      entry: entry,
      fetchLoading: loading,
      latestVersion: latestVersion,
      deviceVersion: widget.deviceVersion,
      selectedChannelId: _selectedChannelId(entry),
      selectedVariant: _selectedVariant(entry),
      client: _client,
    ));

    return FlipperPageCard(
      title: 'Firmware Update',
      trailing: hasChangelog
          ? _WhatsNewButton(
              onTap: () {
                if (latestFirmware == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FirmwareChangelogPage(
                      entry: entry,
                      version: latestFirmware,
                      changelog: latestFirmware.changelog,
                      fetchLoading: loading,
                      latestVersion: latestVersion,
                      deviceVersion: widget.deviceVersion,
                      selectedChannelId: _selectedChannelId(entry),
                      selectedVariant: _selectedVariant(entry),
                      client: _client,
                    ),
                  ),
                );
              },
            )
          : null,
      child: Column(children: body),
    );
  }
}

class _FirmwareSlide extends StatelessWidget {
  const _FirmwareSlide({
    required this.entry,
    required this.fetchLoading,
    required this.latestVersion,
  });

  final FirmwareEntry entry;
  final bool fetchLoading;
  final String? latestVersion;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(entry.assetPath, width: 62, height: 62, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: entry.colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fetchLoading ? 'Checking…' : (latestVersion ?? '—'),
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _variantLabel(UnleashedVariant v) => switch (v) {
        UnleashedVariant.base => 'Default',
        UnleashedVariant.compact => 'Compact',
        UnleashedVariant.extraPacks => 'Extra',
      };
}

class _FirmwareControls extends StatelessWidget {
  const _FirmwareControls({
    required this.entry,
    required this.fetchLoading,
    required this.channelId,
    required this.channels,
    required this.variant,
    required this.showVariant,
    required this.onChannelChanged,
    required this.onVariantChanged,
  });

  final FirmwareEntry entry;
  final bool fetchLoading;
  final String channelId;
  final List<FirmwareDirectoryChannel> channels;
  final UnleashedVariant variant;
  final bool showVariant;
  final ValueChanged<String> onChannelChanged;
  final ValueChanged<UnleashedVariant> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final selectedChannel = channels.isEmpty
        ? null
        : channels.firstWhere(
            (channel) => channel.id == channelId,
            orElse: () => channels.first,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      child: Column(
        children: [
          _SettingsDropdown<FirmwareDirectoryChannel>(
            title: 'Update Channel',
            value: selectedChannel,
            items: channels,
            labelOf: (channel) => channel.title,
            descriptionOf: (channel) => channel.description,
            accent: entry.colors.primary,
            placeholder: fetchLoading ? 'Loading…' : 'Unavailable',
            onChanged: (channel) => onChannelChanged(channel.id),
          ),
          if (showVariant) ...[
            const SizedBox(height: 8),
            _SettingsDropdown<UnleashedVariant>(
              title: 'Build Variant',
              value: variant,
              items: UnleashedVariant.values,
              labelOf: _FirmwareSlide._variantLabel,
              descriptionOf: (variant) => switch (variant) {
                UnleashedVariant.base => 'Only base apps',
                UnleashedVariant.compact => 'Firmware only, no apps',
                UnleashedVariant.extraPacks => 'Extended pack with many apps',
              },
              accent: entry.colors.primary,
              placeholder: 'Unavailable',
              onChanged: onVariantChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.descriptionOf,
    required this.accent,
    required this.placeholder,
    required this.onChanged,
  });

  final String title;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) descriptionOf;
  final Color accent;
  final String placeholder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: items.isEmpty ? null : () async {
                final selected = await showDialog<T>(
                  context: context,
                  builder: (context) {
                    return Dialog(
                      backgroundColor: colors.card,
                      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < items.length; i++) ...[
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(10),
                                            onTap: () => Navigator.of(context).pop(items[i]),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          labelOf(items[i]),
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w700,
                                                            color: items[i] == value
                                                                ? accent
                                                                : colors.textPrimary,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Text(
                                                          descriptionOf(items[i]),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: colors.textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Icon(
                                                    items[i] == value
                                                        ? Icons.radio_button_checked
                                                        : Icons.radio_button_off,
                                                    size: 18,
                                                    color: items[i] == value
                                                        ? accent
                                                        : colors.textMuted,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (i != items.length - 1)
                                          Divider(height: 1, color: colors.divider),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
                if (selected != null) {
                  onChanged(selected);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value == null ? placeholder : labelOf(value as T),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: value == null ? colors.textMuted : accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: value == null ? colors.textMuted : colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsNewButton extends StatelessWidget {
  const _WhatsNewButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.divider),
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 13,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'What\'s New',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselNavButton extends StatelessWidget {
  const _CarouselNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 28,
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
