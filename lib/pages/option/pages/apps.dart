import 'dart:async';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/codec/fap/api_version.dart';
import '../../../components/navigation.dart';
import '../../../services/assembler/controller.dart';
import '../../../services/assembler/remote_build_service.dart';
import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../apps/data/apps_backend.dart';
import '../../apps/data/catalog_mode.dart';
import '../../apps/data/catalog_server.dart';

/// Settings -> Apps: the catalog and Flibler, which builds apps from source.
///
/// Follows the Android settings guidelines and Material 3:
/// - a row is a title with the setting's current status under it
///   (source.android.com/docs/core/settings/settings-guidelines);
/// - a single choice is a radio list in a dialog on a phone; on a desktop,
///   where a dialog only gets in the way, the radios sit in the card under
///   the setting's title;
/// - a free value such as a domain is a field under the last radio, as the
///   Private DNS hostname in Android;
/// - an action is an icon button at the end of the row it affects, in the
///   theme colour (M3 lists allow "text, icons, or icon buttons" there);
/// - the column keeps a max width instead of stretching (Android settings
///   pattern, "Adaptive layout").
class AppsSettingsPage extends StatefulWidget {
  const AppsSettingsPage({
    super.key,
    this.fromConsole = false,
    this.focusBuild = false,
    this.buildRemote,
  });

  /// Set when the Flibler console opened the page, so a job started here goes
  /// back to it instead of stacking a second console on top.
  final bool fromConsole;

  /// Scrolls to the Flibler groups, for the pages that open the build
  /// settings rather than the catalog ones.
  final bool focusBuild;

  /// Injectable for tests; the app always uses the configured singleton.
  @visibleForTesting
  final RemoteBuildService? buildRemote;

  @override
  State<AppsSettingsPage> createState() => _AppsSettingsPageState();
}

// ---------------------------------------------------------------------------
// Rows, actions and choices
// ---------------------------------------------------------------------------

const EdgeInsets _kRowPadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
const double _kRowMinContentHeight = 48;
const double _kGroupSpacing = 16;

/// How wide the settings column grows.
const double _kMaxContentWidth = 720;

/// Desktop platforms pick from radios in the list, the others from a dialog:
/// the split is the input, not the window width, which on a desktop is
/// often narrow.
bool _isDesktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.valueMaxLines = 2,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final int valueMaxLines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (value != null) ...[
          const SizedBox(height: 2),
          Text(
            value!,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? colors.textMuted,
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kRowMinContentHeight),
      child: Row(
        children: [
          Icon(icon, size: 24, color: colors.textSecondary),
          const SizedBox(width: 16),
          Expanded(child: text),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// A row and what tapping it does: only a choice on a phone has a tap, the
/// other rows act through their own controls or not at all.
typedef _Entry = (Widget row, VoidCallback? onTap);

Widget _group(List<_Entry> entries, {String? title}) => GroupedCardList<_Entry>(
  title: title,
  cardPadding: _kRowPadding,
  items: entries,
  onTap: (entry) => entry.$2,
  itemBuilder: (_, entry) => entry.$1,
);

VoidCallback _run(String area, Future<void> Function() action) =>
    () => unawaited(guarded('[Settings/Apps] $area', action));

/// A Material 3 standard icon button in the theme colour: 24 dp icon, 40 dp
/// container, 48 dp target. While its work runs it shows a spinner, and
/// [onPressed] may then lead to where the work can be watched.
Widget _iconAction(
  BuildContext context, {
  required IconData icon,
  required String tooltip,
  required VoidCallback? onPressed,
  bool running = false,
}) => IconButton(
  tooltip: tooltip,
  onPressed: onPressed,
  color: context.appColors.accent,
  style: IconButton.styleFrom(
    iconSize: 24,
    minimumSize: const Size.square(40),
    tapTargetSize: MaterialTapTargetSize.padded,
  ),
  icon: running
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon),
);

class _Option<T> {
  const _Option(this.value, this.title, {this.subtitle});

  final T value;
  final String title;
  final String? subtitle;
}

/// A value outside the options, typed in: the hostname under "Private DNS
/// provider" in Android.
class _Custom<T> {
  const _Custom({
    required this.value,
    required this.label,
    required this.display,
    required this.text,
    required this.hint,
    required this.parse,
    required this.invalid,
  });

  final T value;
  final String label;

  /// How the row names the custom value while it is the current one.
  final String display;

  /// What the field starts with.
  final String text;
  final String hint;

  /// The value the text stands for, or null when it is not a valid one.
  final String? Function(String text) parse;

  /// Shown under the field when [parse] refused the text.
  final String invalid;
}

/// What a choice returned. [text] is the parsed field when the custom value
/// was picked, null otherwise.
typedef _Choice<T> = ({T value, String? text});

/// A single-choice setting.
///
/// On a phone it is one row of its group: the current option under the
/// title, and a tap opens a radio list in a dialog; with a [custom] value the
/// dialog has the field under the last option and waits for Save.
///
/// On a desktop it is a group of its own in the Material 3 segmented list
/// shape (SegmentedListItem): each option is a piece of the group with the
/// radio leading and the whole piece clickable.
class _ChoiceSpec<T> {
  const _ChoiceSpec({
    required this.icon,
    required this.title,
    required this.current,
    required this.options,
    this.custom,
    required this.area,
    required this.apply,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final T current;
  final List<_Option<T>> options;
  final _Custom<T>? custom;
  final String area;
  final Future<void> Function(_Choice<T> choice) apply;
  final bool enabled;

  String get _currentTitle {
    final index = options.indexWhere((option) => option.value == current);
    if (index >= 0) return options[index].title;
    final custom = this.custom;
    return custom != null && current == custom.value ? custom.display : '';
  }

  _Entry phoneEntry(BuildContext context) => (
    _Row(icon: icon, title: title, value: _currentTitle),
    enabled
        ? _run(area, () async {
            final choice = await showDialog<_Choice<T>>(
              context: context,
              barrierColor: context.appColors.dialogBarrier,
              builder: (_) => _ChoiceDialog<T>(
                title: title,
                current: current,
                options: options,
                custom: custom,
              ),
            );
            if (choice != null) await apply(choice);
          })
        : null,
  );

  Widget desktopGroup() => _ChoiceGroup<T>(key: ValueKey(title), spec: this);
}

/// The settings choices of one group: on a phone the rows of one group
/// titled [title], on a desktop a group per choice.
List<Widget> _choiceGroups(
  BuildContext context,
  List<_ChoiceSpec<Object?>> specs, {
  String? title,
}) => _isDesktop(context)
    ? [
        for (final spec in specs) ...[
          spec.desktopGroup(),
          const SizedBox(height: _kGroupSpacing),
        ],
      ]
    : [
        _group([
          for (final spec in specs) spec.phoneEntry(context),
        ], title: title),
        const SizedBox(height: _kGroupSpacing),
      ];

/// An option piece: the radio's 40 px box starts 6 px in, so its circle sits
/// on the 16 px edge the other rows use, and the text starts at 56 px, where
/// a list item's headline goes after a leading element.
const EdgeInsets _kOptionPadding = EdgeInsets.fromLTRB(6, 8, 16, 8);

class _ChoiceGroup<T> extends StatefulWidget {
  const _ChoiceGroup({super.key, required this.spec});

  final _ChoiceSpec<T> spec;

  @override
  State<_ChoiceGroup<T>> createState() => _ChoiceGroupState<T>();
}

class _ChoiceGroupState<T> extends State<_ChoiceGroup<T>> {
  late final _text = TextEditingController(
    text: widget.spec.custom?.text ?? '',
  );
  final _focus = FocusNode();

  /// The custom option while its field has not been saved yet.
  bool _editing = false;
  String? _error;

  _ChoiceSpec<T> get _spec => widget.spec;

  bool _isCustom(T value) =>
      _spec.custom != null && value == _spec.custom!.value;

  T get _shown =>
      _editing && _spec.custom != null ? _spec.custom!.value : _spec.current;

  @override
  void didUpdateWidget(covariant _ChoiceGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _spec.custom?.text ?? '';
    if (!_focus.hasFocus && text != (oldWidget.spec.custom?.text ?? '')) {
      _text.text = text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(T? value) {
    if (value == null || !_spec.enabled) return;
    if (_isCustom(value)) {
      setState(() {
        _editing = !_isCustom(_spec.current);
        _error = null;
      });
      _focus.requestFocus();
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    if (value != _spec.current) {
      _run(_spec.area, () => _spec.apply((value: value, text: null)))();
    }
  }

  void _save() {
    final custom = _spec.custom;
    if (custom == null) return;
    final parsed = custom.parse(_text.text.trim());
    if (parsed == null) {
      setState(() => _error = custom.invalid);
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    _focus.unfocus();
    _run(_spec.area, () => _spec.apply((value: custom.value, text: parsed)))();
  }

  Widget _piece(BuildContext context, T value, String title, String? sub) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Radio<T>(value: value, enabled: _spec.enabled),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _spec.enabled
                        ? colors.textPrimary
                        : colors.textMuted,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, _Custom<T> custom) => Padding(
    padding: const EdgeInsets.fromLTRB(50, 4, 0, 4),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      enabled: _spec.enabled,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        isDense: true,
        hintText: custom.hint,
        errorText: _error,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: context.l10n.commonSave,
          icon: const Icon(Icons.check),
          color: context.appColors.accent,
          onPressed: _spec.enabled ? _save : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final custom = _spec.custom;
    final options = _spec.options;
    // The custom value is the last piece, after the options.
    final pieces = [
      for (var i = 0; i < options.length; i++) i,
      if (custom != null) options.length,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<T>(
          groupValue: _shown,
          onChanged: _select,
          child: GroupedCardList<int>(
            title: _spec.title,
            cardPadding: _kOptionPadding,
            items: pieces,
            onTap: (i) => _spec.enabled
                ? () => _select(
                    i < options.length ? options[i].value : custom!.value,
                  )
                : null,
            itemBuilder: (context, i) {
              if (i < options.length) {
                final option = options[i];
                return _piece(
                  context,
                  option.value,
                  option.title,
                  option.subtitle,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _piece(
                    context,
                    custom!.value,
                    custom.label,
                    _isCustom(_spec.current) && !_editing
                        ? custom.display
                        : null,
                  ),
                  if (_isCustom(_shown)) _field(context, custom),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChoiceDialog<T> extends StatefulWidget {
  const _ChoiceDialog({
    required this.title,
    required this.current,
    required this.options,
    required this.custom,
  });

  final String title;
  final T current;
  final List<_Option<T>> options;
  final _Custom<T>? custom;

  @override
  State<_ChoiceDialog<T>> createState() => _ChoiceDialogState<T>();
}

class _ChoiceDialogState<T> extends State<_ChoiceDialog<T>> {
  static const _tilePadding = EdgeInsets.symmetric(horizontal: 12);

  late T _choice = widget.current;
  late final _text = TextEditingController(text: widget.custom?.text ?? '');
  final _focus = FocusNode();
  String? _error;

  bool get _customPicked =>
      widget.custom != null && _choice == widget.custom!.value;

  void _choose(T? value) {
    if (value == null) return;
    if (widget.custom == null) {
      Navigator.of(context).pop((value: value, text: null));
      return;
    }
    setState(() {
      _choice = value;
      _error = null;
    });
    if (_customPicked) _focus.requestFocus();
  }

  void _save() {
    final custom = widget.custom;
    if (custom == null || !_customPicked) {
      Navigator.of(context).pop((value: _choice, text: null));
      return;
    }
    final parsed = custom.parse(_text.text.trim());
    if (parsed == null) {
      setState(() => _error = custom.invalid);
      return;
    }
    Navigator.of(context).pop((value: _choice, text: parsed));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final colors = context.appColors;
    final custom = widget.custom;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.only(top: 12),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            groupValue: _choice,
            onChanged: _choose,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final option in widget.options)
                  RadioListTile<T>(
                    value: option.value,
                    contentPadding: _tilePadding,
                    title: Text(option.title),
                    subtitle: option.subtitle == null
                        ? null
                        : Text(
                            option.subtitle!,
                            style: TextStyle(color: colors.textMuted),
                          ),
                  ),
                if (custom != null) ...[
                  RadioListTile<T>(
                    value: custom.value,
                    contentPadding: _tilePadding,
                    title: Text(custom.label),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onTap: () => _choose(custom.value),
                      // Typing picks the option too, or Save would keep the
                      // radio that was on while the text went unused.
                      onChanged: (_) {
                        if (!_customPicked) {
                          _choose(custom.value);
                        } else if (_error != null) {
                          setState(() => _error = null);
                        }
                      },
                      onSubmitted: (_) => _save(),
                      decoration: InputDecoration(
                        hintText: custom.hint,
                        errorText: _error,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.commonCancel),
        ),
        if (custom != null)
          TextButton(onPressed: _save, child: Text(s.commonSave)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

String _modeTitle(L10n s, CatalogModePreference value) => switch (value) {
  CatalogModePreference.auto => s.appsModeAuto,
  CatalogModePreference.catalog => s.appsModeCatalog,
  CatalogModePreference.sourceBuild => s.appsModeSourceBuild,
  CatalogModePreference.manager => s.appsModeManager,
};

String _modeSubtitle(L10n s, CatalogModePreference value) => switch (value) {
  CatalogModePreference.auto => s.appsModeAutoSubtitle,
  CatalogModePreference.catalog => s.appsModeCatalogSubtitle,
  CatalogModePreference.sourceBuild => s.appsModeSourceBuildSubtitle,
  CatalogModePreference.manager => s.appsModeManagerSubtitle,
};

String _serverName(L10n s, String server) => server == CatalogServer.official
    ? s.appsCatalogOfficial
    : Uri.parse(server).authority;

String? _parseDomain(String text) {
  try {
    return CatalogServer.normalize(text);
  } on FormatException {
    return null;
  }
}

/// By number, not text: as strings 87.10 sorted below 87.9.
int _newestFirst(String a, String b) {
  final pa = parseApi(a), pb = parseApi(b);
  if (pa == null || pb == null) return b.compareTo(a);
  return compareApi(pb, pa);
}

class _AppsSettingsPageState extends State<AppsSettingsPage> {
  final AppsBackend _backend = AppsBackend.instance;
  final _buildKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.focusBuild) _scrollToBuild();
      await _backend.loadPreference();
      if (mounted) setState(() {});
      // The page can be the first screen that asks, so the mode is resolved
      // here too instead of waiting for the catalog to be opened.
      unawaited(guarded('[Settings/Apps] resolve mode', _backend.resolveMode));
    });
  }

  void _scrollToBuild() {
    final target = _buildKey.currentContext;
    if (target != null) Scrollable.ensureVisible(target);
  }

  Future<void> _applyServer(_Choice<String> choice) async {
    final value = choice.text ?? choice.value;
    if (value == _backend.api.server) return;
    final pending = _backend.setServer(value);
    if (mounted) setState(() {});
    await pending;
    if (mounted) setState(() {});
  }

  Future<void> _applyProtocol(_Choice<CatalogProtocol> choice) async {
    if (choice.value == _backend.api.protocol) return;
    final pending = _backend.setProtocol(choice.value);
    if (mounted) setState(() {});
    await pending;
    if (mounted) setState(() {});
  }

  Future<void> _applyMode(_Choice<CatalogModePreference> choice) async {
    if (choice.value == _backend.preference) return;
    await _backend.setPreference(choice.value);
    if (mounted) setState(() {});
  }

  Future<void> _recheck() async {
    await _backend.resolveMode(force: true);
    if (mounted) setState(() {});
  }

  /// The API versions the catalog serves for this device's target, newest
  /// first, with the one the app requests apps for marked.
  String _apis(L10n s) {
    if (_backend.catalogOffline) return s.appsStatusNoAnswer;
    final target = _backend.deviceTarget;
    final apis = {
      for (final sdk in _backend.serverSdks)
        if (target == null || sdk.target == target) sdk.api,
    }.toList()..sort(_newestFirst);
    if (apis.isEmpty) return s.appsStatusNone;
    final inUse = _backend.api.api;
    return [for (final api in apis) api == inUse ? s.appsApiInUse(api) : api]
        .join(', ');
  }

  List<_ChoiceSpec<Object?>> _catalog(L10n s) {
    final server = _backend.api.server;
    const customServer = '';
    final known = [CatalogServer.official, ...CatalogServer.community];
    final isKnown = known.contains(server);
    return [
      _ChoiceSpec<String>(
        icon: Icons.dns_outlined,
        title: s.appsCatalogServer,
        current: isKnown ? server : customServer,
        options: [
          for (final value in known)
            _Option(
              value,
              _serverName(s, value),
              subtitle: value == CatalogServer.official
                  ? Uri.parse(value).host
                  : null,
            ),
        ],
        custom: _Custom(
          value: customServer,
          label: s.appsCatalogCustom,
          display: _serverName(s, server),
          text: isKnown ? '' : server,
          hint: 'catalog.example.org',
          parse: _parseDomain,
          invalid: s.appsCatalogInvalidDomain,
        ),
        area: 'pick catalog',
        apply: _applyServer,
      ),
      _ChoiceSpec<CatalogProtocol>(
        icon: Icons.swap_horiz,
        title: s.appsCatalogProtocol,
        current: _backend.api.protocol,
        options: [
          _Option(
            CatalogProtocol.v1,
            s.appsProtocolV1,
            subtitle: s.appsProtocolV1Subtitle,
          ),
          _Option(
            CatalogProtocol.v0,
            s.appsProtocolV0,
            subtitle: s.appsProtocolV0Subtitle,
          ),
        ],
        // Official has v0 only.
        enabled: server != CatalogServer.official,
        area: 'pick catalog protocol',
        apply: _applyProtocol,
      ),
      _ChoiceSpec<CatalogModePreference>(
        icon: Icons.tune,
        title: s.appsGroupCatalogMode,
        current: _backend.preference,
        options: [
          for (final value in CatalogModePreference.values)
            _Option(
              value,
              _modeTitle(s, value),
              subtitle: _modeSubtitle(s, value),
            ),
        ],
        area: 'pick catalog mode',
        apply: _applyMode,
      ),
    ];
  }

  List<_Entry> _status(L10n s) {
    final colors = context.appColors;
    final resolving = _backend.mode.value == CatalogMode.resolving;
    return [
      (
        _Row(
          icon: Icons.memory,
          title: s.appsStatusFirmware,
          value: _backend.deviceApi == null
              ? s.appsStatusNotConnected
              : '${_backend.deviceApi} · ${_backend.deviceTarget}',
          valueColor: _backend.deviceApi != null ? colors.success : null,
        ),
        null,
      ),
      (
        _Row(
          icon: Icons.layers_outlined,
          title: s.appsCatalogApis,
          value: _apis(s),
          valueColor: _backend.catalogOffline ? colors.danger : null,
          trailing: _iconAction(
            context,
            icon: Icons.refresh,
            tooltip: resolving ? s.appsChecking : s.appsRecheck,
            running: resolving,
            onPressed: resolving ? null : _run('recheck mode', _recheck),
          ),
        ),
        null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _backend.mode,
      builder: (context, _) {
        final s = context.l10n;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(s.settingsAppsTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          // Not a ListView: a lazy list does not build the Flibler groups
          // until they scroll in, so focusBuild would have nothing to reach.
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._choiceGroups(context, _catalog(s)),
                    _group(_status(s), title: s.appsGroupStatus),
                    const SizedBox(height: _kGroupSpacing),
                    _FliblerSection(
                      key: _buildKey,
                      fromConsole: widget.fromConsole,
                      remote: widget.buildRemote,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Flibler
// ---------------------------------------------------------------------------

String _channelTitle(L10n s, UfbtUpdateChannel channel) => switch (channel) {
  UfbtUpdateChannel.release => s.fliblerChannelRelease,
  UfbtUpdateChannel.rc => s.fliblerChannelRc,
  UfbtUpdateChannel.dev => s.fliblerChannelDev,
};

String _channelSubtitle(L10n s, UfbtUpdateChannel channel) => switch (channel) {
  UfbtUpdateChannel.release => s.fliblerChannelReleaseSubtitle,
  UfbtUpdateChannel.rc => s.fliblerChannelRcSubtitle,
  UfbtUpdateChannel.dev => s.fliblerChannelDevSubtitle,
};

String _sourceTitle(L10n s, AssemblerSdkSource source) => switch (source) {
  AssemblerSdkSource.unleashed => 'Unleashed',
  AssemblerSdkSource.official => 'Official',
  AssemblerSdkSource.custom => s.fliblerSourceCustom,
};

String _backendTitle(L10n s, AssemblerBackendPreference preference) =>
    switch (preference) {
      AssemblerBackendPreference.auto => s.fliblerBackendAuto,
      AssemblerBackendPreference.server => s.fliblerBackendServer,
    };

String _backendSubtitle(L10n s, AssemblerBackendPreference preference) =>
    switch (preference) {
      AssemblerBackendPreference.auto => s.fliblerBackendAutoSubtitle,
      AssemblerBackendPreference.server => s.fliblerBackendServerSubtitle,
    };

/// An http(s) link with a host, the only kind the SDK index can be read from.
String? _parseIndexUrl(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return text;
}

/// Where builds run, the SDK this computer uses and the build server.
class _FliblerSection extends StatefulWidget {
  const _FliblerSection({super.key, required this.fromConsole, this.remote});

  final bool fromConsole;
  final RemoteBuildService? remote;

  @override
  State<_FliblerSection> createState() => _FliblerSectionState();
}

class _FliblerSectionState extends State<_FliblerSection> {
  final AssemblerController _ctrl = AssemblerController.instance;

  RemoteBuildService get _remote =>
      widget.remote ?? RemoteBuildService.instance;
  RemoteServerStatus? _serverStatus;
  String? _serverError;
  bool _serverLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.refreshStatus();
      unawaited(guarded('[Settings/Flibler] server status', _loadServerStatus));
    });
  }

  Future<void> _loadServerStatus() async {
    if (_serverLoading || !mounted) return;
    setState(() {
      _serverLoading = true;
      _serverError = null;
    });
    RemoteServerStatus? status;
    String? error;
    try {
      status = await _remote.serverStatus();
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _serverStatus = status;
      _serverError = error;
      _serverLoading = false;
    });
  }

  void _showConsole() {
    final navigator = Navigator.of(context);
    if (widget.fromConsole) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    openRoute(context, AppRoute.assemblerConsole);
  }

  Future<void> _applyBackend(_Choice<AssemblerBackendPreference> c) async {
    await _ctrl.setPreference(c.value);
    if (_ctrl.usesServerBuild && _serverStatus == null) {
      unawaited(guarded('[Settings/Flibler] server status', _loadServerStatus));
    }
  }

  Future<void> _applyChannel(_Choice<UfbtUpdateChannel> c) async =>
      _ctrl.setChannel(c.value);

  Future<void> _applySource(_Choice<AssemblerSdkSource> c) async {
    // The link first, so the custom source never reads an empty one.
    final url = c.text;
    if (url != null) await _ctrl.setCustomIndexUrl(url);
    await _ctrl.setSdkSource(c.value);
  }

  Future<void> _downloadSdk() async {
    _showConsole();
    await _ctrl.downloadSdk();
  }

  Future<void> _downloadToolchain() async {
    final upToDate = _ctrl.status?.toolchain.isUpToDate ?? false;
    _showConsole();
    await _ctrl.downloadToolchain(force: upToDate);
  }

  List<_ChoiceSpec<Object?>> _settings(L10n s, bool supported, bool busy) => [
    _ChoiceSpec<AssemblerBackendPreference>(
      icon: Icons.construction_outlined,
      title: s.fliblerGroupBuildWith,
      current: _ctrl.preference,
      options: [
        for (final value in AssemblerBackendPreference.values)
          _Option(
            value,
            _backendTitle(s, value),
            subtitle: _backendSubtitle(s, value),
          ),
      ],
      area: 'pick build backend',
      apply: _applyBackend,
      enabled: !busy,
    ),
    // The local controls stay on desktop whatever the resolved backend is:
    // this is the only place the SDK can be downloaded, and until it is,
    // builds keep going to the server.
    if (supported) ...[
      _ChoiceSpec<UfbtUpdateChannel>(
        icon: Icons.alt_route,
        title: s.fliblerGroupSdkChannel,
        current: _ctrl.channel,
        options: [
          for (final value in const [
            UfbtUpdateChannel.release,
            UfbtUpdateChannel.dev,
          ])
            _Option(
              value,
              _channelTitle(s, value),
              subtitle: _channelSubtitle(s, value),
            ),
        ],
        area: 'pick SDK channel',
        apply: _applyChannel,
        enabled: !busy,
      ),
      _ChoiceSpec<AssemblerSdkSource>(
        icon: Icons.source_outlined,
        title: s.fliblerGroupSdkIndex,
        current: _ctrl.sdkSource,
        options: [
          for (final value in AssemblerSdkSource.values)
            if (value.url != null)
              _Option(value, _sourceTitle(s, value), subtitle: value.url),
        ],
        custom: _Custom(
          value: AssemblerSdkSource.custom,
          label: s.fliblerCustomIndexTitle,
          display: _ctrl.customIndexUrl.isEmpty
              ? s.fliblerSetIndexUrl
              : _ctrl.customIndexUrl,
          text: _ctrl.customIndexUrl,
          hint: 'https://server/directory.json',
          parse: _parseIndexUrl,
          invalid: s.fliblerInvalidIndexUrl,
        ),
        area: 'pick SDK index',
        apply: _applySource,
        enabled: !busy,
      ),
    ],
  ];

  List<_Entry> _thisComputer(L10n s) {
    final colors = context.appColors;
    final status = _ctrl.status;
    if (status == null) {
      return [
        (
          _Row(
            icon: Icons.info_outline,
            title: s.fliblerStatusState,
            value: s.fliblerNotCheckedYet,
          ),
          null,
        ),
      ];
    }
    final toolchain = status.toolchain;
    final channel = _channelTitle(s, _ctrl.channel).toLowerCase();
    final sdkRunning = _ctrl.job == AssemblerJob.sdk;
    final toolchainRunning = _ctrl.job == AssemblerJob.toolchain;

    // While a download runs, its button shows the spinner and leads to the
    // console the download writes to.
    Widget download({
      required bool running,
      required IconData icon,
      required String label,
      required String detail,
      required Future<void> Function() action,
      required String area,
    }) => _iconAction(
      context,
      icon: icon,
      tooltip: running ? s.fliblerConsoleTab : '$label · $detail',
      running: running,
      onPressed: running
          ? _showConsole
          : _ctrl.busy
          ? null
          : _run(area, action),
    );

    return [
      (
        _Row(
          icon: Icons.inventory_2_outlined,
          title: 'SDK',
          value: status.sdkDeployed
              ? '${status.version ?? '—'} · ${status.target ?? '—'}'
              : s.fliblerNotInstalled,
          valueColor: status.sdkDeployed ? colors.success : null,
          trailing: download(
            running: sdkRunning,
            icon: status.sdkDeployed ? Icons.sync : Icons.download,
            label: status.sdkDeployed
                ? s.fliblerUpdateSdk
                : s.fliblerDownloadSdk,
            detail: status.sdkDeployed
                ? s.fliblerSdkHave(status.version ?? '—', channel)
                : s.fliblerSdkSize(channel),
            action: _downloadSdk,
            area: 'download SDK',
          ),
        ),
        null,
      ),
      (
        _Row(
          icon: Icons.build_outlined,
          title: s.fliblerStatusToolchain,
          value: toolchain.isUpToDate
              ? 'v${toolchain.installedVersion}'
              : toolchain.isDeployed
              ? 'v${toolchain.installedVersion} → v${toolchain.version}'
              : s.fliblerNotInstalled,
          valueColor: toolchain.isUpToDate ? colors.success : null,
          trailing: download(
            running: toolchainRunning,
            icon: toolchain.isUpToDate
                ? Icons.restart_alt
                : toolchain.isDeployed
                ? Icons.sync
                : Icons.download,
            label: toolchain.isUpToDate
                ? s.fliblerReinstallToolchain
                : toolchain.isDeployed
                ? s.fliblerUpdateToolchain
                : s.fliblerDownloadToolchain,
            detail: toolchain.isUpToDate
                ? s.fliblerToolchainReinstall('${toolchain.installedVersion}')
                : toolchain.isDeployed
                ? s.fliblerToolchainUpdate(
                    '${toolchain.installedVersion}',
                    toolchain.version,
                  )
                : s.fliblerToolchainDownload(toolchain.version),
            action: _downloadToolchain,
            area: 'download toolchain',
          ),
        ),
        null,
      ),
      (
        _Row(
          icon: Icons.folder_outlined,
          title: s.fliblerStatusStateDir,
          value: status.stateDir,
        ),
        null,
      ),
    ];
  }

  List<_Entry> _buildServer(L10n s) {
    final colors = context.appColors;
    final status = _serverStatus;
    final error = _serverError;
    return [
      (
        _Row(
          icon: Icons.link,
          title: s.fliblerStatusAddress,
          value: Uri.parse(_remote.serverUrl).host,
        ),
        null,
      ),
      if (!_remote.canBuild)
        (
          _Row(
            icon: Icons.key_outlined,
            title: s.fliblerStatusSigningKey,
            value: s.fliblerKeyMissing,
            valueColor: colors.danger,
          ),
          null,
        ),
      (
        _Row(
          icon: Icons.cloud_outlined,
          title: s.fliblerStatusServer,
          value: _serverLoading
              ? s.fliblerChecking
              : error != null
              ? '${s.fliblerUnreachable}\n$error'
              : status != null
              ? s.fliblerOnlineVersion(status.version)
              : s.fliblerNotCheckedYet,
          valueMaxLines: 3,
          valueColor: _serverLoading
              ? null
              : error != null
              ? colors.danger
              : status != null
              ? colors.success
              : null,
          trailing: _iconAction(
            context,
            icon: Icons.refresh,
            tooltip: _serverLoading ? s.fliblerChecking : s.fliblerCheckServer,
            running: _serverLoading,
            onPressed: _serverLoading
                ? null
                : _run('check build server', _loadServerStatus),
          ),
        ),
        null,
      ),
      (
        _Row(
          icon: Icons.inventory_2_outlined,
          title: s.fliblerStatusDeployedSdk,
          value: status == null
              ? '—'
              : status.sdkVersions.isEmpty
              ? s.fliblerDeploysOnFirstBuild
              : status.sdkVersions.join(', '),
        ),
        null,
      ),
      (
        _Row(
          icon: Icons.queue_outlined,
          title: s.fliblerStatusQueue,
          value: status == null
              ? '—'
              : s.fliblerQueueLength(status.queueLength),
        ),
        null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (context, _) {
      final s = context.l10n;
      final supported = AssemblerController.isSupported;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._choiceGroups(
            context,
            _settings(s, supported, _ctrl.busy),
            title: 'Flibler',
          ),
          // The choice groups end with their own spacing.
          if (supported) ...[
            _group(_thisComputer(s), title: s.fliblerGroupThisComputer),
            const SizedBox(height: _kGroupSpacing),
          ],
          _group(_buildServer(s), title: s.fliblerBackendServer),
        ],
      );
    },
  );
}
