import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/places/near.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/places/place_tree.dart';
import 'package:test/test.dart';

void main() {
  _grades();
  const devin = LatLng(48.1745, 16.9790), sandberg = LatLng(48.2005, 16.9740), gym = LatLng(48.1600, 17.1200);
  final tree = PlaceTree([
    const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'),
    const Place(id: 'devin', parentId: 'sk', kind: PlaceKind.area, name: 'Devín', geometry: PointGeometry(devin)),
    const Place(id: 'lucka', parentId: 'devin', kind: PlaceKind.boulder, name: 'Lúčka', geometry: PointGeometry(LatLng(48.1748, 16.9786))),
    const Place(id: 'p1', parentId: 'lucka', kind: PlaceKind.problem, name: 'Diagonál', grade: '6C+'),
    const Place(id: 'p2', parentId: 'lucka', kind: PlaceKind.problem, name: 'Zverokruh', grade: '8A'),
    const Place(id: 'sand', parentId: 'sk', kind: PlaceKind.area, name: 'Sandberg', geometry: PointGeometry(sandberg)),
    Place(
      id: 'gym',
      parentId: 'sk',
      kind: PlaceKind.gymWall,
      name: 'Boulder hall',
      indoor: true,
      gradeSystem: GradeSystem.gym('own'),
      geometry: const PointGeometry(gym),
    ),
  ]);

  test('distance and its label', () {
    expect(distanceMetres(devin, devin), 0);
    expect(distanceMetres(devin, sandberg), closeTo(2910, 30));
    expect(distanceLabel(347), '350 m');
    expect(distanceLabel(2910), '2.9 km');
    expect(distanceLabel(24400), '24 km');
  });

  test('near me: nearest first, problems left out, indoor and outdoor filters', () {
    final near = nearMe(tree, const LatLng(48.1750, 16.9785), const PlaceFilter());
    expect(near.map((r) => r.place.id), ['lucka', 'devin', 'sand', 'gym']);
    expect(near.first.metres, lessThan(50));
    expect(nearMe(tree, devin, const PlaceFilter(where: ClimbWhere.indoor)).map((r) => r.place.id), ['gym']);
    expect(nearMe(tree, devin, const PlaceFilter(where: ClimbWhere.outdoor)).map((r) => r.place.id), isNot(contains('gym')));
  });

  test('a grade range keeps places with a problem in it', () {
    final hard = PlaceFilter(minRung: gradeIndex('7C')!);
    expect(hard.anyGrade, isFalse);
    expect(placesOnMap(tree, hard).map((p) => p.id), unorderedEquals(['devin', 'lucka']));
    final easy = PlaceFilter(maxRung: gradeIndex('5C')!);
    expect(placesOnMap(tree, easy), isEmpty);
    expect(const PlaceFilter().anyGrade, isTrue);
  });

  test('search narrows the map, accents ignored', () {
    expect(placesOnMap(tree, const PlaceFilter(query: 'lucka')).map((p) => p.id), ['lucka']);
  });

  test('the top rung is the top of the ladder', () => expect(PlaceFilter.topRung, kGradeLadder.length - 1));

  test('parents: the containing outline first, then nearest, only kinds above', () {
    final t = PlaceTree([
      ...tree.all,
      Place(
        id: 'sector',
        parentId: 'devin',
        kind: PlaceKind.sector,
        name: 'Pod hradom',
        geometry: PolygonGeometry(const [LatLng(48.174, 16.978), LatLng(48.174, 16.980), LatLng(48.176, 16.980), LatLng(48.176, 16.978)]),
      ),
    ]);
    final c = parentCandidates(t, const LatLng(48.175, 16.979), PlaceKind.boulder);
    expect(c.map((r) => r.place.id), ['sector', 'devin', 'sand']);
    expect(parentCandidates(t, const LatLng(48.175, 16.979), PlaceKind.sector).map((r) => r.place.id), ['devin', 'sand']);
    expect(parentCandidates(t, const LatLng(49.5, 19.0), PlaceKind.boulder), isEmpty);
  });

  test('grade span of a place', () {
    expect(gradeSpan(tree, 'devin'), '6C+–8A');
    expect(gradeSpan(tree, 'p1'), '6C+');
    expect(gradeSpan(tree, 'sand'), '');
  });
}

void _grades() {
  test('grades are checked against their scale', () {
    expect(checkGrade('6b+', GradeSystem.font), '6B+');
    expect(checkGrade('fb7a', GradeSystem.font), '7A');
    expect(checkGrade('7A+/B', GradeSystem.font), '7A+/B');
    expect(checkGrade('7B/+', GradeSystem.font), '7B/+');
    expect(checkGrade('7C/', GradeSystem.font), '7C/');
    expect(checkGrade('9+', GradeSystem.font), isNull);
    expect(checkGrade('', GradeSystem.font), isNull);
    expect(checkGrade('9+/10-', GradeSystem.uiaa), '9+/10-');
    expect(checkGrade('10', GradeSystem.uiaa), '10');
    expect(checkGrade('7A', GradeSystem.uiaa), isNull);
    expect(checkGrade('green', GradeSystem.gym('colours')), 'green');
    expect(gradeIndex(checkGrade('7A+/B', GradeSystem.font)!.split('/').first), gradeIndex('7A+'));
  });

  test('grade choices run from easy to hard with in-between grades', () {
    final font = gradeChoices(GradeSystem.font);
    expect(font.first, '3A');
    expect(font.last, '9A+');
    expect(font, containsAllInOrder(['7A+', '7A+/B', '7B', '7C+', '7C+/8A', '8A']));
    final uiaa = gradeChoices(GradeSystem.uiaa);
    expect(uiaa.first, '3-');
    expect(uiaa.last, '12+');
    expect(uiaa, containsAllInOrder(['9', '9+', '9+/10-', '10-']));
    expect(gradeOrder('7A+/B', GradeSystem.font), greaterThan(gradeOrder('7A+', GradeSystem.font)));
    expect(gradeOrder('7C/', GradeSystem.font), gradeOrder('7C', GradeSystem.font));
    expect(gradeOrder('9-/9', GradeSystem.uiaa), gradeOrder('9-', GradeSystem.uiaa));
  });
}
