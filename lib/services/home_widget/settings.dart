import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      _setEnum(v != _theme, () => _theme = v, 'theme', v);
  Future<void> setIconStyle(WidgetIconStyle v) =>
      _setEnum(v != _iconStyle, () => _iconStyle = v, 'icon_style', v);
  Future<void> setBorder(WidgetBorder v) =>
      _setEnum(v != _border, () => _border = v, 'border', v);
  Future<void> setCaptionSize(WidgetCaptionSize v) =>
      _setEnum(v != _captionSize, () => _captionSize = v, 'caption_size', v);
  Future<void> setCaptionShown(bool v) => _set(
    v != _captionShown,
    () => _captionShown = v,
    'caption',
    (prefs, at) => prefs.setBool(at, v),
  );

  /// Four of the five are an enum stored as its [Enum.name], which is how
  /// [readFrom] reads them back. `Enum` rather than a type parameter because
  /// nothing here needs the specific type, and `name` is a member of `Enum` -
  /// so this still chooses the write at compile time, which is the whole
  /// reason [_set] stopped taking an `Object`.
  Future<void> _setEnum(
    bool changed,
    void Function() apply,
    String key,
    Enum v,
  ) => _set(changed, apply, key, (prefs, at) => prefs.setString(at, v.name));

  /// [write] is handed the prefixed key rather than composing it again, so the
  /// one place that knows about [_prefix] is the one place that applies it.
  ///
  /// A callback rather than the `Object` this took before. Five setters pass
  /// four strings and a bool, and dispatching on the runtime type needed a
  /// third branch for everything else - a programmer error that could only be
  /// reported as a storage failure, in a `switch` arm nothing could reach and
  /// no test could cover. Choosing the write at the call site deletes it.
  Future<void> _set(
    bool changed,
    void Function() apply,
    String key,
    Future<bool> Function(SharedPreferences prefs, String at) write,
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
    // Persisted before the push, and the push gated on it. The other order
    // redrew the widget on the home screen immediately, and a Dart write that
    // then failed left sync() pushing the old look back at the next launch -
    // the change undoing itself hours later, with nothing to connect the two.
    // #120. The ordering alone never prevented that, and said it did until
    // #313: a refused write was logged and then pushed, because
    // persistSetting had no way to report one.
    //
    // What the gate covers is **this** push. The field stays applied in
    // memory, deliberately - the control stays where the user put it - and
    // toMap() sends all five, so the next accepted setter carries the refused
    // one to the launcher after all. Closing that means tracking what was
    // last persisted separately from what is on screen, which is a bigger
    // change than #313 and is not made here.
    final at = '$_prefix$key';
    if (!await persistSetting(at, (prefs) => write(prefs, at))) return;
    await push(toMap());
  }
}
