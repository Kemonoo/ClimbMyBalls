import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/near.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing_map/climbing_map.dart';

Opinion _o(String user, {int stars = 0, List<String> tags = const [], bool project = false, String grade = ''}) =>
    (userId: user, who: user, grade: grade, stars: stars, tags: tags, project: project);

void main() {
  const easy = Place(id: 'e', kind: PlaceKind.problem, name: 'Easy', grade: '5B');
  const hard = Place(id: 'h', kind: PlaceKind.problem, name: 'Hard', grade: '7A+');
  const rope = Place(id: 'r', kind: PlaceKind.problem, name: 'Rope', grade: '8', gradeSystem: GradeSystem.uiaa);

  final s = routeSummaries(
    ['e', 'h', 'r'],
    [
      ('e', _o('me', stars: 4, tags: ['crimps'], project: true)),
      ('e', _o('ema', stars: 2, tags: ['slab'])),
      ('h', _o('ema', stars: 5, grade: '7B')),
      ('h', _o('me', grade: '7B')),
    ],
    {'h'},
    'me',
    routes: {'e': easy, 'h': hard, 'r': rope},
    stars: {'e': 2, 'h': 5},
    ascents: {'h': (tops: 4, flashes: 1)},
  );

  test("summaries: stars (#518), ascents, everyone's tags, your tick and project", () {
    expect((s['e']!.stars, s['e']!.project, s['e']!.topped), (2, true, false));
    expect((s['h']!.tops, s['h']!.flashes, s['e']!.tops), (4, 1, 0));
    expect(s['e']!.tags, {'crimps', 'slab'});
    expect((s['h']!.topped, s['h']!.project), (true, false));
    expect(s['r']!.stars, 0);
    expect((s['e']!.grade, s['h']!.grade), ('', '7B'), reason: 'the community grade once people vote (#468)');
  });

  test('filters: show, grade range per scale, stars, tags', () {
    bool m(RouteFilter f, Place p) => f.matches(p, s[p.id]);
    expect(m(const RouteFilter(), rope), isTrue);
    expect(m(const RouteFilter(show: RouteShow.notTopped), hard), isFalse);
    expect(m(const RouteFilter(show: RouteShow.topped), hard), isTrue);
    expect(m(const RouteFilter(show: RouteShow.projects), easy), isTrue);
    expect(m(const RouteFilter(show: RouteShow.projects), hard), isFalse);
    final from6a = gradeStep('6A', GradeSystem.font);
    expect(m(RouteFilter(fontMin: from6a), easy), isFalse);
    expect(m(RouteFilter(fontMin: from6a), hard), isTrue);
    expect(m(RouteFilter(fontMin: from6a), rope), isTrue, reason: 'a Font bound leaves rope routes alone');
    expect(m(const RouteFilter(minStars: 4), hard), isTrue);
    expect(m(const RouteFilter(minStars: 4), easy), isFalse, reason: 'starred by 2');
    expect(m(const RouteFilter(minStars: 1), rope), isFalse, reason: 'no stars');
    expect(m(const RouteFilter(tags: {'crimps', 'slab'}), easy), isTrue);
    expect(m(const RouteFilter(tags: {'crimps'}), hard), isFalse);
    expect(const RouteFilter(show: RouteShow.topped, minStars: 3, tags: {'a', 'b'}).active, 4);
  });

  test('sorting by stars, ascents and flashes; ties by grade (#518)', () {
    List<String> by(RouteSort x) => [for (final p in sortRoutes([easy, hard, rope], x, summaries: s)) p.id];
    expect(by(RouteSort.stars), ['h', 'e', 'r']);
    expect(by(RouteSort.ascents).first, 'h');
    expect(by(RouteSort.flashes).first, 'h');
    expect(by(RouteSort.grade).where((id) => id != 'r'), ['e', 'h']);
  });
}
