import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../models/firmware_config.dart';
import '../../../models/firmware_directory.dart';
import '../../../models/firmware_updater.dart';
import '../../../models/ofw_parser.dart';
import '../../../models/unleashed_parser.dart';
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
  final FlipperClient _client = FlipperOneClient().get();

  int _page = 0;
  FirmwareConfig? _config;

  final Map<String, FirmwareParser> _parsers = {};
  final Map<String, FirmwareDirectory?> _directories = {};
  final Set<String> _fetching = {};

  final Map<String, FirmwareChannel> _channelByEntry = {};

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
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    final config = _config;
    if (config == null || page >= config.firmwares.length) return;
    _themeController.setActiveFirmware(config.firmwares[page]);
    _ensureDirectory(config.firmwares[page]);
  }

  void _syncPageToTheme(FirmwareConfig config) {
    if (config.firmwares.isEmpty) return;
    final active = _themeController.activeFirmware;
    final index = active == null
        ? 0
        : config.firmwares.indexWhere((entry) => entry.shortName == active.shortName);
    final targetPage = index < 0 ? 0 : index;
    _page = targetPage;
    _ensureDirectory(config.firmwares[targetPage]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpToPage(targetPage);
    });
  }

  FirmwareChannel _selectedChannel(FirmwareEntry entry) =>
      _channelByEntry[entry.shortName] ?? FirmwareChannel.release;

  String? _latestVersionFor(FirmwareEntry entry) {
    final dir = _directories[entry.shortName];
    if (dir == null) return null;
    final ch = dir.channelById(_selectedChannel(entry).id);
    return ch?.latest?.version;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startUpdate(FirmwareEntry entry) async {
    if (!_client.isConnected) {
      _toast('Connect a Flipper first');
      return;
    }
    final dir = _directories[entry.shortName];
    if (dir == null) {
      _toast('Update directory not loaded');
      return;
    }

    final channel = _selectedChannel(entry);
    final parser = _parserFor(entry);

    final controller = ValueNotifier<UpdateState>(const UpdateFetching());
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateProgressDialog(controller: controller),
    );

    try {
      final version = parser.getLatestVersion(channel);
      final pkg = version?.updatePackageFor('f7');
      if (pkg == null) {
        controller.value = UpdateError('No build for ${channel.displayName}');
        return;
      }

      await FirmwareUpdater.install(
        entry: entry,
        channel: channel,
        client: _client,
        onState: (state) {
          controller.value = state;
        },
      );
    } catch (e) {
      controller.value = UpdateError(e.toString());
    } finally {
      await dialogFuture;
      controller.dispose();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    final loading = _fetching.contains(entry.shortName) ||
        !_directories.containsKey(entry.shortName);
    final latestVersion = _latestVersionFor(entry);

    final body = <Widget>[];

    if (config.isSingle) {
      body.add(_SingleChannelRow(
        entry: entry,
        fetchLoading: loading,
        latestVersion: latestVersion,
      ));
      body.add(Divider(height: 1, color: colors.divider));
    } else {
      body.add(SizedBox(
        height: 80,
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
      ));
      body.add(Padding(
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
      ));
    }

    body.add(_ChannelSelector(
      value: _selectedChannel(entry),
      accent: entry.colors.primary,
      onChanged: (c) => setState(() => _channelByEntry[entry.shortName] = c),
    ));

    body.add(_FirmwareButton(
      fetchLoading: loading,
      latestVersion: latestVersion,
      deviceVersion: widget.deviceVersion,
      onTap: () => _startUpdate(entry),
    ));

    return FlipperPageCard(
      title: 'Firmware Update',
      child: Column(children: body),
    );
  }
}

class _ChannelSelector extends StatelessWidget {
  const _ChannelSelector({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final FirmwareChannel value;
  final Color accent;
  final ValueChanged<FirmwareChannel> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text('Channel', style: TextStyle(fontSize: 13, color: colors.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: FirmwareChannel.values.map((c) {
                final selected = c == value;
                return _Chip(
                  label: _channelShort(c),
                  selected: selected,
                  accent: accent,
                  onTap: () => onChanged(c),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static String _channelShort(FirmwareChannel c) => switch (c) {
        FirmwareChannel.release => 'Release',
        FirmwareChannel.releaseCandidate => 'RC',
        FirmwareChannel.development => 'Dev',
      };
}


class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? accent : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : colors.textMuted,
          ),
        ),
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
    required this.onTap,
  });

  final bool fetchLoading;
  final String? latestVersion;
  final String? deviceVersion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = _resolve();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        children: [
          GestureDetector(
            onTap: state.enabled ? onTap : null,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: state.color,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(state.label, style: _kFlipperBold),
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

class _UpdateProgressDialog extends StatelessWidget {
  const _UpdateProgressDialog({required this.controller});

  final ValueNotifier<UpdateState> controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final done = state is UpdateDone || state is UpdateError;
        final (title, body, progress) = _describe(state);
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(body),
              const SizedBox(height: 12),
              if (progress != null)
                LinearProgressIndicator(value: progress)
              else if (!done)
                const LinearProgressIndicator(),
            ],
          ),
          actions: [
            if (done)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
          ],
        );
      },
    );
  }

  (String, String, double?) _describe(UpdateState state) => switch (state) {
        UpdateIdle() => ('Update', 'Idle', null),
        UpdateFetching() => ('Update', 'Fetching directory…', null),
        UpdateDownloading(:final progress) =>
          ('Update', 'Downloading firmware…', progress),
        UpdateUploading(:final progress) =>
          ('Update', 'Uploading to Flipper…', progress),
        UpdateStarting() =>
          ('Update', 'Starting updater on Flipper…', null),
        UpdateDone() => (
            'Update started',
            'Flipper will reboot and apply the update.',
            1.0,
          ),
        UpdateError(:final message) => ('Error', message, null),
      };
}
