import 'package:test/test.dart';
import 'package:climbing/climbing.dart';

void main() {
  test("a day's grade is its sends' average, not over ten (#486)", () {
    final s = ClimbSession(id: 's', start: DateTime(2026, 11, 20, 15), outdoor: true, climbs: [
      Climb(grade: '7A+', outcome: ClimbOutcome.sent),
      Climb(grade: '7B', outcome: ClimbOutcome.tried),
    ]);
    expect(s.dayLevel!.grade, '7A+');
    expect(s.topLevel!.grade, isNot('7A+'), reason: 'the top 10 average still divides by ten');
    final two = ClimbSession(id: 't', start: DateTime(2026, 11, 20), climbs: [
      Climb(grade: '6A', outcome: ClimbOutcome.sent),
      Climb(grade: '6C', outcome: ClimbOutcome.flash),
    ]);
    expect(two.dayLevel!.grade, startsWith('6B'));
    expect(ClimbSession(id: 'u', start: DateTime(2026), climbs: [Climb(grade: '6A', outcome: ClimbOutcome.tried)]).dayLevel, isNull);
  });
}
