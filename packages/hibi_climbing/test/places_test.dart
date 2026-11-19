import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/places/place_tree.dart';
import 'package:test/test.dart';

void main() {
  _uiaaAndDetails();
  final devin = PolygonGeometry(const [LatLng(48.173, 16.976), LatLng(48.175, 16.980), LatLng(48.171, 16.979)]);
  final places = [
    const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'),
    const Place(id: 'cz', kind: PlaceKind.country, name: 'Czechia'),
    const Place(id: 'ba', parentId: 'sk', kind: PlaceKind.region, name: 'Bratislava'),
    Place(id: 'devin', parentId: 'ba', kind: PlaceKind.area, name: 'Hrad Devín', geometry: devin),
    const Place(id: 'devin-s1', parentId: 'devin', kind: PlaceKind.sector, name: 'Pod hradom'),
    const Place(id: 'b1', parentId: 'devin-s1', kind: PlaceKind.boulder, name: 'Veľký kameň',
        geometry: PointGeometry(LatLng(48.1735, 16.9775))),
    const Place(id: 'p2', parentId: 'b1', kind: PlaceKind.problem, name: 'Zlatá hrana'),
    const Place(id: 'p1', parentId: 'b1', kind: PlaceKind.problem, name: 'Devínska traverza'),
    Place(id: 'gym-wall', parentId: 'ba', kind: PlaceKind.gymWall, name: 'Boulder Bar · Cave',
        indoor: true, gradeSystem: GradeSystem.gym('colours')),
  ];
  final tree = PlaceTree(places);

  test('roots and children come back sorted by name', () {
    expect(tree.roots.map((p) => p.id), ['cz', 'sk']);
    expect(tree.childrenOf('ba').map((p) => p.id), ['gym-wall', 'devin']);
    expect(tree.childrenOf('b1').map((p) => p.name), ['Devínska traverza', 'Zlatá hrana']);
    expect(tree.childrenOf('p1'), isEmpty);
    expect(tree.childrenOf('nope'), isEmpty);
    expect(tree.descendantsOf('devin').map((p) => p.id), ['devin-s1', 'b1', 'p1', 'p2']);
  });

  test('the path runs from the country down to the place', () {
    expect(tree.pathTo('p2').map((p) => p.id), ['sk', 'ba', 'devin', 'devin-s1', 'b1', 'p2']);
    expect(tree.pathLabel('devin'), 'Slovakia › Bratislava › Hrad Devín');
    expect(tree.pathTo('sk').single.id, 'sk');
    expect(tree.pathTo('nope'), isEmpty);
  });

  test('search ignores case and accents, puts prefix matches and higher places first', () {
    expect(tree.search('devin').map((p) => p.id), ['devin', 'p1']);
    expect(tree.search('DEVÍN TRAV').map((p) => p.id), ['p1']);
    expect(tree.search('hrad').map((p) => p.id), ['devin', 'devin-s1']); // "Hrad Devín" prefix, "Pod hradom" word prefix
    expect(tree.search('kamen').single.id, 'b1');
    expect(tree.search('a', kinds: {PlaceKind.country}).map((p) => p.id), ['cz', 'sk']);
    expect(tree.search('cave', indoor: false), isEmpty);
    expect(tree.search('cave', indoor: true).single.id, 'gym-wall');
    expect(tree.search('   '), isEmpty);
    expect(tree.search('a', limit: 2), hasLength(2));
  });

  test('a missing parent or a loop makes the place a root instead of losing it', () {
    final odd = PlaceTree(const [
      Place(id: 'lost', parentId: 'gone', kind: PlaceKind.boulder, name: 'Lost boulder'),
      Place(id: 'x', parentId: 'y', kind: PlaceKind.area, name: 'X'),
      Place(id: 'y', parentId: 'x', kind: PlaceKind.area, name: 'Y'),
    ]);
    expect(odd.roots.map((p) => p.id), ['lost', 'x', 'y']);
    expect(odd.pathTo('lost').single.id, 'lost');
    expect(odd.pathTo('x').single.id, 'x');
  });

  test('grade systems: Font by default, a named scale for gyms', () {
    expect(tree['p1']!.gradeSystem, GradeSystem.font);
    expect(tree['p1']!.indoor, isFalse);
    final gym = tree['gym-wall']!.gradeSystem;
    expect(gym.isFont, isFalse);
    expect(gym.gymScale, 'colours');
    expect(GradeSystem.fromId('gym:colours'), gym);
    expect(GradeSystem.fromId(null), GradeSystem.font);
  });

  test('geometry: a point is its own centre, a polygon needs 3 vertices', () {
    expect(tree['b1']!.geometry!.centre, const LatLng(48.1735, 16.9775));
    final c = devin.centre;
    expect(c.lat, closeTo(48.173, 1e-9));
    expect(c.lng, closeTo(16.97833, 1e-4));
    expect(() => PolygonGeometry(const [LatLng(0, 0), LatLng(1, 1)]), throwsArgumentError);
  });

  test('JSON round trip keeps every field', () {
    for (final p in places) {
      final back = Place.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
    }
    final gym = Place.fromJson(places.last.toJson());
    expect(gym.indoor, isTrue);
    expect(gym.gradeSystem.gymScale, 'colours');
    final area = Place.fromJson(places[3].toJson());
    expect((area.geometry as PolygonGeometry).ring, devin.ring);
  });
}

void _uiaaAndDetails() {
  test('UIAA scale and optional details survive JSON', () {
    const p = Place(id: 'p', kind: PlaceKind.problem, name: 'Dunaj', gradeSystem: GradeSystem.uiaa, grade: '9+/10-', details: {'sit': true, 'note': 'start N, up to X', 'uncertain': true});
    final back = Place.fromJson(p.toJson());
    expect(back.gradeSystem, GradeSystem.uiaa);
    expect(back.gradeSystem.gymScale, isNull);
    expect((back.grade, back.sitStart, back.note, back.gradeUncertain), ('9+/10-', true, 'start N, up to X', true));
    expect(GradeSystem.fromId('uiaa').isUiaa, isTrue);
    expect(GradeSystem.fromId('Boulder Bar').gymScale, 'Boulder Bar');
    expect(const Place(id: 'x', kind: PlaceKind.area, name: 'X').toJson().containsKey('details'), isFalse);
    expect(p.copyWith(name: 'Dunaj direkt').details['sit'], true);
  });
}
