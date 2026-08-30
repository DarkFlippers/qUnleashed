/// Basemap key for [kCartoTileHost], injected at build time from a CI secret
/// (`--dart-define=QU_CARTO_KEY=...`). It is never stored in the repository.
const String _buildKey = String.fromEnvironment('QU_CARTO_KEY');

const String kCartoTileHost = 'basemaps.cartocdn.com';

class EmbeddedTileKey {
  const EmbeddedTileKey._();

  static bool get available => _buildKey.isNotEmpty;

  /// Only the built-in CARTO basemaps may use this key; every other source
  /// runs on the key the user typed in, or on none at all.
  static String? resolveFor(String host) {
    if (host != kCartoTileHost || _buildKey.isEmpty) return null;
    return _buildKey;
  }
}
