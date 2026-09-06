import 'dart:async';

import 'package:flutter/material.dart';

import '../../../components/archive/category.dart';
import '../../../components/cardlist.dart';
import '../../../components/config.dart';
import '../../../components/icon.dart';
import '../../../services/home_widget/service.dart';
import '../../../services/home_widget/settings.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';

/// Look of the home-screen widgets: every choice is shown as the widget
/// itself, and the preview on top redraws with each tap.
class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  final HomeWidgetSettings _settings = HomeWidgetSettings.instance;
  MaterialPalette? _palette;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
    unawaited(_loadPalette());
  }

  Future<void> _loadPalette() async {
    final palette = await HomeWidgetService.instance.palette();
    if (mounted) setState(() => _palette = palette);
  }

  bool get _systemDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  _Look _look({WidgetTheme? theme, WidgetIconStyle? iconStyle, WidgetBorder? border}) =>
      _Look.build(
        theme: theme ?? _settings.theme,
        iconStyle: iconStyle ?? _settings.iconStyle,
        border: border ?? _settings.border,
        dark: _systemDark,
        palette: _palette,
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final colors = context.appColors;
        final l10n = context.l10n;
        final look = _look();
        final materialAvailable = _palette != null;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: Text(l10n.settingsWidgetsTitle),
            backgroundColor: colors.background,
            surfaceTintColor: colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _group(
                child: _PreviewStrip(
                  look: look,
                  captionShown: _settings.captionShown,
                  captionSize: _settings.captionSize,
                ),
              ),
              const SizedBox(height: 10),
              _group(
                title: l10n.widgetGroupTheme,
                child: _tileRow([
                  for (final t in WidgetTheme.values)
                    _Tile(
                      selected: _settings.theme == t,
                      enabled: t != WidgetTheme.material || materialAvailable,
                      onTap: () => _settings.setTheme(t),
                      child: _MiniWidget(look: _look(theme: t)),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              _group(
                title: l10n.widgetGroupIcon,
                child: _tileRow([
                  for (final s in WidgetIconStyle.values)
                    _Tile(
                      selected: _settings.iconStyle == s,
                      onTap: () => _settings.setIconStyle(s),
                      child: _MiniWidget(look: _look(iconStyle: s)),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              _group(
                title: l10n.widgetGroupBorder,
                child: _tileRow([
                  for (final b in WidgetBorder.values)
                    _Tile(
                      selected: _settings.border == b,
                      onTap: () => _settings.setBorder(b),
                      child: _MiniWidget(look: _look(border: b)),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              _group(
                title: l10n.widgetGroupCaption,
                child: Row(
                  children: [
                    Switch(
                      value: _settings.captionShown,
                      activeThumbColor: colors.accent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: _settings.setCaptionShown,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _tileRow([
                        for (final s in WidgetCaptionSize.values)
                          _Tile(
                            selected: _settings.captionSize == s,
                            enabled: _settings.captionShown,
                            onTap: () => _settings.setCaptionSize(s),
                            child: Text(
                              'Aa',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: _captionPreviewSize(s),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _captionPreviewSize(WidgetCaptionSize s) => switch (s) {
    WidgetCaptionSize.small => 12,
    WidgetCaptionSize.normal => 16,
    WidgetCaptionSize.large => 20,
  };

  Widget _tileRow(List<Widget> tiles) => Row(
    children: [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: tiles[i]),
      ],
    ],
  );

  Widget _group({String? title, required Widget child}) => GroupedCardList<Widget>(
    title: title,
    items: [child],
    cardPadding: const EdgeInsets.all(12),
    itemBuilder: (_, w) => w,
  );
}

/// Resolved colors of one widget — the same rules as `Look` in the native
/// renderer. Every theme takes light or dark from the phone.
class _Look {
  const _Look({
    required this.dark,
    required this.background,
    required this.text,
    required this.plate,
    required this.icon,
    required this.border,
    required this.borderWidth,
  });

  final bool dark;
  final Color background;
  final Color text;
  final Color? plate;
  final Color icon;
  final Color? border;
  final double borderWidth;

  static const Color _lightBackground = Color(0xFFFFFFFF);
  static const Color _darkBackground = Color(0xFF151515);
  static const Color _lightText = Color(0xFF000000);
  static const Color _darkText = Color(0xFFFFFFFF);
  static const Color _lightBorder = Color(0xFFDFDFDF);
  static const Color _darkBorder = Color(0xFF2C2C2C);

  factory _Look.build({
    required WidgetTheme theme,
    required WidgetIconStyle iconStyle,
    required WidgetBorder border,
    required bool dark,
    required MaterialPalette? palette,
  }) {
    if (theme == WidgetTheme.material && palette != null) {
      // One more themed icon on the home screen: the launcher's icon
      // background and icon color, the solid plate inverted.
      final background = Color(dark ? palette.backgroundDark : palette.backgroundLight);
      final foreground = Color(dark ? palette.foregroundDark : palette.foregroundLight);
      return _Look(
        dark: dark,
        background: background,
        text: foreground,
        plate: switch (iconStyle) {
          WidgetIconStyle.solid => foreground,
          WidgetIconStyle.tinted => foreground.withValues(alpha: 0.18),
          WidgetIconStyle.plain => null,
        },
        icon: iconStyle == WidgetIconStyle.solid ? background : foreground,
        border: switch (border) {
          WidgetBorder.none => null,
          WidgetBorder.thin => foreground.withValues(alpha: 0.35),
          WidgetBorder.accent => foreground,
        },
        borderWidth: border == WidgetBorder.accent ? 2 : 1,
      );
    }
    final background = dark ? _darkBackground : _lightBackground;
    final text = dark ? _darkText : _lightText;
    final firmwares = QAppConfig.firmware.firmwares;
    final color = theme == WidgetTheme.system
        ? firmwares
              .firstWhere((f) => f.shortName == (dark ? 'unlshd' : 'ofw'))
              .colors
              .primary
        : ArchiveCategory.nfc.color;
    final plate = switch (iconStyle) {
      WidgetIconStyle.solid => color,
      WidgetIconStyle.tinted => color.withValues(alpha: 0.18),
      WidgetIconStyle.plain => null,
    };
    final icon = switch (iconStyle) {
      WidgetIconStyle.solid => const Color(0xFFFFFFFF),
      WidgetIconStyle.tinted || WidgetIconStyle.plain => color,
    };
    final borderColor = switch (border) {
      WidgetBorder.none => null,
      WidgetBorder.thin => dark ? _darkBorder : _lightBorder,
      WidgetBorder.accent => color,
    };
    return _Look(
      dark: dark,
      background: background,
      text: text,
      plate: plate,
      icon: icon,
      border: borderColor,
      borderWidth: border == WidgetBorder.accent ? 2 : 1,
    );
  }

  /// What the launcher shows behind the widget; the preview sits on it so
  /// the widget reads the way it will on the home screen.
  Color get wallpaper => dark ? const Color(0xFF2B2F36) : const Color(0xFFD9DEE6);

  BoxDecoration box(double radius) => BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(radius),
    border: border == null ? null : Border.all(color: border!, width: borderWidth),
  );
}

/// The three widget sizes side by side, on a stand-in wallpaper.
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.look,
    required this.captionShown,
    required this.captionSize,
  });

  final _Look look;
  final bool captionShown;
  final WidgetCaptionSize captionSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: look.wallpaper,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _WidgetPreview(
              look: look,
              width: 72,
              height: 72,
              badge: 36,
              captionShown: captionShown,
              captionSize: captionSize,
              vertical: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  _WidgetPreview(
                    look: look,
                    width: double.infinity,
                    height: 64,
                    badge: 40,
                    captionShown: captionShown,
                    captionSize: captionSize,
                    vertical: false,
                  ),
                  const SizedBox(height: 12),
                  _WidgetPreview(
                    look: look,
                    width: double.infinity,
                    height: 120,
                    badge: 56,
                    captionShown: captionShown,
                    captionSize: captionSize,
                    vertical: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One widget drawn the way the launcher will draw it.
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({
    required this.look,
    required this.width,
    required this.height,
    required this.badge,
    required this.captionShown,
    required this.captionSize,
    required this.vertical,
  });

  final _Look look;
  final double width;
  final double height;
  final double badge;
  final bool captionShown;
  final WidgetCaptionSize captionSize;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final fontSize = switch (captionSize) {
      WidgetCaptionSize.small => vertical ? 10.0 : 12.0,
      WidgetCaptionSize.normal => vertical ? 11.0 : 14.0,
      WidgetCaptionSize.large => vertical ? 13.0 : 16.0,
    };
    final caption = Text(
      'Office',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: look.text,
        fontSize: fontSize,
        fontWeight: vertical && badge < 50 ? FontWeight.w500 : FontWeight.w700,
      ),
    );
    final plate = _Badge(look: look, size: badge);
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: vertical ? 8 : 12, vertical: 8),
      decoration: look.box(16),
      child: vertical
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                plate,
                if (captionShown) ...[const SizedBox(height: 6), caption],
              ],
            )
          : Row(
              children: [
                plate,
                if (captionShown) ...[
                  const SizedBox(width: 12),
                  Expanded(child: caption),
                ],
              ],
            ),
    );
  }
}

/// The category badge as the app draws it: a rounded square plate with the
/// icon, or the bare icon.
class _Badge extends StatelessWidget {
  const _Badge({required this.look, required this.size});

  final _Look look;
  final double size;

  @override
  Widget build(BuildContext context) {
    final plate = look.plate;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: plate == null
          ? null
          : BoxDecoration(
              color: plate,
              borderRadius: BorderRadius.circular(size * 8 / 36),
            ),
      child: QIcon(
        asset: ArchiveCategory.nfc.asset,
        color: look.icon,
        size: size * 24 / 36,
      ),
    );
  }
}

/// A tiny 1×1 widget as the thumbnail of one choice.
class _MiniWidget extends StatelessWidget {
  const _MiniWidget({required this.look});

  final _Look look;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: look.wallpaper,
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: look.box(10),
            child: _Badge(look: look, size: 26),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
