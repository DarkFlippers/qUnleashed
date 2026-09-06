import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../components/cardlist.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../archive/map/data/settings.dart';

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

  MapTileProvider get _provider => _settings.provider;

  bool get _mapDark => _settings.darkFor(context.appColors.isDark);

  // ------------------------------------------------------------------ editing

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

  static String _mask(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 8) return '•' * value.length;
    return '${value.substring(0, 4)}${'•' * 6}'
        '${value.substring(value.length - 4)}';
  }

  Widget _appearanceGroup(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kGroupedHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupTitle(context.l10n.mapGroupColors),
          GroupedCard(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                for (final value in MapAppearance.values) ...[
                  Expanded(
                    child: _ChoiceTile(
                      icon: switch (value) {
                        MapAppearance.auto => Icons.brightness_auto_outlined,
                        MapAppearance.light => Icons.light_mode_outlined,
                        MapAppearance.dark => Icons.dark_mode_outlined,
                      },
                      label: value.label,
                      selected: _settings.appearance == value,
                      colors: colors,
                      onTap: () => _settings.setAppearance(value),
                    ),
                  ),
                  if (value != MapAppearance.values.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerRow(BuildContext context, MapTileProvider provider) {
    final colors = context.appColors;
    final selected = _provider.id == provider.id;
    final needsKey = provider.needsKey && !_settings.hasKey(provider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                provider.isCustom && _settings.customUrl.isNotEmpty
                    ? _settings.customUrl
                    : provider.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (needsKey)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.key_outlined, size: 18, color: colors.textMuted),
          ),
        const SizedBox(width: 8),
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 22,
          color: selected ? colors.accent : colors.textMuted,
        ),
      ],
    );
  }

  Widget _styleStrip(
    QAppColors colors, {
    required String title,
    required List<MapTileDesign> designs,
  }) {
    if (designs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kGroupedHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupTitle(title),
          GroupedCard(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: designs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final design = designs[i];
                  final selected =
                      _settings.designOf(_provider, dark: design.dark).id ==
                      design.id;
                  return _StyleTile(
                    label: design.label,
                    url: _settings.previewUrl(
                      _settings.configFor(_provider, design),
                    ),
                    missingKey: _settings
                        .configFor(_provider, design)
                        .missingKey,
                    selected: selected,
                    colors: colors,
                    onTap: () => _settings.setDesign(_provider, design),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueRow(
    BuildContext context, {
    required String title,
    required String value,
    IconData icon = Icons.chevron_right,
  }) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 20, color: colors.textMuted),
      ],
    );
  }

  List<_Row> _keyRows(BuildContext context) {
    final provider = _provider;
    final own = _settings.keyOf(provider);
    final builtIn =
        provider.id == kCartoProviderId &&
        own.isEmpty &&
        _settings.hasEmbeddedKey;
    return [
      _Row(
        _valueRow(
          context,
          title: context.l10n.mapYourProviderKey(provider.label),
          value: own.isNotEmpty
              ? _mask(own)
              : builtIn
              ? context.l10n.mapKeyBuiltIn
              : provider.keyHint ?? context.l10n.mapKeyNotSet,
        ),
        () => _editKey(provider),
      ),
      if (provider.signupUrl != null)
        _Row(
          _valueRow(
            context,
            title: context.l10n.mapGetKey,
            value: Uri.parse(provider.signupUrl!).host,
            icon: Icons.open_in_new,
          ),
          () => launchUrl(
            Uri.parse(provider.signupUrl!),
            mode: LaunchMode.externalApplication,
          ),
        ),
    ];
  }

  List<_Row> _customRows(BuildContext context) => [
    _Row(
      _valueRow(
        context,
        title: context.l10n.mapTileUrlTemplate,
        value: _settings.customUrl.isEmpty
            ? context.l10n.mapCustomUrlHint
            : _settings.customUrl,
      ),
      _editCustomUrl,
    ),
    _Row(
      _valueRow(
        context,
        title: context.l10n.mapSubdomains,
        value: _settings.customSubdomains.isEmpty
            ? context.l10n.mapSubdomainsEmpty
            : _settings.customSubdomains,
      ),
      _editCustomSubdomains,
    ),
    _Row(
      _valueRow(
        context,
        title: context.l10n.mapMaxZoom,
        value: '${_settings.customMaxZoom.round()}',
      ),
      _editCustomMaxZoom,
    ),
  ];

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final colors = context.appColors;
        final provider = _provider;
        final auto = _settings.appearance == MapAppearance.auto;
        final config = _settings.resolve(dark: _mapDark);

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
              _appearanceGroup(colors),
              const SizedBox(height: 14),
              GroupedCardList<MapTileProvider>(
                title: context.l10n.mapGroupTileSource,
                items: mapTileProviders(context.l10n),
                onTap: (value) =>
                    () => _selectProvider(value),
                itemBuilder: _providerRow,
              ),
              // Styles for the mode the map is actually in; in auto both sets
              // matter, because the map follows the app theme.
              if (!provider.isCustom) ...[
                if (auto || !_mapDark) ...[
                  const SizedBox(height: 14),
                  _styleStrip(
                    colors,
                    title: auto
                        ? context.l10n.mapGroupDesignLight(provider.label)
                        : context.l10n.mapGroupStyle(provider.label),
                    designs: provider.lightDesigns,
                  ),
                ],
                if (auto || _mapDark) ...[
                  const SizedBox(height: 14),
                  _styleStrip(
                    colors,
                    title: auto
                        ? context.l10n.mapGroupDesignDark(provider.label)
                        : context.l10n.mapGroupStyle(provider.label),
                    designs: provider.darkDesigns,
                  ),
                ],
              ],
              if (provider.isCustom) ...[
                const SizedBox(height: 14),
                GroupedCardList<_Row>(
                  title: context.l10n.mapGroupCustomSource,
                  items: _customRows(context),
                  onTap: (row) => row.onTap,
                  itemBuilder: (context, row) => row.child,
                ),
              ],
              if (provider.needsKey ||
                  provider.isCustom ||
                  provider.id == kCartoProviderId) ...[
                const SizedBox(height: 14),
                GroupedCardList<_Row>(
                  title: context.l10n.mapGroupKeys,
                  items: _keyRows(context),
                  onTap: (row) => row.onTap,
                  itemBuilder: (context, row) => row.child,
                ),
              ],
              if (config.retina || provider.retina) ...[
                const SizedBox(height: 14),
                GroupedCardList<_Row>(
                  title: context.l10n.mapGroupTileDetail,
                  items: [
                    _Row(
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.mapRetinaTiles,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Switch(
                            value: _settings.retina,
                            onChanged: _settings.setRetina,
                            activeTrackColor: colors.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ],
                  itemBuilder: (context, row) => row.child,
                ),
              ],
              const SizedBox(height: 14),
              GroupedCardList<_Row>(
                title: context.l10n.mapGroupPinScan,
                items: [
                  _Row(
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.mapScanSubfolders,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Switch(
                          value: _settings.scanSubfolders,
                          onChanged: _settings.setScanSubfolders,
                          activeTrackColor: colors.accent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
                itemBuilder: (context, row) => row.child,
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class _Row {
  const _Row(this.child, [this.onTap]);

  final Widget child;
  final VoidCallback? onTap;
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// An icon choice drawn like a style tile, so both pickers read the same way.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.accent.withAlpha(24) : colors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? colors.accent : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? colors.accent : colors.textSecondary,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// One base-map style: its own tile as the thumbnail, name underneath.
class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.label,
    required this.url,
    required this.missingKey,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final String url;
  final bool missingKey;
  final bool selected;
  final QAppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? colors.accent : colors.divider,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: missingKey
                      ? Icon(
                          Icons.key_off_outlined,
                          size: 24,
                          color: colors.textMuted,
                        )
                      : Image.network(
                          url,
                          key: ValueKey(url),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            size: 22,
                            color: colors.textMuted,
                          ),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ),
                        ),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: colors.onAccent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? colors.accent : colors.textSecondary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
