import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/events.dart';
import 'package:test/test.dart';

void main() {
  ClimbSession session(String id, String start, {bool outdoor = false, required List<Climb> climbs}) =>
      ClimbSession(id: id, start: DateTime.parse(start), outdoor: outdoor, place: outdoor ? 'Devín' : 'Boulder Bar', climbs: climbs);

  final crag = session('o1', '2026-11-15T10:00:00', outdoor: true, climbs: [
    Climb(grade: '6B', outcome: ClimbOutcome.sent, problemId: 'p1'),
    Climb(grade: '6A', outcome: ClimbOutcome.tried),
  ]);
  final crag2 = session('o2', '2026-11-16T10:00:00', outdoor: true, climbs: [Climb(grade: '6B', outcome: ClimbOutcome.flash, problemId: 'p1', repeat: true)]);
  final gym = session('i1', '2026-11-14T18:00:00', climbs: [Climb(grade: '6A+', outcome: ClimbOutcome.sent, gymGrade: 'yellow')]);

  test('a tick keeps its problem and gym grade through JSON, and old JSON reads as before', () {
    final back = ClimbSession.fromJson(crag.toJson());
    expect(back.climbs.first.problemId, 'p1');
    expect(back.climbs.last.problemId, isNull);
    expect(ClimbSession.fromJson(gym.toJson()).climbs.single.gymGrade, 'yellow');
    final old = Climb.fromJson({'grade': '6A', 'outcome': 'sent', 'angle': 'vertical'});
    expect(old.problemId, isNull);
    expect(old.gymGrade, '');
    expect(old.toJson().containsKey('problem'), isFalse);
    expect(old.toJson().containsKey('gymGrade'), isFalse);
  });

  test('outdoor shows Font, indoor shows the gym scale when known; points stay Font', () {
    final g = gym.climbs.single;
    expect(g.shownGrade(outdoor: false), 'yellow');
    expect(g.shownGrade(outdoor: true), '6A+');
    expect(crag.climbs.first.shownGrade(outdoor: false), '6B');
    expect(g.points, Climb(grade: '6A+', outcome: ClimbOutcome.sent).points);
  });

  test('indoor and outdoor filter sessions apart', () {
    final all = [gym, crag, crag2];
    expect(all.where(ClimbWhere.indoor.has).map((s) => s.id), ['i1']);
    expect(all.where(ClimbWhere.outdoor.has).map((s) => s.id), ['o1', 'o2']);
    expect(all.where(ClimbWhere.all.has), hasLength(3));
  });

  test('ticks on a problem, oldest first', () {
    final t = ticksOn('p1', [crag2, gym, crag]);
    expect(t.map((x) => x.$2.id), ['o1', 'o2']);
    expect(ticksOn('nope', [crag]), isEmpty);
  });

  test('the link survives the trip through protocol events', () {
    final back = sessionsFromEvents(sessionsToEvents([crag, gym]));
    expect(back.firstWhere((s) => s.id == 'o1').climbs.first.problemId, 'p1');
    expect(back.firstWhere((s) => s.id == 'i1').climbs.single.gymGrade, 'yellow');
  });

  test('copyWith can set and clear the problem', () {
    final c = crag.climbs.first;
    expect(c.copyWith(problemId: () => null).problemId, isNull);
    expect(c.copyWith(problemId: () => 'p9').problemId, 'p9');
    expect(c.copyWith(name: 'x').problemId, 'p1');
  });
}
