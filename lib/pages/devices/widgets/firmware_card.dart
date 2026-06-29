import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../config.dart';
import '../../../theme/theme.dart';
import '../../../widgets/page_card.dart';
import '../controllers/firmware.dart';
import '../device_scope.dart';
import '../firmware/directory.dart';
import 'firmware_changelog_page.dart';
import 'firmware_update_button.dart';

class FirmwareCard extends StatefulWidget {
  const FirmwareCard({
    super.key,
    required this.deviceVersion,
    required this.deviceInfo,
  });

  final String? deviceVersion;
  final Map<String, String> deviceInfo;

  @override
  State<FirmwareCard> createState() => _FirmwareCardState();
}

class _FirmwareCardState extends State<FirmwareCard> {
  final _pageController = PageController();
  final _themeController = QAppThemeController.instance;
  final FlipperClient _client = FlipperOneClient().get();
  late final FirmwareController _fw;

  int _page = 0;

  @override
  void initState() {
    super.initState();
    _fw = FirmwareController()..addListener(_onChanged);
    _syncPageToTheme();
  }

  @override
  void didUpdateWidget(covariant FirmwareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPageToTheme();
  }

  @override
  void dispose() {
    _fw.removeListener(_onChanged);
    _fw.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _syncPageToTheme() {
    final config = _fw.config;
    if (config.firmwares.isEmpty) return;
    final active = _themeController.activeFirmware;
    final index = config.firmwares.indexWhere(
      (entry) => entry.shortName == active.shortName,
    );
    final target = index < 0 ? 0 : index;
    _page = target;
    _themeController.setActiveFirmware(config.firmwares[target]);
    _fw.ensureDirectory(config.firmwares[target]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(target);
    });
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    final config = _fw.config;
    if (page >= config.firmwares.length) return;
    _themeController.setActiveFirmware(config.firmwares[page]);
    _fw.ensureDirectory(config.firmwares[page]);
  }

  void _goToPage(int page) {
    final config = _fw.config;
    if (config.firmwares.isEmpty) return;
    final target = page.clamp(0, config.firmwares.length - 1);
    if (target == _page) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _openChangelog(FirmwareEntry entry, FirmwareVersion version) {
    final device = DeviceScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceScope(
          notifier: device,
          child: FirmwareChangelogPage(
            entry: entry,
            version: version,
            changelog: version.changelog,
            fetchLoading: _fw.fetchLoadingFor(entry),
            latestVersion: _fw.latestVersionFor(entry),
            deviceVersion: widget.deviceVersion,
            deviceInfo: widget.deviceInfo,
            selectedChannelId: _fw.selectedChannelId(entry),
            selectedVariant: _fw.selectedVariant(entry),
            client: _client,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _fw.config;
    if (config.firmwares.isEmpty) return const SizedBox.shrink();

    final entry = config.firmwares[_page.clamp(0, config.firmwares.length - 1)];
    final loading = _fw.fetchLoadingFor(entry);
    final latestVersion = _fw.latestVersionFor(entry);
    final latestFirmware = _fw.latestFirmwareFor(entry);
    final hasChangelog = latestFirmware?.changelog.trim().isNotEmpty ?? false;

    return FlipperPageCard(
      title: 'Firmware Update',
      trailing: hasChangelog
          ? _WhatsNewButton(
              onTap: () {
                if (latestFirmware != null)
                  _openChangelog(entry, latestFirmware);
              },
            )
          : null,
      child: Column(
        children: [
          if (config.isSingle)
            _FirmwareSlide(
              entry: entry,
              fetchLoading: loading,
              latestVersion: latestVersion,
            )
          else
            _carousel(config),
          _FirmwareControls(
            entry: entry,
            fetchLoading: loading,
            channelId: _fw.selectedChannelId(entry),
            channels: _fw.channelsFor(entry),
            variant: _fw.selectedVariant(entry),
            showVariant: _fw.hasVariants(entry),
            onChannelChanged: (channelId) => _fw.setChannel(entry, channelId),
            onVariantChanged: (variant) => _fw.setVariant(entry, variant),
          ),
          FirmwareUpdateButton(
            key: ValueKey(
              '${entry.shortName}:${_fw.selectedChannelId(entry)}:'
              '${_fw.selectedVariant(entry).name}:${latestVersion ?? ''}:'
              '${widget.deviceVersion ?? ''}',
            ),
            entry: entry,
            fetchLoading: loading,
            latestVersion: latestVersion,
            deviceVersion: widget.deviceVersion,
            deviceInfo: widget.deviceInfo,
            selectedChannelId: _fw.selectedChannelId(entry),
            selectedVariant: _fw.selectedVariant(entry),
            client: _client,
          ),
        ],
      ),
    );
  }

  Widget _carousel(FirmwareConfig config) {
    return SizedBox(
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
              controller: _pageController,
              itemCount: config.firmwares.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) {
                final firmware = config.firmwares[i];
                return _FirmwareSlide(
                  entry: firmware,
                  fetchLoading: _fw.fetchLoadingFor(firmware),
                  latestVersion: _fw.latestVersionFor(firmware),
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
            child: Image.asset(
              entry.assetPath,
              width: 62,
              height: 62,
              fit: BoxFit.cover,
            ),
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
                    color: colors.accent,
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
    final accent = context.appColors.accent;
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
            accent: accent,
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
              accent: accent,
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
              onTap: items.isEmpty ? null : () => _showPicker(context, colors),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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
                      color: value == null
                          ? colors.textMuted
                          : colors.textSecondary,
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

  Future<void> _showPicker(BuildContext context, QAppColors colors) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: colors.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                          _option(context, colors, items[i]),
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
      ),
    );
    if (selected != null) onChanged(selected);
  }

  Widget _option(BuildContext context, QAppColors colors, T item) {
    final selected = item == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).pop(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labelOf(item),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? accent : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descriptionOf(item),
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
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? accent : colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatsNewButton extends StatelessWidget {
  const _WhatsNewButton({required this.onTap});

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
              Icon(Icons.error_outline, size: 13, color: colors.textSecondary),
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
