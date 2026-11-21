part of '../climbing_map.dart';

/// The map types: OpenStreetMap (osm.dart; works offline) and Mapy.com's
/// aerial photos (online only, when the build has a Mapy key).
enum MapStyle {
  map('', 'Map'),
  aerial('aerial', 'Aerial photos (online)');

  const MapStyle(this.mapset, this.label);
  final String mapset, label;
}

/// Mapy.com's aerial photos, the one Mapy layer left (the map itself is
/// OpenStreetMap since 21/11, #461, so it can be kept offline). Their terms
/// (§4.6.2) forbid storing, pre-caching or exporting tiles, so there is no
/// offline download: tiles are kept only as long as the server's own
/// Cache-Control allows (one day), like a browser would. The logo and the
/// copyright line must stay visible (§4.4, §4.6.7).
///
/// The key is a public, client-side key, built in with
/// `--dart-define-from-file` from a file outside the repo. It is never
/// written to the app's data or exports.
class MapTiles {
  const MapTiles({required this.mapyKey});

  /// From `--dart-define=MAPY_API_KEY=...`; empty when the build has none.
  factory MapTiles.fromEnvironment() => const MapTiles(mapyKey: String.fromEnvironment('MAPY_API_KEY'));

  final String mapyKey;

  bool get hasKey => mapyKey.isNotEmpty;

  String get urlTemplate => urlFor(MapStyle.aerial);

  /// Tiles of [style]. Every Mapy.com map type costs the same credits.
  String urlFor(MapStyle style) => 'https://api.mapy.com/v1/maptiles/${style.mapset}/256/{z}/{x}/{y}?apikey={key}';

  /// The cache key of a tile: its URL without the API key, so a new key
  /// doesn't throw the cache away.
  static String cacheKey(String url) => BuiltInMapCachingProvider.uuidTileKeyGenerator(url.replaceFirst(RegExp(r'[?&]apikey=[^&]*'), ''));

  static const logoUrl = 'https://api.mapy.com/img/api/logo.svg';
  static const mapyCopyright = '© Seznam.cz a.s. a další';
  static const osmCopyright = '© OpenStreetMap contributors';

  /// Mapy.com's outdoor map around [at], in their own app or website. Uses no
  /// API credits.
  static Uri mapyLink(LatLng at, {int zoom = 17}) =>
      Uri.https('mapy.com', '/fnc/v1/showmap', {'mapset': 'outdoor', 'center': '${at.lng},${at.lat}', 'zoom': '$zoom', 'marker': 'true'});
}
