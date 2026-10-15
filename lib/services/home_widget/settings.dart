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

  /// What the next launch will read back, in the preference keys without
  /// [_prefix] - which is why [_fieldFor] exists to translate them.
  ///
  /// Not quite "what the store took": after a read it holds what [readFrom]
  /// resolved, so a key that was absent or unreadable is in here as the
  /// fallback. That is the same value the next launch resolves it to, which
  /// is the property this is for.
  ///
  /// The launcher is drawn from this and not from the fields above. The
  /// fields are what the user chose, and they keep that choice on screen even
  /// when the write was refused - #120's rule, and the one the setters follow.
  /// The native store is a second durable copy that every widget is drawn
  /// from while the app is not running, so what belongs in it is what the
  /// next launch will read back. Sending a refused value would put it on the
  /// home screen for [sync] to take away hours later, which is the whole of
  /// #120.
  final Map<String, Object> _stored = {};

  /// Each setting's preference key, without [_prefix], against the key
  /// [toMap] sends it under.
  ///
  /// Written down once because the two spellings are not derivable from each
  /// other: `caption` is `captionShown`. The other four are snake to camel
  /// and would survive a rule, which is exactly why one key that is not would
  /// have been the bug.
  ///
  /// The native side reads these names and nothing else -
  /// `WidgetSettings.kt` does `map["iconStyle"] as? String ?: base.iconStyle`
  /// - so a misspelling here is read as absent, the launcher keeps the old
  /// value, and nothing corrects it. `a setter after a good read pushes the
  /// whole look` asserts all five.
  static const Map<String, String> _fieldFor = {
    'theme': 'theme',
    'icon_style': 'iconStyle',
    'border': 'border',
    'caption': 'captionShown',
    'caption_size': 'captionSize',
  };

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

    _rememberStored();

    reader.report('[HomeWidgetSettings]');
  }

  /// Takes the shadow from the fields wholesale.
  ///
  /// For the two places the fields are set other than by a write. [readFrom]
  /// is the one that matters and has tests; [resetFields] is belt and braces,
  /// because `reset()` clears [loaded] in the same call and both readers of
  /// the shadow gate on it - so no test can observe that call, and nothing is
  /// missing one. Everywhere else exactly one setting changed and [_set]
  /// updates that entry, after the store has taken it.
  void _rememberStored() {
    _stored
      ..clear()
      ..addAll({
        'theme': _theme.name,
        'icon_style': _iconStyle.name,
        'border': _border.name,
        'caption': _captionShown,
        'caption_size': _captionSize.name,
      });
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
    _rememberStored();

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

  /// What the launcher is told: the stored look, not the look on screen.
  ///
  /// **Empty before a read lands**, because [_stored] is. Both callers gate
  /// on [loaded] first, which is set only after [readFrom] has filled it.
  ///
  /// `_fieldFor[key]!` holds because of the call sites rather than anything
  /// here: [_rememberStored] writes exactly the five keys, and [_set] takes
  /// its key from the five setters below. A sixth setting added without a
  /// [_fieldFor] entry would throw from here, on the push, one step away from
  /// the write that caused it - so the two lists are checked against each
  /// other by `every setter writes its own key`.
  Map<String, Object> toMap() => {
    for (final MapEntry(:key, :value) in _stored.entries)
      _fieldFor[key]!: value,
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
    v,
    (prefs, at, value) => prefs.setBool(at, value),
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
  ) => _set(
    changed,
    apply,
    key,
    v.name,
    (prefs, at, value) => prefs.setString(at, value),
  );

  /// [write] is handed the prefixed key rather than composing it again, so
  /// the one place that knows about [_prefix] is the one place that applies
  /// it, and [stored] so the shadow can move forward without decoding it
  /// back out.
  ///
  /// A callback rather than the `Object` this took before. Five setters pass
  /// four strings and a bool, and dispatching on the runtime type needed a
  /// third branch for everything else - a programmer error that could only be
  /// reported as a storage failure, in a `switch` arm nothing could reach and
  /// no test could cover. The type parameter keeps that choice at compile
  /// time while letting [stored] and [write] agree.
  Future<void> _set<T extends Object>(
    bool changed,
    void Function() apply,
    String key,
    T stored,
    Future<bool> Function(SharedPreferences prefs, String at, T value) write,
  ) async {
    // `changed` is measured against the field, which a refused write leaves
    // holding the user's choice while the shadow keeps the stored one. Taken
    // alone it would make re-picking the same value a no-op, so a setting
    // refused once could not be retried for the rest of the session - the
    // user's only route back would be picking another and picking this again.
    if (!changed && _stored[key] == stored) return;
    if (!loaded) {
      // The same reason [sync] gates its push. The shadow is empty until a
      // read lands, so honouring one tap here would send the native store a
      // single setting in place of a look - and the four it left out are read
      // there as absent, keeping whatever the launcher drew last. The tile
      // does not move either, because the page reads its state from this
      // store, so the control is inert and only the log says why: #124 is
      // what makes this reachable, and it wants a surface before it is.
      LogService.warn('[HomeWidgetSettings] "$key" not applied: never read');
      return;
    }
    apply();
    notifyListeners();
    // Persisted first, and nothing below happens unless the store took it.
    // The other order redrew the widget on the home screen immediately, and a
    // Dart write that then failed left sync() pushing the old look back at
    // the next launch - the change undoing itself hours later, with nothing
    // to connect the two. #120. The ordering alone never prevented that, and
    // said it did until #313: a refused write was logged and then pushed,
    // because persistSetting had no way to report one.
    //
    // Gating this push is not enough on its own. apply() has already put the
    // refused value in the field, deliberately, and before the shadow existed
    // toMap() read the fields - so that value rode out on the next accepted
    // setter's push. The shadow moves forward here instead, after the answer,
    // and never for a write the store did not take.
    final at = '$_prefix$key';
    if (!await persistSetting(at, (prefs) => write(prefs, at, stored))) return;
    _stored[key] = stored;
    await push(toMap());
  }
}
