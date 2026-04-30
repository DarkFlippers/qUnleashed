import 'package:flutter/material.dart';

import '../../../models/firmware_config.dart';
import '../../../theme.dart';
import '../../../widgets/device_shell.dart';

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

  int _page = 0;
  FirmwareConfig? _config;
  final Map<String, FirmwareRelease?> _releaseCache = {};
  final Set<String> _fetching = {};

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

  void _ensureRelease(FirmwareEntry entry) {
    final url = entry.releaseUrl;
    if (_releaseCache.containsKey(url) || _fetching.contains(url)) return;
    _fetching.add(url);
    _fetchRelease(entry);
  }

  Future<void> _fetchRelease(FirmwareEntry entry) async {
    final release = await entry.fetchRelease();
    if (!mounted) return;
    setState(() {
      _releaseCache[entry.releaseUrl] = release;
      _fetching.remove(entry.releaseUrl);
    });
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    final config = _config;
    if (config == null || page >= config.firmwares.length) return;
    _themeController.setActiveFirmware(config.firmwares[page]);
    _ensureRelease(config.firmwares[page]);
  }

  void _syncPageToTheme(FirmwareConfig config) {
    if (config.firmwares.isEmpty) return;
    final active = _themeController.activeFirmware;
    final index = active == null
        ? 0
        : config.firmwares.indexWhere((entry) => entry.shortName == active.shortName);
    final targetPage = index < 0 ? 0 : index;
    _page = targetPage;
    _ensureRelease(config.firmwares[targetPage]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(targetPage);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final colors = context.appColors;

    if (config == null) {
      return const FlipperPageCard(title: 'Firmware Update', child: _LoadingRow());
    }
    if (config.firmwares.isEmpty) {
      return const SizedBox.shrink();
    }

    final entry = config.firmwares[_page.clamp(0, config.firmwares.length - 1)];
    final fetchLoading = !_releaseCache.containsKey(entry.releaseUrl);
    final latestVersion = _releaseCache[entry.releaseUrl]?.version;

    if (config.isSingle) {
      return FlipperPageCard(
        title: 'Firmware Update',
        child: Column(
          children: [
            _SingleChannelRow(
              entry: entry,
              fetchLoading: fetchLoading,
              latestVersion: latestVersion,
            ),
            Divider(height: 1, color: colors.divider),
            _FirmwareButton(
              fetchLoading: fetchLoading,
              latestVersion: latestVersion,
              deviceVersion: widget.deviceVersion,
            ),
          ],
        ),
      );
    }

    return FlipperPageCard(
      title: 'Firmware Update',
      child: Column(
        children: [
          SizedBox(
            height: 80,
            child: PageView.builder(
              controller: _controller,
              itemCount: config.firmwares.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) {
                final firmware = config.firmwares[i];
                final firmwareLoading = !_releaseCache.containsKey(firmware.releaseUrl);
                return _FirmwareSlide(
                  entry: firmware,
                  fetchLoading: firmwareLoading,
                  latestVersion: _releaseCache[firmware.releaseUrl]?.version,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(config.firmwares.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 5,
                  height: active ? 8 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? entry.colors.primary : colors.textMuted,
                  ),
                );
              }),
            ),
          ),
          _FirmwareButton(
            fetchLoading: fetchLoading,
            latestVersion: latestVersion,
            deviceVersion: widget.deviceVersion,
          ),
        ],
      ),
    );
  }
}

class _SingleChannelRow extends StatelessWidget {
  const _SingleChannelRow({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Update Channel',
              style: TextStyle(fontSize: 14, color: colors.textMuted),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: entry.colors.primary,
                ),
              ),
              Text(
                fetchLoading ? 'Checking…' : (latestVersion ?? '—'),
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(entry.assetPath, width: 62, height: 62, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
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

const _kFlipperBold = TextStyle(
  fontFamily: 'FlipperBold',
  fontSize: 40,
  fontWeight: FontWeight.w500,
);

class _FirmwareButton extends StatelessWidget {
  const _FirmwareButton({
    required this.fetchLoading,
    required this.latestVersion,
    required this.deviceVersion,
  });

  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;

  @override
  Widget build(BuildContext context) {
    final state = _resolve();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        children: [
          GestureDetector(
            onTap: state.enabled ? () {} : null,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: state.color,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                state.label,
                style: _kFlipperBold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              state.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: FlipperOriginalColors.text30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _ButtonState _resolve() {
    if (fetchLoading) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking for updates…',
        enabled: false,
      );
    }

    if (latestVersion == null) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Can\'t connect to update server',
        enabled: false,
      );
    }

    if (deviceVersion == null) {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description:
            'Firmware on Flipper doesn\'t match the selected update channel.\nSelected version will be installed.',
        enabled: true,
      );
    }

    if (deviceVersion == '-') {
      return _ButtonState(
        label: 'INSTALL',
        color: FlipperOriginalColors.accent,
        description: 'Checking device firmware version…',
        enabled: false,
      );
    }

    if (deviceVersion == latestVersion) {
      return _ButtonState(
        label: 'NO UPDATES',
        color: FlipperOriginalColors.text16,
        description: 'There are no updates in the selected channel',
        enabled: false,
      );
    }

    return _ButtonState(
      label: 'UPDATE',
      color: FlipperOriginalColors.green,
      description: 'Update Flipper to the latest version',
      enabled: true,
    );
  }
}

class _ButtonState {
  const _ButtonState({
    required this.label,
    required this.color,
    required this.description,
    required this.enabled,
  });

  final String label;
  final Color color;
  final String description;
  final bool enabled;
}
