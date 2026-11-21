import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:climbing_map/climbing_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

class _Store implements MapStore {
  final data = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => data[key] = bytes;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

Uint8List _j(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

final _style = {
  'version': 8,
  'sources': {
    'openmaptiles': {'type': 'vector', 'url': 'https://tiles.example/planet'},
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#eeeeee'},
    },
  ],
};

void main() {
  test('the style is kept, so the map draws without signal next time', () async {
    final store = _Store();
    var online = true;
    Future<Uint8List> fetch(Uri u) async {
      if (!online) throw Exception('SocketException: no signal');
      if (u.toString() == osmStyleUrl) return _j(_style);
      if (u.toString() == 'https://tiles.example/planet') {
        return _j({
          'tiles': ['https://tiles.example/v1/{z}/{x}/{y}.pbf'],
          'maxzoom': 14,
        });
      }
      throw Exception('not found');
    }

    final m = await OsmMap.load(store, fetch: fetch);
    expect(m.tiles.template, 'https://tiles.example/v1/{z}/{x}/{y}.pbf');
    online = false;
    final again = await OsmMap.load(store, fetch: fetch);
    expect(again.tiles.maxZoom, 14);
    expect(() => OsmMap.load(_Store(), fetch: fetch), throwsException, reason: 'nothing kept and no signal');
  });

  test('download an area: its tiles at every zoom, then they come from the phone; too big is refused', () async {
    final store = _Store();
    final asked = <String>[];
    final tiles = OsmTiles(
      'https://t/{z}/{x}/{y}.pbf',
      store,
      maxZoom: 14,
      fetch: (u) async {
        asked.add(u.path);
        return Uint8List.fromList([1, 2]);
      },
    );
    // Devín castle, a few hundred metres
    final box = (48.170, 16.970, 48.178, 16.985);
    final want = tiles.tilesIn(box.$1, box.$2, box.$3, box.$4);
    expect(want.first.$1, 6);
    expect(want.last.$1, 14);
    expect(want.length, lessThan(100));
    final steps = <(int, int)>[];
    expect(await tiles.download('Devín', box.$1, box.$2, box.$3, box.$4, progress: (d, n) => steps.add((d, n))), isNull);
    expect(asked.length, want.length);
    expect(steps.last, (want.length, want.length));
    expect((await tiles.areas()).single.name, 'Devín');

    asked.clear();
    final (z, x, y) = want.last;
    expect(await tiles.provide(TileIdentity(z, x, y)), [1, 2]);
    expect(asked, isEmpty, reason: 'from the phone');

    // all of Slovakia is far over the limit
    final big = await tiles.download('SK', 47.7, 16.8, 49.6, 22.6);
    expect(big, contains('too big'));

    await tiles.remove('Devín');
    expect(await tiles.areas(), isEmpty);
    expect(store.data.keys.where((k) => k.startsWith('tiles/')), isEmpty);
  });

  test('removing one area keeps tiles another area still uses', () async {
    final store = _Store();
    final tiles = OsmTiles('https://t/{z}/{x}/{y}.pbf', store, maxZoom: 12, fetch: (u) async => Uint8List.fromList([1]));
    await tiles.download('A', 48.170, 16.970, 48.178, 16.985);
    await tiles.download('B', 48.172, 16.972, 48.176, 16.980);
    await tiles.remove('A');
    final keep = tiles.tilesIn(48.172, 16.972, 48.176, 16.980);
    for (final (z, x, y) in keep) {
      expect(store.data.containsKey(OsmTiles.key(z, x, y)), isTrue);
    }
  });
}
