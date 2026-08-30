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

const MapTileProvider kCartoProvider = MapTileProvider(
  id: 'carto',
  label: 'CARTO',
  description: 'Voyager, Positron and Dark Matter basemaps',
  attribution: '© OpenStreetMap contributors, © CARTO',
  template:
      'https://{s}.basemaps.cartocdn.com/{design}/{z}/{x}/{y}{r}.png'
      '?api_key={key}',
  subdomains: <String>['a', 'b', 'c', 'd'],
  retina: true,
  keyHint: 'The app ships a key for these tiles',
  signupUrl: 'https://carto.com/basemaps',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'rastertiles/voyager',
      label: 'Voyager',
      description: 'Colored streets, labels on top',
      dark: false,
    ),
    MapTileDesign(
      id: 'rastertiles/voyager_labels_under',
      label: 'Voyager, labels under',
      description: 'Same palette, roads drawn over the labels',
      dark: false,
    ),
    MapTileDesign(
      id: 'rastertiles/voyager_nolabels',
      label: 'Voyager, no labels',
      description: 'Colored streets, nothing written on them',
      dark: false,
    ),
    MapTileDesign(
      id: 'light_all',
      label: 'Positron',
      description: 'Pale grey basemap, pins stand out',
      dark: false,
    ),
    MapTileDesign(
      id: 'light_nolabels',
      label: 'Positron, no labels',
      description: 'Pale grey basemap without names',
      dark: false,
    ),
    MapTileDesign(
      id: 'dark_all',
      label: 'Dark Matter',
      description: 'Black basemap with light labels',
      dark: true,
    ),
    MapTileDesign(
      id: 'dark_nolabels',
      label: 'Dark Matter, no labels',
      description: 'Black basemap without names',
      dark: true,
    ),
  ],
);

const MapTileProvider kOsmProvider = MapTileProvider(
  id: 'osm',
  label: 'OpenStreetMap',
  description: 'Community tiles, no key needed',
  attribution: '© OpenStreetMap contributors',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'standard',
      label: 'Standard',
      description: 'The classic osm.org rendering',
      dark: false,
      template: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    MapTileDesign(
      id: 'de',
      label: 'German style',
      description: 'Softer colors, German label rendering',
      dark: false,
      template: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
      maxZoom: 18,
    ),
    MapTileDesign(
      id: 'hot',
      label: 'Humanitarian',
      description: 'High contrast, built for field mapping',
      dark: false,
      template: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b'],
      maxZoom: 20,
    ),
    MapTileDesign(
      id: 'cyclosm',
      label: 'CyclOSM',
      description: 'Cycling infrastructure and terrain',
      dark: false,
      template:
          'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b', 'c'],
      maxZoom: 20,
    ),
  ],
);

const MapTileProvider kOpenTopoProvider = MapTileProvider(
  id: 'opentopo',
  label: 'OpenTopoMap',
  description: 'Topographic relief with contour lines, no key',
  attribution: '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)',
  subdomains: <String>['a', 'b', 'c'],
  maxZoom: 17,
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'topo',
      label: 'Topographic',
      description: 'Contours, hillshade and trails',
      dark: false,
      template: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: <String>['a', 'b', 'c'],
      maxZoom: 17,
    ),
  ],
);

const MapTileProvider kEsriProvider = MapTileProvider(
  id: 'esri',
  label: 'Esri',
  description: 'Satellite, topo and canvas basemaps, no key',
  attribution: 'Tiles © Esri and the GIS user community',
  template:
      'https://server.arcgisonline.com/ArcGIS/rest/services/{design}'
      '/MapServer/tile/{z}/{y}/{x}',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'World_Imagery',
      label: 'World Imagery',
      description: 'Satellite and aerial photography',
      dark: true,
    ),
    MapTileDesign(
      id: 'World_Street_Map',
      label: 'World Street Map',
      description: 'General purpose street map',
      dark: false,
    ),
    MapTileDesign(
      id: 'World_Topo_Map',
      label: 'World Topo Map',
      description: 'Terrain with roads and place names',
      dark: false,
    ),
    MapTileDesign(
      id: 'Canvas/World_Light_Gray_Base',
      label: 'Light Gray Canvas',
      description: 'Muted backdrop for data on top, up to zoom 16',
      dark: false,
      maxZoom: 16,
    ),
    MapTileDesign(
      id: 'Canvas/World_Dark_Gray_Base',
      label: 'Dark Gray Canvas',
      description: 'Dark muted backdrop for data on top, up to zoom 16',
      dark: true,
      maxZoom: 16,
    ),
  ],
);

const MapTileProvider kStadiaProvider = MapTileProvider(
  id: 'stadia',
  label: 'Stadia Maps',
  description: 'Alidade, Outdoors and the Stamen styles',
  attribution: '© Stadia Maps, © Stamen Design, © OpenMapTiles, © OSM',
  template:
      'https://tiles.stadiamaps.com/tiles/{design}/{z}/{x}/{y}{r}.png'
      '?api_key={key}',
  retina: true,
  maxZoom: 20,
  needsKey: true,
  keyHint: 'Free tier after signing up at stadiamaps.com',
  signupUrl: 'https://client.stadiamaps.com/signup/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'alidade_smooth',
      label: 'Alidade Smooth',
      description: 'Clean light basemap',
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors',
      label: 'Outdoors',
      description: 'Trails, terrain and parks',
      dark: false,
    ),
    MapTileDesign(
      id: 'osm_bright',
      label: 'OSM Bright',
      description: 'Bright general purpose rendering',
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_toner_lite',
      label: 'Stamen Toner Lite',
      description: 'Light high contrast black and white',
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_terrain',
      label: 'Stamen Terrain',
      description: 'Hill shading with soft colors',
      dark: false,
    ),
    MapTileDesign(
      id: 'stamen_watercolor',
      label: 'Stamen Watercolor',
      description: 'Painted look, labels not included',
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
      description: 'Clean dark basemap',
      dark: true,
    ),
    MapTileDesign(
      id: 'stamen_toner',
      label: 'Stamen Toner',
      description: 'Stark black and white',
      dark: true,
    ),
    MapTileDesign(
      id: 'alidade_satellite',
      label: 'Alidade Satellite',
      description: 'Satellite imagery',
      dark: true,
      template:
          'https://tiles.stadiamaps.com/tiles/alidade_satellite'
          '/{z}/{x}/{y}{r}.jpg?api_key={key}',
    ),
  ],
);

const MapTileProvider kThunderforestProvider = MapTileProvider(
  id: 'thunderforest',
  label: 'Thunderforest',
  description: 'OpenCycleMap, Transport, Landscape and friends',
  attribution: 'Maps © Thunderforest, data © OpenStreetMap contributors',
  template:
      'https://{s}.tile.thunderforest.com/{design}/{z}/{x}/{y}.png'
      '?apikey={key}',
  subdomains: <String>['a', 'b', 'c'],
  maxZoom: 22,
  needsKey: true,
  keyHint: 'Free hobby plan at thunderforest.com',
  signupUrl: 'https://www.thunderforest.com/pricing/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'cycle',
      label: 'OpenCycleMap',
      description: 'Cycle routes and contours',
      dark: false,
    ),
    MapTileDesign(
      id: 'transport',
      label: 'Transport',
      description: 'Public transport lines and stops',
      dark: false,
    ),
    MapTileDesign(
      id: 'landscape',
      label: 'Landscape',
      description: 'Terrain, forests and land use',
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors',
      label: 'Outdoors',
      description: 'Hiking and outdoor detail',
      dark: false,
    ),
    MapTileDesign(
      id: 'pioneer',
      label: 'Pioneer',
      description: 'Vintage tinted cartography',
      dark: false,
    ),
    MapTileDesign(
      id: 'neighbourhood',
      label: 'Neighbourhood',
      description: 'Local amenities in pastel colors',
      dark: false,
    ),
    MapTileDesign(
      id: 'atlas',
      label: 'Atlas',
      description: 'Muted reference style',
      dark: false,
    ),
    MapTileDesign(
      id: 'transport-dark',
      label: 'Transport Dark',
      description: 'Dark transport network',
      dark: true,
    ),
    MapTileDesign(
      id: 'spinal-map',
      label: 'Spinal Map',
      description: 'Black and red, turned up to eleven',
      dark: true,
    ),
    MapTileDesign(
      id: 'mobile-atlas',
      label: 'Mobile Atlas',
      description: 'Dark reference style for small screens',
      dark: true,
    ),
  ],
);

const MapTileProvider kMapTilerProvider = MapTileProvider(
  id: 'maptiler',
  label: 'MapTiler',
  description: 'Streets, Topo, Satellite and Dataviz',
  attribution: '© MapTiler, © OpenStreetMap contributors',
  template:
      'https://api.maptiler.com/maps/{design}/{z}/{x}/{y}{r}.png'
      '?key={key}',
  retina: true,
  maxZoom: 22,
  needsKey: true,
  keyHint: 'Free tier key from maptiler.com',
  signupUrl: 'https://cloud.maptiler.com/account/keys/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'streets-v2',
      label: 'Streets',
      description: 'Detailed street cartography',
      dark: false,
    ),
    MapTileDesign(
      id: 'basic-v2',
      label: 'Basic',
      description: 'Simplified base for data on top',
      dark: false,
    ),
    MapTileDesign(
      id: 'bright-v2',
      label: 'Bright',
      description: 'High contrast colorful streets',
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoor-v2',
      label: 'Outdoor',
      description: 'Trails, contours and terrain',
      dark: false,
    ),
    MapTileDesign(
      id: 'topo-v2',
      label: 'Topo',
      description: 'Topographic with relief shading',
      dark: false,
    ),
    MapTileDesign(
      id: 'winter-v2',
      label: 'Winter',
      description: 'Snow-toned outdoor style',
      dark: false,
    ),
    MapTileDesign(
      id: 'dataviz',
      label: 'Dataviz',
      description: 'Neutral light backdrop',
      dark: false,
    ),
    MapTileDesign(
      id: 'satellite',
      label: 'Satellite',
      description: 'Aerial imagery',
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
      description: 'Neutral dark backdrop',
      dark: true,
    ),
    MapTileDesign(
      id: 'toner-v2',
      label: 'Toner',
      description: 'Stark black and white',
      dark: true,
    ),
  ],
);

const MapTileProvider kMapboxProvider = MapTileProvider(
  id: 'mapbox',
  label: 'Mapbox',
  description: 'Streets, Outdoors, Satellite and the day/night pair',
  attribution: '© Mapbox, © OpenStreetMap contributors',
  template:
      'https://api.mapbox.com/styles/v1/mapbox/{design}/tiles/256'
      '/{z}/{x}/{y}{r}?access_token={key}',
  retina: true,
  maxZoom: 22,
  needsKey: true,
  keyHint: 'Public access token from your Mapbox account',
  signupUrl: 'https://account.mapbox.com/access-tokens/',
  designs: <MapTileDesign>[
    MapTileDesign(
      id: 'streets-v12',
      label: 'Streets',
      description: 'The default Mapbox street style',
      dark: false,
    ),
    MapTileDesign(
      id: 'outdoors-v12',
      label: 'Outdoors',
      description: 'Terrain, trails and contours',
      dark: false,
    ),
    MapTileDesign(
      id: 'light-v11',
      label: 'Light',
      description: 'Muted light backdrop',
      dark: false,
    ),
    MapTileDesign(
      id: 'navigation-day-v1',
      label: 'Navigation Day',
      description: 'Driving style, daylight palette',
      dark: false,
    ),
    MapTileDesign(
      id: 'dark-v11',
      label: 'Dark',
      description: 'Muted dark backdrop',
      dark: true,
    ),
    MapTileDesign(
      id: 'navigation-night-v1',
      label: 'Navigation Night',
      description: 'Driving style, night palette',
      dark: true,
    ),
    MapTileDesign(
      id: 'satellite-v9',
      label: 'Satellite',
      description: 'Imagery without labels',
      dark: true,
    ),
    MapTileDesign(
      id: 'satellite-streets-v12',
      label: 'Satellite Streets',
      description: 'Imagery with roads and labels',
      dark: true,
    ),
  ],
);

const MapTileProvider kCustomProvider = MapTileProvider(
  id: 'custom',
  label: 'Custom',
  description: 'Your own tile server',
  attribution: '',
  needsKey: false,
  designs: <MapTileDesign>[],
);

const List<MapTileProvider> kMapTileProviders = <MapTileProvider>[
  kCartoProvider,
  kOsmProvider,
  kOpenTopoProvider,
  kEsriProvider,
  kStadiaProvider,
  kThunderforestProvider,
  kMapTilerProvider,
  kMapboxProvider,
  kCustomProvider,
];

MapTileProvider mapProviderById(String? id) {
  for (final provider in kMapTileProviders) {
    if (provider.id == id) return provider;
  }
  return kCartoProvider;
}
