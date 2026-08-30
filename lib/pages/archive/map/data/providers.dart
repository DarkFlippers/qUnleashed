import '../../../../services/localization/l10n.dart';

const String kCartoProviderId = 'carto';

class MapTileDesign {
  const MapTileDesign({
    required this.id,
    required this.label,
    required this.description,
    required this.dark,
    this.template,
    this.subdomains,
    this.maxZoom,
    this.retina,
  });

  final String id;
  final String label;
  final String description;
  final bool dark;
  final String? template;
  final List<String>? subdomains;
  final double? maxZoom;
  final bool? retina;
}

class MapTileProvider {
  const MapTileProvider({
    required this.id,
    required this.label,
    required this.description,
    required this.attribution,
    required this.designs,
    this.template,
    this.subdomains = const <String>[],
    this.maxZoom = 19,
    this.retina = false,
    this.needsKey = false,
    this.keyHint,
    this.signupUrl,
  });

  final String id;
  final String label;
  final String description;
  final String attribution;
  final List<MapTileDesign> designs;
  final String? template;
  final List<String> subdomains;
  final double maxZoom;
  final bool retina;
  final bool needsKey;
  final String? keyHint;
  final String? signupUrl;

  bool get isCustom => id == 'custom';

  List<MapTileDesign> get lightDesigns =>
      designs.where((design) => !design.dark).toList();

  List<MapTileDesign> get darkDesigns =>
      designs.where((design) => design.dark).toList();

  MapTileDesign? designById(String? id) {
    for (final design in designs) {
      if (design.id == id) return design;
    }
    return null;
  }

  MapTileDesign defaultDesign({required bool dark}) {
    for (final design in designs) {
      if (design.dark == dark) return design;
    }
    return designs.first;
  }
}

MapTileProvider cartoProvider(L10n s) => MapTileProvider(
  id: 'carto',
  label: 'CARTO',
  description: s.mapProviderCartoDesc,
  attribution: '© OpenStreetMap contributors, © CARTO',
  template:
      'https://{s}.basemaps.cartocdn.com/{design}/{z}/{x}/{y}{r}.png'
      '?key={key}',
  subdomains: <String>['a', 'b', 'c', 'd'],
  retina: true,
  keyHint: s.mapKeyHintCarto,
  signupUrl: 'https://carto.com/basemaps',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'rastertiles/voyager',
      label: 'Voyager',
      description: s.mapDesignVoyagerDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'rastertiles/voyager_labels_under',
      label: 'Voyager, labels under',
      description: s.mapDesignVoyagerLabelsUnderDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'rastertiles/voyager_nolabels',
      label: 'Voyager, no labels',
      description: s.mapDesignVoyagerNoLabelsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'light_all',
      label: 'Positron',
      description: s.mapDesignPositronDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'light_nolabels',
      label: 'Positron, no labels',
      description: s.mapDesignPositronNoLabelsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'dark_all',
      label: 'Dark Matter',
      description: s.mapDesignDarkMatterDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'dark_nolabels',
      label: 'Dark Matter, no labels',
      description: s.mapDesignDarkMatterNoLabelsDesc,
      dark: true,
    ),
  ],
);

MapTileProvider osmProvider(L10n s) => MapTileProvider(
  id: 'osm',
  label: 'OpenStreetMap',
  description: s.mapProviderOsmDesc,
  attribution: '© OpenStreetMap contributors',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'standard',
      label: 'Standard',
      description: s.mapDesignOsmStandardDesc,
      dark: false,
      template: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    MapTileDesign(
      id: 'de',
      label: 'German style',
      description: s.mapDesignOsmGermanDesc,
      dark: false,
      template: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
      maxZoom: 18,
    ),
    MapTileDesign(
      id: 'hot',
      label: 'Humanitarian',
      description: s.mapDesignOsmHotDesc,
      dark: false,
      template: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b'],
      maxZoom: 20,
    ),
    MapTileDesign(
      id: 'cyclosm',
      label: 'CyclOSM',
      description: s.mapDesignCyclOsmDesc,
      dark: false,
      template:
          'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b', 'c'],
      maxZoom: 20,
    ),
  ],
);

MapTileProvider openTopoProvider(L10n s) => MapTileProvider(
  id: 'opentopo',
  label: 'OpenTopoMap',
  description: s.mapProviderOpenTopoDesc,
  attribution: '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)',
  subdomains: <String>['a', 'b', 'c'],
  maxZoom: 17,
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'topo',
      label: 'Topographic',
      description: s.mapDesignTopographicDesc,
      dark: false,
      template: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b', 'c'],
      maxZoom: 17,
    ),
  ],
);

MapTileProvider esriProvider(L10n s) => MapTileProvider(
  id: 'esri',
  label: 'Esri',
  description: s.mapProviderEsriDesc,
  attribution: 'Tiles © Esri and the GIS user community',
  template:
      'https://server.arcgisonline.com/ArcGIS/rest/services/{design}'
      '/MapServer/tile/{z}/{y}/{x}',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'World_Imagery',
      label: 'World Imagery',
      description: s.mapDesignEsriImageryDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'World_Street_Map',
      label: 'World Street Map',
      description: s.mapDesignEsriStreetsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'World_Topo_Map',
      label: 'World Topo Map',
      description: s.mapDesignEsriTopoDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'Canvas/World_Light_Gray_Base',
      label: 'Light Gray Canvas',
      description: s.mapDesignEsriLightCanvasDesc,
      dark: false,
      maxZoom: 16,
    ),
    MapTileDesign(
      id: 'Canvas/World_Dark_Gray_Base',
      label: 'Dark Gray Canvas',
      description: s.mapDesignEsriDarkCanvasDesc,
      dark: true,
      maxZoom: 16,
    ),
  ],
);

MapTileProvider stadiaProvider(L10n s) => MapTileProvider(
  id: 'stadia',
  label: 'Stadia Maps',
  description: s.mapProviderStadiaDesc,
  attribution: '© Stadia Maps, © Stamen Design, © OpenMapTiles, © OSM',
  template:
      'https://tiles.stadiamaps.com/tiles/{design}/{z}/{x}/{y}{r}.png'
      '?api_key={key}',
  retina: true,
  maxZoom: 20,
  needsKey: true,
  keyHint: s.mapKeyHintStadia,
  signupUrl: 'https://client.stadiamaps.com/signup/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'alidade_smooth',
      label: 'Alidade Smooth',
      description: s.mapDesignAlidadeSmoothDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors',
      label: 'Outdoors',
      description: s.mapDesignStadiaOutdoorsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'osm_bright',
      label: 'OSM Bright',
      description: s.mapDesignOsmBrightDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_toner_lite',
      label: 'Stamen Toner Lite',
      description: s.mapDesignStamenTonerLiteDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_terrain',
      label: 'Stamen Terrain',
      description: s.mapDesignStamenTerrainDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_watercolor',
      label: 'Stamen Watercolor',
      description: s.mapDesignStamenWatercolorDesc,
      dark: false,
      template:
          'https://tiles.stadiamaps.com/tiles/stamen_watercolor'
          '/{z}/{x}/{y}.jpg?api_key={key}',
      maxZoom: 16,
      retina: false,
    ),
    MapTileDesign(
      id: 'alidade_smooth_dark',
      label: 'Alidade Smooth Dark',
      description: s.mapDesignAlidadeSmoothDarkDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'stamen_toner',
      label: 'Stamen Toner',
      description: s.mapDesignStamenTonerDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'alidade_satellite',
      label: 'Alidade Satellite',
      description: s.mapDesignAlidadeSatelliteDesc,
      dark: true,
      template:
          'https://tiles.stadiamaps.com/tiles/alidade_satellite'
          '/{z}/{x}/{y}{r}.jpg?api_key={key}',
    ),
  ],
);

MapTileProvider thunderforestProvider(L10n s) => MapTileProvider(
  id: 'thunderforest',
  label: 'Thunderforest',
  description: s.mapProviderThunderforestDesc,
  attribution: 'Maps © Thunderforest, data © OpenStreetMap contributors',
  template:
      'https://{s}.tile.thunderforest.com/{design}/{z}/{x}/{y}.png'
      '?apikey={key}',
  subdomains: <String>['a', 'b', 'c'],
  maxZoom: 22,
  needsKey: true,
  keyHint: s.mapKeyHintThunderforest,
  signupUrl: 'https://www.thunderforest.com/pricing/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'cycle',
      label: 'OpenCycleMap',
      description: s.mapDesignOpenCycleMapDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'transport',
      label: 'Transport',
      description: s.mapDesignTransportDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'landscape',
      label: 'Landscape',
      description: s.mapDesignLandscapeDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors',
      label: 'Outdoors',
      description: s.mapDesignThunderforestOutdoorsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'pioneer',
      label: 'Pioneer',
      description: s.mapDesignPioneerDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'neighbourhood',
      label: 'Neighbourhood',
      description: s.mapDesignNeighbourhoodDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'atlas',
      label: 'Atlas',
      description: s.mapDesignAtlasDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'transport-dark',
      label: 'Transport Dark',
      description: s.mapDesignTransportDarkDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'spinal-map',
      label: 'Spinal Map',
      description: s.mapDesignSpinalMapDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'mobile-atlas',
      label: 'Mobile Atlas',
      description: s.mapDesignMobileAtlasDesc,
      dark: true,
    ),
  ],
);

MapTileProvider mapTilerProvider(L10n s) => MapTileProvider(
  id: 'maptiler',
  label: 'MapTiler',
  description: s.mapProviderMapTilerDesc,
  attribution: '© MapTiler, © OpenStreetMap contributors',
  template:
      'https://api.maptiler.com/maps/{design}/{z}/{x}/{y}{r}.png'
      '?key={key}',
  retina: true,
  maxZoom: 22,
  needsKey: true,
  keyHint: s.mapKeyHintMapTiler,
  signupUrl: 'https://cloud.maptiler.com/account/keys/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'streets-v2',
      label: 'Streets',
      description: s.mapDesignMapTilerStreetsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'basic-v2',
      label: 'Basic',
      description: s.mapDesignMapTilerBasicDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'bright-v2',
      label: 'Bright',
      description: s.mapDesignMapTilerBrightDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoor-v2',
      label: 'Outdoor',
      description: s.mapDesignMapTilerOutdoorDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'topo-v2',
      label: 'Topo',
      description: s.mapDesignMapTilerTopoDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'winter-v2',
      label: 'Winter',
      description: s.mapDesignMapTilerWinterDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'dataviz',
      label: 'Dataviz',
      description: s.mapDesignMapTilerDatavizDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'satellite',
      label: 'Satellite',
      description: s.mapDesignMapTilerSatelliteDesc,
      dark: true,
      template:
          'https://api.maptiler.com/maps/satellite/{z}/{x}/{y}.jpg'
          '?key={key}',
      maxZoom: 20,
      retina: false,
    ),
    MapTileDesign(
      id: 'dataviz-dark',
      label: 'Dataviz Dark',
      description: s.mapDesignMapTilerDatavizDarkDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'toner-v2',
      label: 'Toner',
      description: s.mapDesignMapTilerTonerDesc,
      dark: true,
    ),
  ],
);

MapTileProvider mapboxProvider(L10n s) => MapTileProvider(
  id: 'mapbox',
  label: 'Mapbox',
  description: s.mapProviderMapboxDesc,
  attribution: '© Mapbox, © OpenStreetMap contributors',
  template:
      'https://api.mapbox.com/styles/v1/mapbox/{design}/tiles/256'
      '/{z}/{x}/{y}{r}?access_token={key}',
  retina: true,
  maxZoom: 22,
  needsKey: true,
  keyHint: s.mapKeyHintMapbox,
  signupUrl: 'https://account.mapbox.com/access-tokens/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'streets-v12',
      label: 'Streets',
      description: s.mapDesignMapboxStreetsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors-v12',
      label: 'Outdoors',
      description: s.mapDesignMapboxOutdoorsDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'light-v11',
      label: 'Light',
      description: s.mapDesignMapboxLightDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'navigation-day-v1',
      label: 'Navigation Day',
      description: s.mapDesignMapboxNavigationDayDesc,
      dark: false,
    ),
    MapTileDesign(
      id: 'dark-v11',
      label: 'Dark',
      description: s.mapDesignMapboxDarkDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'navigation-night-v1',
      label: 'Navigation Night',
      description: s.mapDesignMapboxNavigationNightDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'satellite-v9',
      label: 'Satellite',
      description: s.mapDesignMapboxSatelliteDesc,
      dark: true,
    ),
    MapTileDesign(
      id: 'satellite-streets-v12',
      label: 'Satellite Streets',
      description: s.mapDesignMapboxSatelliteStreetsDesc,
      dark: true,
    ),
  ],
);

MapTileProvider customProvider(L10n s) => MapTileProvider(
  id: 'custom',
  label: s.mapProviderCustom,
  description: s.mapProviderCustomDesc,
  attribution: '',
  needsKey: false,
  designs: <MapTileDesign>[],
);

List<MapTileProvider> mapTileProviders(L10n s) => <MapTileProvider>[
  cartoProvider(s),
  osmProvider(s),
  openTopoProvider(s),
  esriProvider(s),
  stadiaProvider(s),
  thunderforestProvider(s),
  mapTilerProvider(s),
  mapboxProvider(s),
  customProvider(s),
];

MapTileProvider mapProviderById(String? id) {
  final s = l10n;
  for (final provider in mapTileProviders(s)) {
    if (provider.id == id) return provider;
  }
  return cartoProvider(s);
}
