import '../../../../services/localization/l10n.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/logging.dart';
import '../../../../services/prefs_reader.dart';
import 'carto_key.dart';
import 'providers.dart';

export 'providers.dart';

enum MapAppearance {
  auto,
  light,
  dark;

  String get label => switch (this) {
    MapAppearance.auto => l10n.mapAppearanceSystem,
    MapAppearance.light => l10n.mapAppearanceLight,
    MapAppearance.dark => l10n.mapAppearanceDark,
  };

  String get description => switch (this) {
    MapAppearance.auto => l10n.mapAppearanceSystemDesc,
    MapAppearance.light => l10n.mapAppearanceLightDesc,
    MapAppearance.dark => l10n.mapAppearanceDarkDesc,
  };

  static MapAppearance parse(String? raw) => MapAppearance.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => MapAppearance.auto,
  );
}

class MapTileConfig {
  const MapTileConfig({
    required this.urlTemplate,
    required this.subdomains,
    required this.maxZoom,
    required this.retina,
    required this.label,
    required this.attribution,
    required this.usesEmbeddedKey,
    required this.missingKey,
  });

  final String urlTemplate;
  final List<String> subdomains;
  final double maxZoom;
  final bool retina;
  final String label;
  final String attribution;
  final bool usesEmbeddedKey;
  final bool missingKey;
}

class MapSettings extends ChangeNotifier {
  MapSettings._();

  static final MapSettings instance = MapSettings._();

  static const String _prefProvider = 'map.tiles.provider';
  static const String _prefAppearance = 'map.tiles.appearance';
  static const String _prefRetina = 'map.tiles.retina';
  static const String _prefCustomUrl = 'map.tiles.custom.url';
  static const String _prefCustomSubdomains = 'map.tiles.custom.subdomains';
  static const String _prefCustomMaxZoom = 'map.tiles.custom.max_zoom';
  static const String _prefAutoCenter = 'map.follow.auto_center';
  static const String _prefTrackDevice = 'map.follow.track_device';
  static const String _prefScanSubfolders = 'map.scan.subfolders';

  static String _designPref(String provider, bool dark) =>
      'map.tiles.design.$provider.${dark ? 'dark' : 'light'}';

  static String _keyPref(String provider) => 'map.tiles.key.$provider';

  static const double defaultMaxZoom = 19;

  /// The range a value is held to, on the way in and on the way out. It
  /// reaches `TileLayer.maxZoom`, where a zero or a negative is a custom
  /// layer that draws nothing and a negative also throws out of the preview's
  /// `1 << maxZoom.floor()`. The prompt that sets it offers no range of its
  /// own - it is a number field - so these two clamps are the whole of it.
  static const double minCustomZoom = 2;
  static const double maxCustomZoom = 22;

  bool _loaded = false;
  Future<void>? _loading;

  /// Named so [reset] and the fallbacks in [_load] cannot drift from the
  /// initialisers below, which is the drift [reset] exists to prevent.
  static const MapAppearance _defaultAppearance = MapAppearance.auto;
  static const String _defaultCustomUrl = '';
  static const String _defaultCustomSubdomains = '';
  static const bool _defaultRetina = true;
  static const bool _defaultAutoCenter = false;
  static const bool _defaultTrackDevice = false;
  static const bool _defaultScanSubfolders = true;

  /// A getter rather than a const: it needs [l10n], which follows a locale
  /// the user can change while the app runs. Routed through [mapProviderById]
  /// so the initialiser, [reset] and the fallback inside that function are
  /// one expression rather than three copies of "the default is Carto".
  static MapTileProvider get _defaultProvider => mapProviderById(null);

  late MapTileProvider _provider = _defaultProvider;
  MapAppearance _appearance = _defaultAppearance;
  final Map<String, String> _designs = <String, String>{};
  final Map<String, String> _keys = <String, String>{};
  String _customUrl = _defaultCustomUrl;
  String _customSubdomains = _defaultCustomSubdomains;
  double _customMaxZoom = defaultMaxZoom;
  bool _retina = _defaultRetina;
  bool _autoCenter = _defaultAutoCenter;
  bool _trackDevice = _defaultTrackDevice;
  bool _scanSubfolders = _defaultScanSubfolders;

  bool get loaded => _loaded;
  MapTileProvider get provider => _provider;
  MapAppearance get appearance => _appearance;
  String get customUrl => _customUrl;
  String get customSubdomains => _customSubdomains;
  double get customMaxZoom => _customMaxZoom;
  bool get retina => _retina;
  bool get autoCenter => _autoCenter;
  bool get trackDevice => _trackDevice;
  bool get scanSubfolders => _scanSubfolders;

  bool get hasEmbeddedKey => EmbeddedTileKey.available;

  String keyOf(MapTileProvider provider) => _keys[provider.id] ?? '';

  bool hasKey(MapTileProvider provider) {
    if (keyOf(provider).isNotEmpty) return true;
    return provider.id == kCartoProviderId && hasEmbeddedKey;
  }

  MapTileDesign designOf(MapTileProvider provider, {required bool dark}) {
    final stored = provider.designById(
      _designs[_designPref(provider.id, dark)],
    );
    if (stored != null && stored.dark == dark) return stored;
    final pool = dark ? provider.darkDesigns : provider.lightDesigns;
    if (pool.isEmpty) {
      final other = provider.designById(
        _designs[_designPref(provider.id, !dark)],
      );
      if (other != null) return other;
    }
    return provider.defaultDesign(dark: dark);
  }

  /// Reads once per process; later callers await the same read.
  ///
  /// Never throws. This memoises, and all three callers assume it: the map
  /// page and the map settings page both start it unawaited, and the map
  /// controller awaits it ahead of loading files and requesting location - so
  /// a rejection would abort the rest of that initialize, and then be handed
  /// to every later caller for the life of the process. #123.
  ///
  /// The fallback is the Carto provider with no key, so unless the build
  /// carries an embedded one the tile layer is still built and still asks for
  /// tiles, with the key stripped out of the template, and the map page shows
  /// the missing-key notice - a toast that dismisses after three seconds and
  /// is skipped entirely in pick mode. Better than nothing, but the log line
  /// below is what actually keeps the failure.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final PrefsReader reader;
    try {
      reader = PrefsReader(await SharedPreferences.getInstance());
    } catch (e, st) {
      // The only throw in here. It carries a stack when the error is an
      // Error - a TypeError out of the platform decoder, which is the
      // corrupted store this exists for - and none when it is not, which is
      // what a PlatformException from an unopenable store is. LogService
      // .describe is the one place that difference is handled.
      //
      // Nothing below can throw: every value goes through PrefsReader, which
      // cannot, and the two l10n calls cannot either - QLocaleController only
      // ever holds a supported locale, which setLocale now asserts. So the
      // fields are either all read or all left at their initialisers, and
      // "load failed" always means the second.
      //
      // _loading is deliberately left set. getInstance memoises success for
      // the process and drops its memo only on failure, and main() reads
      // preferences through three other controllers before runApp (#124) - so
      // if this fails, the app did not start, and a retry has nothing to
      // retry.
      LogService.warn(
        '[MapSettings] load failed: ${LogService.describe(e, st)}',
      );
      return;
    }

    _provider = mapProviderById(reader.orNull<String>(_prefProvider));
    _appearance = MapAppearance.parse(reader.orNull<String>(_prefAppearance));
    for (final provider in mapTileProviders(l10n)) {
      for (final dark in const [false, true]) {
        final pref = _designPref(provider.id, dark);
        final stored = reader.orNull<String>(pref);
        if (stored != null) _designs[pref] = stored;
      }
      final key = reader.orNull<String>(_keyPref(provider.id));
      if (key != null && key.isNotEmpty) _keys[provider.id] = key;
    }
    _customUrl = reader.or(_prefCustomUrl, _defaultCustomUrl);
    _customSubdomains = reader.or(
      _prefCustomSubdomains,
      _defaultCustomSubdomains,
    );
    // Clamped like the write path. A stored 0 predates this - getDouble
    // read one too - and accepting whole numbers adds a second route to it,
    // so this is closing an old hole rather than one the widening opened.
    _customMaxZoom = reader
        .or(_prefCustomMaxZoom, defaultMaxZoom)
        .clamp(minCustomZoom, maxCustomZoom)
        .toDouble();
    _retina = reader.or(_prefRetina, _defaultRetina);
    _autoCenter = reader.or(_prefAutoCenter, _defaultAutoCenter);
    _trackDevice = reader.or(_prefTrackDevice, _defaultTrackDevice);
    _scanSubfolders = reader.or(_prefScanSubfolders, _defaultScanSubfolders);
    _loaded = true;

    if (reader.mismatched.isNotEmpty) {
      // Once per load rather than once per key, and it names them. Nothing
      // says a stored value was *rejected*: an API key raises the missing-key
      // notice as though none had ever been entered, a custom URL quietly
      // draws OpenStreetMap instead, and the toggles just come back
      // different.
      LogService.warn(
        '[MapSettings] ignored ${reader.mismatched.length} stored '
        'preference(s) of the wrong type: ${reader.mismatched.join(', ')}',
      );
    }
    notifyListeners();
  }

  /// Forgets what was read, so one test does not inherit another's state.
  ///
  /// Without this the first test to drive a failure fixes the result for
  /// every test after it in the same isolate - see [load].
  @visibleForTesting
  void reset() {
    _provider = _defaultProvider;
    _appearance = _defaultAppearance;
    _designs.clear();
    _keys.clear();
    _customUrl = _defaultCustomUrl;
    _customSubdomains = _defaultCustomSubdomains;
    _customMaxZoom = defaultMaxZoom;
    _retina = _defaultRetina;
    _autoCenter = _defaultAutoCenter;
    _trackDevice = _defaultTrackDevice;
    _scanSubfolders = _defaultScanSubfolders;

    _loaded = false;
    _loading = null;
  }

  bool darkFor(bool appDark) => switch (_appearance) {
    MapAppearance.auto => appDark,
    MapAppearance.light => false,
    MapAppearance.dark => true,
  };

  Future<void> setProvider(MapTileProvider value) async {
    if (_provider.id == value.id) return;
    _provider = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProvider, value.id);
  }

  Future<void> setAppearance(MapAppearance value) async {
    if (_appearance == value) return;
    _appearance = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAppearance, value.name);
  }

  Future<void> setDesign(MapTileProvider provider, MapTileDesign design) async {
    final pref = _designPref(provider.id, design.dark);
    if (_designs[pref] == design.id) return;
    _designs[pref] = design.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pref, design.id);
  }

  Future<void> setKey(MapTileProvider provider, String value) async {
    final key = value.trim();
    if (keyOf(provider) == key) return;
    if (key.isEmpty) {
      _keys.remove(provider.id);
    } else {
      _keys[provider.id] = key;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPref(provider.id), key);
  }

  Future<void> setCustomUrl(String value) async {
    final url = value.trim();
    if (_customUrl == url) return;
    _customUrl = url;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomUrl, url);
  }

  Future<void> setCustomSubdomains(String value) async {
    final raw = value.trim();
    if (_customSubdomains == raw) return;
    _customSubdomains = raw;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomSubdomains, raw);
  }

  Future<void> setCustomMaxZoom(double value) async {
    final zoom = value.clamp(minCustomZoom, maxCustomZoom).toDouble();
    if (_customMaxZoom == zoom) return;
    _customMaxZoom = zoom;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefCustomMaxZoom, zoom);
  }

  Future<void> setRetina(bool value) async {
    if (_retina == value) return;
    _retina = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRetina, value);
  }

  Future<void> setAutoCenter(bool value) async {
    if (_autoCenter == value) return;
    _autoCenter = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCenter, value);
  }

  Future<void> setTrackDevice(bool value) async {
    if (_trackDevice == value) return;
    _trackDevice = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefTrackDevice, value);
  }

  Future<void> setScanSubfolders(bool value) async {
    if (_scanSubfolders == value) return;
    _scanSubfolders = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefScanSubfolders, value);
  }

  MapTileConfig resolve({required bool dark}) {
    if (_provider.isCustom) return _customConfig();
    return configFor(_provider, designOf(_provider, dark: dark));
  }

  MapTileConfig configFor(MapTileProvider provider, MapTileDesign design) {
    if (provider.isCustom) return _customConfig();
    var template = design.template ?? provider.template!;
    template = template.replaceAll('{design}', design.id);
    final own = keyOf(provider);
    final embedded = own.isEmpty && provider.id == kCartoProviderId
        ? EmbeddedTileKey.resolveFor(kCartoTileHost)
        : null;
    final key = own.isNotEmpty ? own : (embedded ?? '');
    template = key.isEmpty
        ? template.replaceAll(RegExp(r'[?&][A-Za-z_]+=\{key\}'), '')
        : template.replaceAll('{key}', Uri.encodeQueryComponent(key));
    return MapTileConfig(
      urlTemplate: template,
      subdomains: design.subdomains ?? provider.subdomains,
      maxZoom: design.maxZoom ?? provider.maxZoom,
      retina: design.retina ?? provider.retina,
      label: l10n.mapProviderDesign(provider.label, design.label),
      attribution: provider.attribution,
      usesEmbeddedKey: embedded != null,
      missingKey: provider.needsKey && key.isEmpty,
    );
  }

  MapTileConfig _customConfig() {
    var template = _customUrl.trim();
    if (template.isEmpty) {
      final osm = osmProvider(l10n);
      return configFor(osm, osm.designs.first);
    }
    final key = keyOf(customProvider(l10n));
    if (template.contains('{key}')) {
      template = template.replaceAll('{key}', Uri.encodeQueryComponent(key));
    } else if (key.isNotEmpty) {
      final separator = template.contains('?') ? '&' : '?';
      template =
          '$template${separator}api_key=${Uri.encodeQueryComponent(key)}';
    }
    final subdomains = _customSubdomains
        .split(RegExp(r'[,\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return MapTileConfig(
      urlTemplate: template,
      subdomains: subdomains,
      maxZoom: _customMaxZoom,
      retina: template.contains('{r}'),
      label: Uri.tryParse(template)?.host ?? l10n.mapProviderCustom,
      attribution: '',
      usesEmbeddedKey: false,
      missingKey: false,
    );
  }

  static const double previewLatitude = 48.8584;
  static const double previewLongitude = 2.2945;
  static const int previewZoom = 14;

  String previewUrl(MapTileConfig config) {
    final zoom = math.min(previewZoom, config.maxZoom.floor());
    final scale = 1 << zoom;
    final x = ((previewLongitude + 180) / 360 * scale).floor().clamp(
      0,
      scale - 1,
    );
    final rad = previewLatitude * math.pi / 180;
    final y =
        ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
                2 *
                scale)
            .floor()
            .clamp(0, scale - 1);
    final subdomain = config.subdomains.isEmpty ? '' : config.subdomains.first;
    return config.urlTemplate
        .replaceAll('{s}', subdomain)
        .replaceAll('{z}', '$zoom')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        .replaceAll('{r}', '');
  }
}
