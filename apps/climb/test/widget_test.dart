import 'dart:io';

import 'package:climb/climb_host.dart';
import 'package:climb/main.dart';
import 'package:climb/storage/text_box_io.dart';
import 'package:climb/shared_places.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing_map/climbing_map.dart';
import 'package:climbing_ui/climbing_ui.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('climb_app'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a logged session is saved as events and is there after a restart', () async {
    final file = EventFile(FileBox(File('${dir.path}/climb_events.json')));
    final host = ClimbAppHost(file);
    host.store.add(ClimbSession.fromJson({
      'id': 's1',
      'start': '2026-11-17T18:00:00.000',
      'place': 'Boulder Bar',
      'source': 'manual',
      'climbs': [
        {'grade': '6B', 'outcome': 'flash', 'angle': 'overhang'},
      ],
    }));
    await Future<void>.delayed(Duration.zero);
    final again = ClimbAppHost(file);
    expect(again.store.sessions.single.place, 'Boulder Bar');
    expect(again.store.sessions.single.climbs.single.grade, '6B');
  });

  testWidgets('the app opens on the climbing screen with no hibi', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    ClimbingHost.instance = ClimbAppHost(EventFile(FileBox(File('${dir.path}/empty.json'))));
    await tester.pumpWidget(const ClimbApp());
    await tester.pump();
    expect(find.text('ClimbMyBalls'), findsOneWidget);
    expect(find.byTooltip('Export for hibi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the map tab is built only when opened (places load at start), and lists them', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    ClimbingHost.instance = ClimbAppHost(EventFile(FileBox(File('${dir.path}/empty.json'))));
    var loads = 0;
    Future<SharedPlaces> places() async {
      loads++;
      return SharedPlaces(bundled: [
        const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'),
        const Place(id: 'devin', parentId: 'sk', kind: PlaceKind.area, name: 'Devín', geometry: PointGeometry(LatLng(48.1745, 16.9790))),
      ]);
    }

    await tester.pumpWidget(MaterialApp(home: ClimbHome(places: places, tiles: const MapTiles(mapyKey: ''))));
    await tester.pump();
    expect(loads, 1, reason: 'places load at start, so ascents reach the Climbs tab');
    expect(find.byType(ClimbMapScreen), findsNothing, reason: 'the map (and its tiles) waits for its tab');
    await tester.tap(find.text('Map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(loads, 1);
    expect(find.byType(ClimbMapScreen), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Devín'), findsOneWidget);
    await tester.tap(find.text('Friends'));
    await tester.pump();
    expect(find.textContaining('no server keys'), findsOneWidget);
    await tester.tap(find.text('Climbs'));
    await tester.pump();
    expect(find.byTooltip('Export for hibi'), findsOneWidget);
  });

  testWidgets('the bundled OpenStreetMap places load', (tester) async {
    final cache = File('${dir.path}/shared.json')..writeAsStringSync('not json');
    final places = await tester.runAsync(() => SharedPlaces.load(cacheFile: FileBox(cache)));
    expect(places!.tree.length, greaterThan(200));
    expect(places.bundled.every((p) => p.licence == 'ODbL'), isTrue);
    expect(places.cache.places, isEmpty); // a broken copy is ignored
  });
}
