import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../services/notifications/push_intent.dart';
import '../../../services/notifications/push_service.dart';
import '../../../components/config.dart';
import '../../../theme/theme.dart';
import 'page_card.dart';
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
  FirmwareEntry? _pendingChangelog;

  /// Whether the theme's active firmware is one this card can show.
  ///
  /// Only false where `setActiveFirmware`'s assert is compiled out, which is
  /// every build but debug - so this and the fallback in [_themePage] are
  /// repairs a test cannot reach, and the test that the assert fires is what
  /// stands in for them.
  bool get _themeIsShowable => _fw.config.firmwares.any(
    (e) => e.shortName == _themeController.activeFirmware.shortName,
  );

  /// The page holding the firmware the theme controller calls active.
  ///
  /// Both writers pick out of the same config this reads, and
  /// `setActiveFirmware` asserts it - but an assert is compiled out of a
  /// release build, so the fallback stays and says so. A miss means something
  /// wrote an entry from outside the config, which is the most diagnostic
  /// single fact this can report, and page 0 is the only answer left.
  ///
  /// Not covered by a test, for the reason on [_themeIsShowable].
  int get _themePage {
    final name = _themeController.activeFirmware.shortName;
    final index = _fw.config.firmwares.indexWhere((e) => e.shortName == name);
    if (index < 0) {
      LogService.error(
        '[FirmwareCard] active firmware "$name" is not in the config '
        '(${_fw.config.firmwares.map((e) => e.shortName).join(', ')}); '
        'showing the first page',
      );
      return 0;
    }
    return index;
  }

  @override
  void initState() {
    super.initState();
    _fw = FirmwareController()..addListener(_onChanged);
    if (_fw.config.firmwares.isNotEmpty) {
      _page = _themePage;
      // A no-op on every normal launch: [_themePage] was derived from the
      // active firmware, so `setActiveFirmware` gets the value it already
      // holds and returns without notifying. It is here for the case
      // [_themePage] logs - an active firmware outside the config, where this
      // is the only thing that puts the theme back on one the card can show.
      _followPage(_page);
      // A no-op at a cold start: the active firmware is not persisted, so it
      // is page 0 here, and the shell builds this card once. Kept because the
      // page comes from [_themePage] rather than from the controller's
      // initial page, so a mount onto a theme that has already moved needs
      // this to bring the view across.
      //
      // The listener goes on after all of this, because in the off-list case
      // [_followPage] is the one call here that notifies.
      _jumpTo(_page);
    }
    _themeController.addListener(_onThemeChanged);
    PushService.instance.taps.addListener(_onPushTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPushTap());
  }

  @override
  void dispose() {
    PushService.instance.taps.removeListener(_onPushTap);
    _themeController.removeListener(_onThemeChanged);
    _fw.removeListener(_onChanged);
    _fw.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Follows the active firmware when something else moves it.
  ///
  /// This replaced a call from `didUpdateWidget`, which the parent supplies a
  /// new widget for on every rebuild - and `DeviceScope` is an
  /// `InheritedNotifier` driven by a five-second battery poll, so it ran
  /// twelve times a minute with a device connected. Each run called
  /// `ensureDirectory`, which is free while the directory is fresh but is a
  /// fresh request once a failed fetch has left nothing cached; and each run
  /// scheduled a `jumpToPage`, which cut off the 220ms `animateToPage` the
  /// carousel arrows start. #135.
  ///
  /// The controller notifies for the theme mode too, and for a platform
  /// brightness change while the mode is `system`, so this compares before
  /// acting rather than syncing on every notify.
  void _onThemeChanged() {
    if (_fw.config.firmwares.isEmpty) return;
    final target = _themePage;
    // The page match is not enough on its own: an off-list firmware resolves
    // to page 0, so with the card already there, returning here would skip
    // the one thing that puts the theme back - and [_themePage] would say so
    // again on every later notify instead of once.
    if (target == _page && _themeIsShowable) return;
    // Through setState, because nothing else is going to rebuild for this -
    // the call it replaced was part of the parent's own rebuild and got one
    // for free.
    setState(() => _page = target);
    _followPage(target);
    _jumpTo(target);
  }

  void _onChanged() {
    if (mounted) setState(() {});
    _tryOpenPendingChangelog();
  }

  void _onPushTap() {
    final intent = PushService.instance.taps.value;
    if (!mounted || intent == null || intent.type != PushIntent.typeFirmware) {
      return;
    }
    final firmwares = _fw.config.firmwares;
    final index = firmwares.indexWhere((e) => e.shortName == intent.entry);
    if (index < 0) {
      // Consumed rather than left pending, so it cannot be retried on every
      // later notify - but said out loud, because a name this build does not
      // carry means the push backend and a shipped client disagree, and that
      // is undiagnosable from a bug report without this line.
      LogService.warn(
        '[FirmwareCard] push names an unknown firmware "${intent.entry}"; '
        'this build has ${firmwares.map((e) => e.shortName).join(', ')}',
      );
      PushService.instance.taps.value = null;
      return;
    }
    // The same three steps as every move the code initiates - _onPageChanged
    // skips the jump, because there the view is what moved. Inlining the
    // middle one and letting the theme notify supply the rest worked only
    // while `_page` was stale, which is not a property a caller should have
    // to preserve.
    setState(() => _page = index);
    _followPage(index);
    _jumpTo(index);
    final entry = firmwares[index];
    final channel = intent.channel;
    if (channel != null && _fw.selectedChannelId(entry) != channel) {
      _fw.setChannel(entry, channel);
    }
    final superseded = _pendingChangelog;
    if (superseded != null && superseded.shortName != entry.shortName) {
      // The other two ways a tap ends without a changelog both say so; this
      // one is a tap still waiting for its directory when a second arrived.
      LogService.warn(
        '[FirmwareCard] push tap for ${superseded.shortName} superseded by '
        '${entry.shortName} before its directory landed',
      );
    }
    _pendingChangelog = entry;
    _tryOpenPendingChangelog();
  }

  void _tryOpenPendingChangelog() {
    final entry = _pendingChangelog;
    final state = entry == null
        ? FirmwareFetchState.loading
        : _fw.fetchStateFor(entry);
    if (entry == null || !mounted || state.isLoading) return;
    final version = _fw.latestFirmwareFor(entry);
    final failed = state.hasFailed;
    _pendingChangelog = null;
    PushService.instance.taps.value = null;
    if (version == null) {
      // The tap is spent and nothing is on screen, so this line is the only
      // record that it happened at all. On the failed branch the repository
      // will usually have said nothing either: its suppression drops a repeat
      // with the same reason, and the reason here is the one the startup
      // prefetch already gave. On the other branch it never had anything to
      // say - the directory arrived, it just carries no version here.
      LogService.warn(
        failed
            ? '[FirmwareCard] push tap for ${entry.shortName} dropped: the '
                  'directory could not be fetched'
            : '[FirmwareCard] push tap for ${entry.shortName} dropped: the '
                  'directory has no version on '
                  '${_fw.selectedChannelId(entry)}',
      );
      return;
    }
    _openChangelog(entry, version);
  }

  /// Points everything that follows the carousel at [index].
  ///
  /// Every caller assigns [_page] first. `setActiveFirmware` notifies when it
  /// really moves the firmware, and [_onThemeChanged] answers that by
  /// comparing the theme's page against [_page] - so a stale [_page] here
  /// would send the sync round again and schedule a jump across whatever
  /// animation is already running.
  void _followPage(int index) {
    final entry = _fw.config.firmwares[index];
    _themeController.setActiveFirmware(entry);
    _fw.ensureDirectory(entry);
  }

  /// Brings the carousel itself onto [index], once the frame has been laid
  /// out - a single firmware builds no `PageView`, so there is nothing to
  /// jump until then, and there may never be.
  void _jumpTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(index);
    });
  }

  void _onPageChanged(int page) {
    if (page >= _fw.config.firmwares.length) return;
    setState(() => _page = page);
    _followPage(page);
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
            fetchState: _fw.fetchStateFor(entry),
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
    final fetchState = _fw.fetchStateFor(entry);
    final latestVersion = _fw.latestVersionFor(entry);
    final latestFirmware = _fw.latestFirmwareFor(entry);
    final hasChangelog = latestFirmware?.changelog.trim().isNotEmpty ?? false;

    return FlipperPageCard(
      title: context.l10n.firmwareUpdateTitle,
      trailing: hasChangelog
          ? _WhatsNewButton(
              onTap: () {
                if (latestFirmware != null) {
                  _openChangelog(entry, latestFirmware);
                }
              },
            )
          : null,
      child: Column(
        children: [
          if (config.isSingle)
            _FirmwareSlide(
              entry: entry,
              fetchState: fetchState,
              latestVersion: latestVersion,
            )
          else
            _carousel(config),
          _FirmwareControls(
            entry: entry,
            fetchState: fetchState,
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
            fetchState: fetchState,
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
                  fetchState: _fw.fetchStateFor(firmware),
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
    required this.fetchState,
    required this.latestVersion,
  });

  final FirmwareEntry entry;
  final FirmwareFetchState fetchState;
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
                  fetchState.isLoading
                      ? context.l10n.firmwareChecking
                      : (latestVersion ?? '—'),
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
    UnleashedVariant.base => l10n.firmwareVariantDefault,
    UnleashedVariant.compact => l10n.firmwareVariantCompact,
    UnleashedVariant.extraPacks => l10n.firmwareVariantExtra,
  };
}

class _FirmwareControls extends StatelessWidget {
  const _FirmwareControls({
    required this.entry,
    required this.fetchState,
    required this.channelId,
    required this.channels,
    required this.variant,
    required this.showVariant,
    required this.onChannelChanged,
    required this.onVariantChanged,
  });

  final FirmwareEntry entry;
  final FirmwareFetchState fetchState;
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
            title: context.l10n.firmwareUpdateChannel,
            value: selectedChannel,
            items: channels,
            labelOf: (channel) => channel.title,
            descriptionOf: (channel) => channel.description,
            accent: accent,
            placeholder: fetchState.isLoading
                ? context.l10n.firmwareLoading
                : context.l10n.firmwareUnavailable,
            onChanged: (channel) => onChannelChanged(channel.id),
          ),
          if (showVariant) ...[
            const SizedBox(height: 8),
            _SettingsDropdown<UnleashedVariant>(
              title: context.l10n.firmwareBuildVariant,
              value: variant,
              items: UnleashedVariant.values,
              labelOf: _FirmwareSlide._variantLabel,
              descriptionOf: (variant) => switch (variant) {
                UnleashedVariant.base =>
                  context.l10n.firmwareVariantDefaultDescription,
                UnleashedVariant.compact =>
                  context.l10n.firmwareVariantCompactDescription,
                UnleashedVariant.extraPacks =>
                  context.l10n.firmwareVariantExtraDescription,
              },
              accent: accent,
              placeholder: context.l10n.firmwareUnavailable,
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
                context.l10n.firmwareWhatsNew,
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
