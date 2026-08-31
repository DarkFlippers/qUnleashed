import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../archive/map/data/settings.dart';

class _ActionTile {
  const _ActionTile(this.child, [this.onTap]);

  final Widget child;
  final VoidCallback? onTap;
}

class MapSettingsPage extends StatefulWidget {
  const MapSettingsPage({super.key});

  @override
  State<MapSettingsPage> createState() => _MapSettingsPageState();
}

class _MapSettingsPageState extends State<MapSettingsPage> {
  final MapSettings _settings = MapSettings.instance;
  final TextEditingController _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool get _mapDark => _settings.darkFor(context.appColors.isDark);

  MapTileProvider get _provider => _settings.provider;

  Widget _titleColumn(
    BuildContext context, {
    required String title,
    required String subtitle,
    int subtitleLines = 2,
  }) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: subtitleLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.2),
        ),
      ],
    );
  }

  Widget _radioTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    Widget? leading,
    Widget? badge,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 10)],
        Expanded(
          child: _titleColumn(context, title: title, subtitle: subtitle),
        ),
        if (badge != null) ...[const SizedBox(width: 8), badge],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 22,
            color: selected ? colors.accent : colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _valueTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    IconData icon = Icons.chevron_right,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: _titleColumn(context, title: title, subtitle: subtitle),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(icon, size: 20, color: colors.textMuted),
        ),
      ],
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: _titleColumn(context, title: title, subtitle: subtitle),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: colors.accent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _tilePreview(
    BuildContext context,
    MapTileConfig config, {
    double size = 56,
    bool selected = false,
  }) {
    final colors = context.appColors;
    const radius = BorderRadius.all(Radius.circular(8));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.background, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: selected ? colors.accent : colors.divider,
          width: selected ? 2 : 1,
        ),
        borderRadius: radius,
      ),
      child: config.missingKey
          ? Icon(
              Icons.key_off_outlined,
              size: size * 0.4,
              color: colors.textMuted,
            )
          : Image.network(
              _settings.previewUrl(config),
              key: ValueKey(_settings.previewUrl(config)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                size: size * 0.4,
                color: colors.textMuted,
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Center(
                      child: SizedBox(
                        width: size * 0.3,
                        height: size * 0.3,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
            ),
    );
  }

  Widget _livePreview(BuildContext context) {
    final colors = context.appColors;
    final config = _settings.resolve(dark: _mapDark);
    final strings = context.l10n;
    final status = config.missingKey
        ? strings.mapKeyNeeded
        : config.usesEmbeddedKey
        ? strings.mapKeyBuiltIn
        : _settings.keyOf(_provider).isNotEmpty
        ? strings.mapKeyYours
        : strings.mapKeyNotNeeded;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kGroupedHorizontalPadding,
      ),
      child: GroupedCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _tilePreview(context, config, size: 84),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_mapDark ? strings.mapTilesDark : strings.mapTilesLight}'
                    ' · ${strings.mapMaxZoomOf(config.maxZoom.round())}',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: TextStyle(
                      color: config.missingKey
                          ? colors.danger
                          : config.usesEmbeddedKey
                          ? colors.success
                          : colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (config.attribution.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      config.attribution,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerTile(BuildContext context, MapTileProvider provider) {
    final colors = context.appColors;
    final needsKey = provider.needsKey && !_settings.hasKey(provider);
    return _radioTile(
      context,
      title: provider.label,
      subtitle: provider.isCustom && _settings.customUrl.isNotEmpty
          ? _settings.customUrl
          : provider.description,
      selected: _provider.id == provider.id,
      badge: needsKey
          ? Icon(Icons.key_outlined, size: 18, color: colors.textMuted)
          : null,
    );
  }

  Widget _designTile(BuildContext context, MapTileDesign design) {
    final selected =
        _settings.designOf(_provider, dark: design.dark).id == design.id;
    return _radioTile(
      context,
      title: design.label,
      subtitle: design.description,
      selected: selected,
      leading: _tilePreview(
        context,
        _settings.configFor(_provider, design),
        selected: selected,
      ),
    );
  }

  static String _mask(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 8) return '•' * value.length;
    return '${value.substring(0, 4)}${'•' * 6}'
        '${value.substring(value.length - 4)}';
  }

  Future<String?> _prompt({
    required String title,
    required String hint,
    required String initial,
    TextInputType keyboard = TextInputType.text,
    bool allowClear = false,
  }) {
    final colors = context.appColors;
    _field.text = initial;
    _field.selection = TextSelection.collapsed(offset: initial.length);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: colors.dialogBackground,
        title: Text(title, style: TextStyle(color: colors.dialogText)),
        content: TextField(
          controller: _field,
          autofocus: true,
          keyboardType: keyboard,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(color: colors.dialogText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.l10n.commonCancel),
          ),
          if (allowClear)
            TextButton(
              onPressed: () => Navigator.pop(c, ''),
              child: Text(c.l10n.commonClear),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c, _field.text.trim()),
            child: Text(c.l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _selectProvider(MapTileProvider provider) async {
    await _settings.setProvider(provider);
    if (!mounted) return;
    if (provider.isCustom && _settings.customUrl.isEmpty) {
      await _editCustomUrl();
      return;
    }
    if (provider.needsKey && !_settings.hasKey(provider)) {
      await _editKey(provider);
    }
  }

  Future<void> _editKey(MapTileProvider provider) async {
    final current = _settings.keyOf(provider);
    final value = await _prompt(
      title: l10n.mapProviderKeyTitle(provider.label),
      hint: provider.keyHint ?? l10n.mapApiKeyHint,
      initial: current,
      allowClear: current.isNotEmpty,
    );
    if (value != null) await _settings.setKey(provider, value);
  }

  Future<void> _editCustomUrl() async {
    final value = await _prompt(
      title: l10n.mapTileUrlTemplate,
      hint: 'https://{s}.tiles.example/{z}/{x}/{y}.png',
      initial: _settings.customUrl,
      keyboard: TextInputType.url,
      allowClear: _settings.customUrl.isNotEmpty,
    );
    if (value != null) await _settings.setCustomUrl(value);
  }

  Future<void> _editCustomSubdomains() async {
    final value = await _prompt(
      title: l10n.mapSubdomains,
      hint: l10n.mapSubdomainsHint,
      initial: _settings.customSubdomains,
      allowClear: _settings.customSubdomains.isNotEmpty,
    );
    if (value != null) await _settings.setCustomSubdomains(value);
  }

  Future<void> _editCustomMaxZoom() async {
    final value = await _prompt(
      title: l10n.mapMaxZoom,
      hint: '19',
      initial: '${_settings.customMaxZoom.round()}',
      keyboard: TextInputType.number,
    );
    if (value == null) return;
    final zoom = double.tryParse(value);
    if (zoom != null) await _settings.setCustomMaxZoom(zoom);
  }

  Future<void> _openSignup(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  List<_ActionTile> _keyTiles(BuildContext context) {
    final colors = context.appColors;
    final provider = _provider;
    final own = _settings.keyOf(provider);
    final builtIn = provider.id == kCartoProviderId;
    return [
      if (builtIn)
        _ActionTile(
          Row(
            children: [
              Expanded(
                child: _titleColumn(
                  context,
                  title: context.l10n.mapBuiltInCartoKey,
                  subtitle: _settings.hasEmbeddedKey
                      ? context.l10n.mapBuiltInCartoKeyPresent
                      : context.l10n.mapBuiltInKeyMissing,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  _settings.hasEmbeddedKey
                      ? Icons.lock_outline
                      : Icons.lock_open,
                  size: 20,
                  color: _settings.hasEmbeddedKey
                      ? colors.success
                      : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      _ActionTile(
        _valueTile(
          context,
          title: context.l10n.mapYourProviderKey(provider.label),
          subtitle: own.isNotEmpty
              ? _mask(own)
              : builtIn
              ? context.l10n.mapKeyNotSetBuiltInUsed
              : provider.keyHint ?? context.l10n.mapKeyNotSet,
        ),
        () => _editKey(provider),
      ),
      if (provider.signupUrl != null)
        _ActionTile(
          _valueTile(
            context,
            title: context.l10n.mapGetKey,
            subtitle: Uri.parse(provider.signupUrl!).host,
            icon: Icons.open_in_new,
          ),
          () => _openSignup(provider.signupUrl!),
        ),
    ];
  }

  List<_ActionTile> _customTiles(BuildContext context) => [
    _ActionTile(
      _valueTile(
        context,
        title: context.l10n.mapTileUrlTemplate,
        subtitle: _settings.customUrl.isEmpty
            ? context.l10n.mapCustomUrlHint
            : _settings.customUrl,
      ),
      _editCustomUrl,
    ),
    _ActionTile(
      _valueTile(
        context,
        title: context.l10n.mapSubdomains,
        subtitle: _settings.customSubdomains.isEmpty
            ? context.l10n.mapSubdomainsEmpty
            : _settings.customSubdomains,
      ),
      _editCustomSubdomains,
    ),
    _ActionTile(
      _valueTile(
        context,
        title: context.l10n.mapMaxZoom,
        subtitle: '${_settings.customMaxZoom.round()}',
      ),
      _editCustomMaxZoom,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final colors = context.appColors;
        final provider = _provider;
        final light = provider.lightDesigns;
        final dark = provider.darkDesigns;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(context.l10n.settingsMapTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _livePreview(context),
              const SizedBox(height: 14),
              GroupedCardList<MapAppearance>(
                title: context.l10n.mapGroupColors,
                items: MapAppearance.values,
                onTap: (value) =>
                    () => _settings.setAppearance(value),
                itemBuilder: (context, value) => _radioTile(
                  context,
                  title: value.label,
                  subtitle: value.description,
                  selected: _settings.appearance == value,
                ),
              ),
              const SizedBox(height: 14),
              GroupedCardList<MapTileProvider>(
                title: context.l10n.mapGroupTileSource,
                items: mapTileProviders(context.l10n),
                onTap: (value) =>
                    () => _selectProvider(value),
                itemBuilder: _providerTile,
              ),
              if (light.isNotEmpty) ...[
                const SizedBox(height: 14),
                GroupedCardList<MapTileDesign>(
                  title: context.l10n.mapGroupDesignLight(provider.label),
                  items: light,
                  onTap: (design) =>
                      () => _settings.setDesign(provider, design),
                  itemBuilder: _designTile,
                ),
              ],
              if (dark.isNotEmpty) ...[
                const SizedBox(height: 14),
                GroupedCardList<MapTileDesign>(
                  title: context.l10n.mapGroupDesignDark(provider.label),
                  items: dark,
                  onTap: (design) =>
                      () => _settings.setDesign(provider, design),
                  itemBuilder: _designTile,
                ),
              ],
              if (provider.isCustom) ...[
                const SizedBox(height: 14),
                GroupedCardList<_ActionTile>(
                  title: context.l10n.mapGroupCustomSource,
                  items: _customTiles(context),
                  onTap: (tile) => tile.onTap,
                  itemBuilder: (context, tile) => tile.child,
                ),
              ],
              if (provider.needsKey ||
                  provider.id == kCartoProviderId ||
                  provider.isCustom) ...[
                const SizedBox(height: 14),
                GroupedCardList<_ActionTile>(
                  title: context.l10n.mapGroupKeys,
                  items: _keyTiles(context),
                  onTap: (tile) => tile.onTap,
                  itemBuilder: (context, tile) => tile.child,
                ),
              ],
              if (_settings.resolve(dark: _mapDark).retina ||
                  provider.retina) ...[
                const SizedBox(height: 14),
                GroupedCardList<_ActionTile>(
                  title: context.l10n.mapGroupTileDetail,
                  items: [
                    _ActionTile(
                      _switchTile(
                        context,
                        title: context.l10n.mapRetinaTiles,
                        subtitle: context.l10n.mapRetinaTilesSubtitle,
                        value: _settings.retina,
                        onChanged: _settings.setRetina,
                      ),
                    ),
                  ],
                  itemBuilder: (context, tile) => tile.child,
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
