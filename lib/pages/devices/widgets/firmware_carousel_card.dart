import 'dart:async';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../models/firmware_config.dart';
import '../../../models/firmware_directory.dart';
import '../../../models/ofw_parser.dart';
import '../../../models/unleashed_parser.dart';
import '../../../theme.dart';
import '../../../widgets/device_shell.dart';
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

  final Map<String, FirmwareChannel> _channelByEntry = {};
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
    } catch (_) {
      dir = null;
    }
    if (!mounted) return;
    setState(() {
      _directories[entry.shortName] = dir;
      _fetching.remove(entry.shortName);
      _channelByEntry.putIfAbsent(entry.shortName, () => FirmwareChannel.release);
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

  FirmwareChannel _selectedChannel(FirmwareEntry entry) =>
      _channelByEntry[entry.shortName] ?? FirmwareChannel.release;

  UnleashedVariant _selectedVariant(FirmwareEntry entry) =>
      _variantByEntry[entry.shortName] ?? UnleashedVariant.base;

  bool _hasVariants(FirmwareEntry entry) => entry.shortName == 'unlshd';

  String? _latestVersionFor(FirmwareEntry entry) {
    final dir = _directories[entry.shortName];
    if (dir == null) return null;
    final ch = dir.channelById(_selectedChannel(entry).id);
    return ch?.latest?.version;
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

    final body = <Widget>[];

    if (config.isSingle) {
      body.add(_FirmwareSlide(
        entry: entry,
        fetchLoading: loading,
        latestVersion: latestVersion,
        channel: _selectedChannel(entry),
        variant: _selectedVariant(entry),
        showVariant: _hasVariants(entry),
        onChannelChanged: (c) =>
            setState(() => _channelByEntry[entry.shortName] = c),
        onVariantChanged: (v) =>
            setState(() => _variantByEntry[entry.shortName] = v),
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
                    channel: _selectedChannel(firmware),
                    variant: _selectedVariant(firmware),
                    showVariant: _hasVariants(firmware),
                    onChannelChanged: (c) =>
                        setState(() => _channelByEntry[firmware.shortName] = c),
                    onVariantChanged: (v) =>
                        setState(() => _variantByEntry[firmware.shortName] = v),
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

    body.add(FirmwareUpdateButton(
      key: ValueKey(
        '${entry.shortName}:${_selectedChannel(entry).id}:${_selectedVariant(entry).name}:${latestVersion ?? ''}:${widget.deviceVersion ?? ''}',
      ),
      entry: entry,
      fetchLoading: loading,
      latestVersion: latestVersion,
      deviceVersion: widget.deviceVersion,
      selectedChannel: _selectedChannel(entry),
      selectedVariant: _selectedVariant(entry),
      client: _client,
    ));

    return FlipperPageCard(
      title: 'Firmware Update',
      child: Column(children: body),
    );
  }
}

class _FirmwareSlide extends StatelessWidget {
  const _FirmwareSlide({
    required this.entry,
    required this.fetchLoading,
    required this.latestVersion,
    required this.channel,
    required this.variant,
    required this.showVariant,
    required this.onChannelChanged,
    required this.onVariantChanged,
  });

  final FirmwareEntry entry;
  final bool fetchLoading;
  final String? latestVersion;
  final FirmwareChannel channel;
  final UnleashedVariant variant;
  final bool showVariant;
  final ValueChanged<FirmwareChannel> onChannelChanged;
  final ValueChanged<UnleashedVariant> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
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
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MiniDropdown<FirmwareChannel>(
                  value: channel,
                  items: FirmwareChannel.values,
                  labelOf: _channelLabel,
                  accent: entry.colors.primary,
                  onChanged: onChannelChanged,
                ),
                if (showVariant) ...[
                  const SizedBox(height: 4),
                  _MiniDropdown<UnleashedVariant>(
                    value: variant,
                    items: UnleashedVariant.values,
                    labelOf: _variantLabel,
                    accent: entry.colors.primary,
                    onChanged: onVariantChanged,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _channelLabel(FirmwareChannel c) => switch (c) {
        FirmwareChannel.release => 'Release',
        FirmwareChannel.releaseCandidate => 'PreRelease',
        FirmwareChannel.development => 'Development',
      };

  static String _variantLabel(UnleashedVariant v) => switch (v) {
        UnleashedVariant.base => 'Default',
        UnleashedVariant.compact => 'Compact',
        UnleashedVariant.extraPacks => 'Extra',
      };
}

class _MiniDropdown<T> extends StatelessWidget {
  const _MiniDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.accent,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final Color accent;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: colors.textMuted),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child: Text(labelOf(v)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
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
