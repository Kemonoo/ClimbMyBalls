import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:climb/shared_places.dart';
import 'package:climb/storage/photo_box.dart';
import 'package:climb/storage/text_box.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/topo.dart';
import 'package:climbing_cloud/climbing_cloud.dart';

class _Box implements TextBox {
  String? text;
  @override
  String? read() => text;
  @override
  void write(String t) => text = t;
}

CloudTopo _topo(String id, String place) => CloudTopo(
  topo: Topo(id: id, placeId: place, photoPath: '$id/photo.jpg', width: 400, height: 300, createdBy: 'u'),
  updatedAt: DateTime.utc(2026, 11, 21),
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('climb_photos'));
  tearDown(() => dir.deleteSync(recursive: true));

  SharedPlaces make(Future<Uint8List> Function(Uri) fetch, _Box file) => SharedPlaces(
    bundled: const [
      Place(id: 'a', kind: PlaceKind.area, name: 'Devín'),
      Place(id: 'b', parentId: 'a', kind: PlaceKind.boulder, name: 'Lúčka'),
      Place(id: 'c', parentId: 'a', kind: PlaceKind.boulder, name: 'Jaskynka'),
      Place(id: 'x', kind: PlaceKind.area, name: 'Elsewhere'),
    ],
    cloud: ClimbCloud(SupabaseClient('https://example.supabase.co', 'public-key')),
    cacheFile: file,
    photos: PhotoBox(dir),
    topos: TopoCache([_topo('t1', 'b'), _topo('t2', 'c'), _topo('t3', 'x')]),
    fetch: fetch,
  );

  test('saving an area downloads the photos of everything in it; they then open from the phone', () async {
    final asked = <String>[];
    final file = _Box();
    final p = make((u) async {
      asked.add(u.path);
      return Uint8List.fromList([1, 2, 3]);
    }, file);
    final steps = <(int, int)>[];
    expect(p.isOffline('b'), isFalse);
    expect(await p.keep('a', progress: (d, n) => steps.add((d, n))), isNull);
    expect(asked.length, 2, reason: 't1 and t2, not t3 in another area');
    expect(steps.last, (2, 2));
    expect(p.isOffline('a'), isTrue);
    expect(p.isOffline('b'), isTrue, reason: 'inside a saved place');
    expect(p.isOffline('x'), isFalse);
    expect(p.photoOf('t1/photo.jpg'), isA<FileImage>());
    expect((jsonDecode(file.text!) as Map)['offline'], ['a']);

    // updating fetches only what is missing
    asked.clear();
    expect(await p.keep('a'), isNull);
    expect(asked, isEmpty);

    await p.forget('a');
    expect(p.isOffline('b'), isFalse);
    expect(PhotoBox(dir).has('t1/photo.jpg'), isFalse);
  });

  test('no signal: what arrived is kept, and it says how many photos are missing', () async {
    var n = 0;
    final p = make((u) async {
      if (n++ == 0) throw const SocketException('no signal');
      return Uint8List.fromList([1]);
    }, _Box());
    final err = await p.keep('a');
    expect(err, contains('1 of 2 photos did not download'));
    expect(p.isOffline('a'), isTrue);
    expect(await p.keep('a'), isNull, reason: 'Update fetches the missing one');
  });
}
