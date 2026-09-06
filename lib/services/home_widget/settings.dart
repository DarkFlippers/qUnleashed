import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'service.dart';

/// Where the widget takes its colors from. All three follow the phone's
/// light/dark mode for the surface.
enum WidgetTheme {
  /// The app's own theme surfaces, the category color as accent.
  categories,

  /// The firmware looks: dark Unleashed when the phone is dark, light OFW
  /// when it is light.
  system,

  /// The phone's Material You colors throughout.
  material,
}

enum WidgetIconStyle { solid, tinted, plain }

enum WidgetBorder { none, thin, accent }

enum WidgetCaptionSize { small, normal, large }

/// How the home-screen widgets look. Persisted here and mirrored to the
/// native store on every change, which redraws every widget at once.
class HomeWidgetSettings extends ChangeNotifier {
  HomeWidgetSettings._();

  static final HomeWidgetSettings instance = HomeWidgetSettings._();

  static const String _prefix = 'home_widget.';

  bool _loaded = false;
  Future<void>? _loading;

  WidgetTheme _theme = WidgetTheme.categories;
  WidgetIconStyle _iconStyle = WidgetIconStyle.solid;
  WidgetBorder _border = WidgetBorder.none;
  bool _captionShown = true;
  WidgetCaptionSize _captionSize = WidgetCaptionSize.normal;

  bool get loaded => _loaded;
  WidgetTheme get theme => _theme;
  WidgetIconStyle get iconStyle => _iconStyle;
  WidgetBorder get border => _border;
  bool get captionShown => _captionShown;
  WidgetCaptionSize get captionSize => _captionSize;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final raw = prefs.getString('$_prefix$key');
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    _theme = pick(WidgetTheme.values, 'theme', _theme);
    _iconStyle = pick(WidgetIconStyle.values, 'icon_style', _iconStyle);
    _border = pick(WidgetBorder.values, 'border', _border);
    _captionShown = prefs.getBool('${_prefix}caption') ?? _captionShown;
    _captionSize = pick(WidgetCaptionSize.values, 'caption_size', _captionSize);
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  Map<String, Object> toMap() => {
    'theme': _theme.name,
    'iconStyle': _iconStyle.name,
    'border': _border.name,
    'captionShown': _captionShown,
    'captionSize': _captionSize.name,
  };

  /// Sends the current look to the native store, e.g. at app start.
  Future<void> sync() async {
    await load();
    await HomeWidgetService.instance.pushSettings(toMap());
  }

  Future<void> setTheme(WidgetTheme v) => _set(v != _theme, () => _theme = v, 'theme', v.name);
  Future<void> setIconStyle(WidgetIconStyle v) =>
      _set(v != _iconStyle, () => _iconStyle = v, 'icon_style', v.name);
  Future<void> setBorder(WidgetBorder v) => _set(v != _border, () => _border = v, 'border', v.name);
  Future<void> setCaptionShown(bool v) =>
      _set(v != _captionShown, () => _captionShown = v, 'caption', v);
  Future<void> setCaptionSize(WidgetCaptionSize v) =>
      _set(v != _captionSize, () => _captionSize = v, 'caption_size', v.name);

  Future<void> _set(bool changed, void Function() apply, String key, Object value) async {
    if (!changed) return;
    apply();
    notifyListeners();
    await HomeWidgetService.instance.pushSettings(toMap());
    final prefs = await SharedPreferences.getInstance();
    switch (value) {
      case final String s:
        await prefs.setString('$_prefix$key', s);
      case final bool b:
        await prefs.setBool('$_prefix$key', b);
    }
  }
}
