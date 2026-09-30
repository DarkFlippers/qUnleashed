import 'package:flutter/foundation.dart';

import '../settings/persist.dart';
import '../settings/store.dart';

import '../logging.dart';
import '../prefs_reader.dart';
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
class HomeWidgetSettings extends PrefsBackedSettings {
  HomeWidgetSettings._();

  static final HomeWidgetSettings instance = HomeWidgetSettings._();

  static const String _prefix = 'home_widget.';

  /// Named so [reset] and the fallbacks in [_load] cannot drift from the
  /// initialisers below. These are also what the native store ships with, so
  /// a widget drawn from them looks like a fresh install rather than broken.
  static const WidgetTheme _defaultTheme = WidgetTheme.categories;
  static const WidgetIconStyle _defaultIconStyle = WidgetIconStyle.solid;
  static const WidgetBorder _defaultBorder = WidgetBorder.none;
  static const bool _defaultCaptionShown = true;
  static const WidgetCaptionSize _defaultCaptionSize = WidgetCaptionSize.normal;

  WidgetTheme _theme = _defaultTheme;
  WidgetIconStyle _iconStyle = _defaultIconStyle;
  WidgetBorder _border = _defaultBorder;
  bool _captionShown = _defaultCaptionShown;
  WidgetCaptionSize _captionSize = _defaultCaptionSize;

  WidgetTheme get theme => _theme;
  WidgetIconStyle get iconStyle => _iconStyle;
  WidgetBorder get border => _border;
  bool get captionShown => _captionShown;
  WidgetCaptionSize get captionSize => _captionSize;

  @override
  void readFrom(PrefsReader reader) {
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final raw = reader.orNull<String>('$_prefix$key');
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    _theme = pick(WidgetTheme.values, 'theme', _defaultTheme);
    _iconStyle = pick(WidgetIconStyle.values, 'icon_style', _defaultIconStyle);
    _border = pick(WidgetBorder.values, 'border', _defaultBorder);
    _captionShown = reader.or('${_prefix}caption', _defaultCaptionShown);
    _captionSize = pick(
      WidgetCaptionSize.values,
      'caption_size',
      _defaultCaptionSize,
    );

    reader.report('[HomeWidgetSettings]');
  }

  /// [loaded] stays false, which is what [sync] and [_set] check before they
  /// push: the initialisers must not reach the native store.
  @override
  void onLoadFailed(Object error, StackTrace stack) {
    LogService.warn(
      '[HomeWidgetSettings] load failed: ${LogService.describe(error, stack)}',
    );
  }

  @override
  void resetFields() {
    _theme = _defaultTheme;
    _iconStyle = _defaultIconStyle;
    _border = _defaultBorder;
    _captionShown = _defaultCaptionShown;
    _captionSize = _defaultCaptionSize;

    push = HomeWidgetService.instance.pushSettings;
  }

  /// Where [sync] and [_set] send the look.
  ///
  /// A seam rather than a direct call because the alternative - overriding
  /// `HomeWidgetService.supported` - arms six platform entry points to make
  /// one line of behaviour observable, and off Android the rest of them
  /// invoke a channel with no native half. This narrows it to the one call
  /// that matters and lets a test record what was sent.
  @visibleForTesting
  Future<void> Function(Map<String, Object> settings) push =
      HomeWidgetService.instance.pushSettings;

  Map<String, Object> toMap() => {
    'theme': _theme.name,
    'iconStyle': _iconStyle.name,
    'border': _border.name,
    'captionShown': _captionShown,
    'captionSize': _captionSize.name,
  };

  /// Sends the current look to the native store, e.g. at app start.
  ///
  /// Skipped when the read did not land. The native store is a separate,
  /// durable copy that every widget is drawn from, so pushing the defaults
  /// after a failed read would replace the user's look with one they never
  /// chose - and keep doing it at every launch, since the bad state persists.
  /// Leaving the last good look in place loses nothing.
  Future<void> sync() async {
    await load();
    if (!loaded) return;
    await push(toMap());
  }

  Future<void> setTheme(WidgetTheme v) =>
      _set(v != _theme, () => _theme = v, 'theme', v.name);
  Future<void> setIconStyle(WidgetIconStyle v) =>
      _set(v != _iconStyle, () => _iconStyle = v, 'icon_style', v.name);
  Future<void> setBorder(WidgetBorder v) =>
      _set(v != _border, () => _border = v, 'border', v.name);
  Future<void> setCaptionShown(bool v) =>
      _set(v != _captionShown, () => _captionShown = v, 'caption', v);
  Future<void> setCaptionSize(WidgetCaptionSize v) =>
      _set(v != _captionSize, () => _captionSize = v, 'caption_size', v.name);

  Future<void> _set(
    bool changed,
    void Function() apply,
    String key,
    Object value,
  ) async {
    if (!changed) return;
    if (!loaded) {
      // The same reason [sync] gates its push. toMap() sends all five fields,
      // so honouring one tap here would write the other four as initialisers
      // into the native store - the look the user never chose. The tile does
      // not move either, because the page reads its state from this store, so
      // the control is inert and only the log says why: #124 is what makes
      // this reachable, and it wants a surface before it is.
      LogService.warn('[HomeWidgetSettings] "$key" not applied: never read');
      return;
    }
    apply();
    notifyListeners();
    // Persisted before the push, not after. The other order redrew the
    // widget on the home screen immediately, and a Dart write that then
    // failed left sync() pushing the old look back at the next launch - the
    // change undoing itself hours later, with nothing to connect the two.
    // This way a write that fails never reaches the launcher at all. #120.
    await persistSetting('$_prefix$key', (prefs) async {
      switch (value) {
        case final String s:
          await prefs.setString('$_prefix$key', s);
        case final bool b:
          await prefs.setBool('$_prefix$key', b);
      }
    });
    await push(toMap());
  }
}
