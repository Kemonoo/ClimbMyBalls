import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:climbing_map/climbing_map.dart';

void main() {
  final tree = PlaceTree([
    const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'),
    const Place(id: 'devin', parentId: 'sk', kind: PlaceKind.area, name: 'Devín', geometry: PointGeometry(LatLng(48.1745, 16.9790))),
    const Place(id: 'lucka', parentId: 'devin', kind: PlaceKind.boulder, name: 'Lúčka', geometry: PointGeometry(LatLng(48.1748, 16.9786))),
    const Place(id: 'p1', parentId: 'lucka', kind: PlaceKind.problem, name: 'Diagonál', grade: '6C+'),
    Place(id: 'gym', parentId: 'sk', kind: PlaceKind.gymWall, name: 'Boulder hall', indoor: true, gradeSystem: GradeSystem.gym('own'), geometry: const PointGeometry(LatLng(48.16, 17.12))),
  ]);

  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ClimbMapScreen(places: tree, locator: const FixedLocator(LatLng(48.1750, 16.9785))))));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('near me lists the closest first; filters and the place sheet work', (t) async {
    await pump(t);
    expect(find.text('Near you'), findsOneWidget);
    expect(find.textContaining('OpenFreeMap'), findsOneWidget); // the map's credit
    final rows = find.byType(ListTile);
    expect(t.widget<ListTile>(rows.first).title, isA<Text>().having((x) => x.data, 'name', 'Lúčka'));

    await t.tap(find.text('Indoor'));
    await t.pump();
    expect(find.widgetWithText(ListTile, 'Lúčka'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Boulder hall'), findsOneWidget);

    await t.tap(find.text('All'));
    await t.pump();
    await t.tap(find.widgetWithText(ListTile, 'Lúčka'));
    await t.pumpAndSettle();
    expect(find.text('Boulder · 6C+'), findsOneWidget);
    expect(find.text('1 problem'), findsOneWidget);
    expect(find.text('Open in Mapy.com'), findsOneWidget);
    await t.tap(find.text('Devín').last); // up the path
    await t.pumpAndSettle();
    expect(find.text('Area · 6C+'), findsOneWidget);
  });

  test('the cache key drops the API key; the Mapy link points at the place', () {
    final a = MapTiles.cacheKey('https://api.mapy.com/v1/maptiles/outdoor/256/13/1/2?apikey=AAA');
    final b = MapTiles.cacheKey('https://api.mapy.com/v1/maptiles/outdoor/256/13/1/2?apikey=BBB');
    expect(a, b);
    expect(MapTiles.mapyLink(const LatLng(48.17, 16.97)).toString(), contains('center=16.97%2C48.17'));
    expect(const MapTiles(mapyKey: '').hasKey, isFalse);
  });
}
