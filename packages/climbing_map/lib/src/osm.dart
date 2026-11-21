part of '../climbing_map.dart';

/// The map: OpenStreetMap data drawn on the phone from OpenFreeMap's vector
/// tiles and its "liberty" style (#461). Free, no key, and its terms allow
/// downloading areas for offline use: at most 3,000 tiles per download, 4 at
/// a time, with a User-Agent naming the app (openfreemap.org/tos). Tiles you
/// browse are kept by the layer's own cache; downloaded areas are kept in the
/// app's [MapStore] until removed.
const osmStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';
const osmCopyright = '© OpenFreeMap © OpenMapTiles © OpenStreetMap';
const _osmHeaders = {'User-Agent': 'ClimbMyBalls (https://github.com/Kemonoo/ClimbMyBalls)'};

/// Most tiles one offline download may take (OpenFreeMap's limit).
const maxAreaTiles = 3000;

/// Where the map keeps its style and downloaded areas; the app gives one
/// (files on a phone). Null keeps nothing beyond the layer's cache.
abstract class MapStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> delete(String key);
}

/// The style and tiles, ready for a [VectorTileLayer].
class OsmMap {
  OsmMap({required this.theme, required this.sprites, required this.tiles});
  final vt.Theme theme;
  final SpriteStyle? sprites;
  final OsmTiles tiles;

  /// Fetches the style (or uses the last one kept, without signal).
  static Future<OsmMap> load(MapStore? store, {Future<Uint8List> Function(Uri url)? fetch}) async {
    final get = fetch ?? _get;
    Future<Uint8List> kept(String url, String key) async {
      try {
        final b = await get(Uri.parse(url));
        await store?.write(key, b);
        return b;
      } catch (e) {
        final b = await store?.read(key);
        if (b != null) return b;
        rethrow;
      }
    }

    Map<String, dynamic> json(Uint8List b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
    final style = json(await kept(osmStyleUrl, 'style/liberty.json'));
    final source = ((style['sources'] as Map)['openmaptiles'] as Map).cast<String, dynamic>();
    final tilejson = source['tiles'] is List ? source : json(await kept(source['url'] as String, 'style/tiles.json'));
    final template = (tilejson['tiles'] as List).first as String;
    SpriteStyle? sprites;
    try {
      final s = switch (style['sprite']) {
        final String url => url,
        final List l when l.isNotEmpty => (l.first as Map)['url'] as String,
        _ => null,
      };
      if (s != null) {
        final index = json(await kept('$s@2x.json', 'style/sprite.json'));
        final atlas = await kept('$s@2x.png', 'style/sprite.png');
        sprites = SpriteStyle(atlasProvider: () async => atlas, index: vt.SpriteIndexReader().read(index));
      }
    } catch (_) {} // icons are a nicety
    return OsmMap(
      theme: vt.ThemeReader().read(style),
      sprites: sprites,
      tiles: OsmTiles(template, store, maxZoom: (tilejson['maxzoom'] as num?)?.toInt() ?? 14, fetch: get),
    );
  }

  static Future<Uint8List> _get(Uri url) async {
    final r = await http.get(url, headers: _osmHeaders);
    if (r.statusCode != 200) throw ProviderException(message: 'HTTP ${r.statusCode}', statusCode: r.statusCode, retryable: Retryable.none);
    return r.bodyBytes;
  }
}

/// One downloaded area.
typedef OfflineArea = ({String name, double south, double west, double north, double east, int tiles});

/// Vector tiles: from a downloaded area when there is one, else the network.
class OsmTiles extends VectorTileProvider {
  OsmTiles(this.template, this.store, {required this.maxZoom, required this.fetch});
  final String template;
  final MapStore? store;
  final int maxZoom;
  final Future<Uint8List> Function(Uri url) fetch;

  static String key(int z, int x, int y) => 'tiles/$z/$x/$y.pbf';
  Uri url(int z, int x, int y) => Uri.parse(template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y'));

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final kept = await store?.read(key(tile.z, tile.x, tile.y));
    if (kept != null) return kept;
    return fetch(url(tile.z, tile.x, tile.y));
  }

  @override
  int get maximumZoom => maxZoom;
  @override
  int get minimumZoom => 0;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  /// The tiles covering a box, from zoom 6 to the most detailed.
  List<(int, int, int)> tilesIn(double south, double west, double north, double east) => [
    for (var z = 6; z <= maxZoom; z++)
      for (var x = _x(west, z); x <= _x(east, z); x++)
        for (var y = _y(north, z); y <= _y(south, z); y++) (z, x, y),
  ];

  static int _x(double lng, int z) => ((lng + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);
  static int _y(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }

  Future<List<OfflineArea>> areas() async {
    final b = await store?.read('areas.json');
    if (b == null) return [];
    return [
      for (final a in (jsonDecode(utf8.decode(b)) as List).cast<Map>())
        (
          name: a['name'] as String,
          south: (a['south'] as num).toDouble(),
          west: (a['west'] as num).toDouble(),
          north: (a['north'] as num).toDouble(),
          east: (a['east'] as num).toDouble(),
          tiles: (a['tiles'] as num).toInt(),
        ),
    ];
  }

  Future<void> _saveAreas(List<OfflineArea> list) async => store?.write(
    'areas.json',
    Uint8List.fromList(
      utf8.encode(
        jsonEncode([
          for (final a in list) {'name': a.name, 'south': a.south, 'west': a.west, 'north': a.north, 'east': a.east, 'tiles': a.tiles},
        ]),
      ),
    ),
  );

  /// Downloads the map of a box for offline use; [progress] gets (done, all).
  /// Null when it worked, else why not.
  Future<String?> download(String name, double south, double west, double north, double east, {void Function(int done, int total)? progress}) async {
    final s = store;
    if (s == null) return 'Offline maps are not available here.';
    final all = tilesIn(south, west, north, east);
    if (all.length > maxAreaTiles) return 'That area is too big (${all.length} tiles, at most $maxAreaTiles). Zoom in and try again.';
    var done = 0, failed = 0;
    progress?.call(0, all.length);
    for (var i = 0; i < all.length; i += 4) {
      await Future.wait([
        for (final (z, x, y) in all.skip(i).take(4))
          () async {
            if (await s.read(key(z, x, y)) == null) {
              try {
                await s.write(key(z, x, y), await fetch(url(z, x, y)));
              } catch (_) {
                failed++;
              }
            }
            progress?.call(++done, all.length);
          }(),
      ]);
    }
    final list = [...(await areas()).where((a) => a.name != name), (name: name, south: south, west: west, north: north, east: east, tiles: all.length)];
    await _saveAreas(list);
    return failed == 0 ? null : '$failed of ${all.length} map tiles did not download (no signal?). Download it again to fill them in.';
  }

  /// Removes a downloaded area; tiles another area still covers stay.
  Future<void> remove(String name) async {
    final list = await areas();
    final gone = list.where((a) => a.name == name).toList();
    final left = list.where((a) => a.name != name).toList();
    final keep = {for (final a in left) ...tilesIn(a.south, a.west, a.north, a.east)};
    for (final a in gone) {
      for (final t in tilesIn(a.south, a.west, a.north, a.east)) {
        if (!keep.contains(t)) await store?.delete(key(t.$1, t.$2, t.$3));
      }
    }
    await _saveAreas(left);
  }
}
