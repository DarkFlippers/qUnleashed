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
    // No `DeviceScope` around this any more: it is provided above the
    // Navigator, so a pushed route is inside it - ADR 0011. It used to be
    // re-provided here, and this was the only push that remembered to.
    //
    // `clientOf`, and that matters more here than at a read in a `build`.
    // Nothing clears `Element._dependencies` on a rebuild - only `activate`
    // and `deactivate` touch it - so a listening read from a callback is a
    // *standing* dependency for the element's life, not one that lapses at the
    // next build. This card is the device screen's heaviest, and one tap on a
    // changelog used to subscribe it to the five-second info poll until the
    // screen went away. #344.
    final client = DeviceScope.clientOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FirmwareChangelogPage(
          entry: entry,
          version: version,
          changelog: version.changelog,
          fetchState: _fw.fetchStateFor(entry),
          latestVersion: _fw.latestVersionFor(entry),
          deviceVersion: widget.deviceVersion,
          deviceInfo: widget.deviceInfo,
          selectedChannelId: _fw.selectedChannelId(entry),
          selectedVariant: _fw.selectedVariant(entry),
          client: client,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _fw.config;
    if (config.firmwares.isEmpty) return const SizedBox.shrink();

    // The device scope owns the client; this card is always built inside one.
    // Reading it here rather than holding `FlipperOneClient().get()` in a
    // field is what lets a widget test mount this against a fake - ADR 0002.
    final client = DeviceScope.clientOf(context);

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
            client: client,
          ),
        ],
      ),
    );
  }

  Widget _carousel(FirmwareConfig config) {
    return SizedBox(
      // **A known overflow, not an open question.** A fixed height holding
      // text that scales is the same class of bug as #463, which filed it as
      // "same card, not confirmed" on the strength of a screenshot. A
      // screenshot is the one instrument that cannot see it, for two reasons
      // that are not the same reason: the overflow report lives inside an
      // `assert` in `RenderFlex.paint`, so a release build says nothing
      // whether or not anything clips; and the excess is clipped anyway -
      // by the slide's own `Column`, whose `Flex.clipBehavior` is
      // `Clip.hardEdge`, by the `PageView`'s viewport, and by the card's
      // `Clip.antiAlias`. `device_header_fit_test.dart` records the same trap.
      //
      // Pumped through `test/firmware_fixture.dart` at a 360 dp window, this
      // overflows by 10 pixels at a scaler of 1.3, 163 at 2.0 and 555 at 3.1,
      // and by 73 at 1.3 on a 320. Fixing it means deciding what the carousel
      // does instead - a `PageView` needs a bounded height, and the slide's
      // 22pt name wraps before the box runs out - which is a design question
      // rather than the one-line change #463's two rows were. It is #471;
      // this note is here so the 110 is not read as a number that was
      // measured.
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
          SettingsDropdown<FirmwareDirectoryChannel>(
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
            SettingsDropdown<UnleashedVariant>(
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

/// A setting's title beside a tap target showing its current value, or
/// above it once both will not fit one line.
///
/// ## The two arrangements, and why there are two
///
/// A title and a value on one line stop fitting on one line at some text
/// size, and this one did it badly: the title was an `Expanded` beside an
/// inflexible dropdown, so the dropdown took its whole intrinsic width - its
/// value plus 22 of padding and border, the 6 before the chevron and the
/// chevron's 18, none of which follows the text scaler because nothing here
/// sets `Icon.applyTextScaling` - and the title got the remainder. At a
/// scaler of 2 that remainder fell to about one glyph, and `Text` with no
/// `maxLines` wraps per character: a vertical column of letters, tall enough
/// to push the build-variant row and the update button off the screen. #463.
///
/// So the row is kept only while both strings fit it whole, and below that
/// the title moves above the dropdown instead. Of the three fixes the issue
/// weighed, this is the one that keeps both strings intact at every scaler:
/// ellipsising the value would bring the #425 trap here - a cut value that
/// cannot be told from another cut value, which in #425 was the bottom bar
/// drawing "Syncing" and "Synced" as the same word - and clamping the title
/// to two lines leaves the user reading "Кан..." for the setting they are
/// changing.
///
/// ## A `Wrap`, and not a measurement
///
/// The arrangement is the layout's own decision. A `Wrap` puts a child on a
/// new run when the run it is on cannot hold it with [_gap] to spare, which
/// is this rule exactly, and `spaceBetween` keeps the dropdown against the
/// trailing edge while the two share a run. Two children, no arithmetic.
///
/// The draft before this one computed it instead, with a `TextPainter` over
/// each string and a constant for the dropdown's chrome. It worked, and every
/// defect available to it was in the model rather than in the layout: the
/// chrome constant left out the `Border.all` pixel `Container` adds outside
/// its padding on each side, which is nothing anywhere except at the width
/// where the decision is made; `Text` merges `FontWeight.bold` over its style
/// under the system bold-text setting, so a probe reading `w500` measures a
/// paragraph drawn at `w700`; and a `MediaQuery` letter- or word-spacing
/// override is applied by `Text` to the *span* rather than to the style, so a
/// probe could not see it at all. `TabLabel` in `lib/app/nav_bar.dart` records
/// the same three for the same reason - it retired a two-probe fit in favour
/// of a `FittedBox` - and this is that note taken rather than re-learned.
///
/// On the channel row the value is **server data**, which is why no width
/// threshold would have done either: a channel's title comes from the
/// firmware directory (`directory.dart`'s `_presentation(json, 'title')`), so
/// nothing picked here and no ARB kept short survives a longer channel title
/// shipping upstream. The variant row's three values and both placeholders
/// are ARB strings, and a translator can lengthen those just as freely.
///
/// ## It wants a bounded width, as the `Expanded` it replaces did
///
/// Because it claims the whole of it: a `Wrap` is as wide as its children, and
/// the `Column` these sit in centres anything narrower than itself, so without
/// `width: double.infinity` the two rows would hug their content and drift to
/// the middle of the card. An infinite width then makes that `SizedBox`
/// infinite, which is an assertion of its own - the old row's was the
/// `RenderFlex` one, since `Expanded` is `FlexFit.tight`.
///
/// What bounds it is the call site and nothing here: both of these are built
/// by `_FirmwareControls`, inside `FlipperPageCard`, inside the device page's
/// `ListView`. The card's own `Container(width: double.infinity)` is **not**
/// what does it - that propagates an incoming bound and forces infinity where
/// there is none.
///
/// A case pins the full width rather than the bound, because filling the card
/// is the part a caller depends on.
///
/// `@visibleForTesting` so `test/firmware_dropdown_fit_test.dart` can drive
/// the contract at a scaler; nothing outside this file builds one.
@visibleForTesting
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
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

  /// The gap the title keeps from the dropdown beside it.
  ///
  /// `Wrap.spacing` is both the gap it draws and the room it insists on
  /// before it will keep two children on one run, so "fits" is "fits with
  /// room to read" rather than "the two strings touch" - and the two cannot
  /// disagree, because they are the same number read once.
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      // Fills the card rather than hugging its text; the class doc has why a
      // `Wrap` needs saying so where the `Row` did not.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          // Holds the dropdown against the trailing edge while the two share a
          // run, which is what the `Expanded` used to do. With one child on a
          // run there is nothing to space, so a stacked title sits at the
          // leading edge.
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: _gap,
          runSpacing: 6,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            _dropdown(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(BuildContext context, QAppColors colors) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: items.isEmpty ? null : () => _showPicker(context, colors),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: colors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `Flexible`, so a value too long for the card wraps inside the
              // dropdown rather than overflowing it: `Wrap` hands each child
              // its own maxWidth, which here is the card's width.
              Flexible(
                child: Text(
                  value == null ? placeholder : labelOf(value as T),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: value == null ? colors.textMuted : accent,
                  ),
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
