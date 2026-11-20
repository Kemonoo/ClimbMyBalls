import 'package:climbing/climbing.dart';
import 'package:test/test.dart';

void main() {
  test('weekly ascents: Monday weeks, tries left out, this week last with its flash share', () {
    final now = DateTime(2026, 11, 20, 12); // a Friday
    ClimbSession s(DateTime d, List<ClimbOutcome> o) =>
        ClimbSession(id: '$d', start: d, outdoor: true, climbs: [for (final x in o) Climb(grade: '6A', outcome: x)]);
    final w = weeklyAscents([
      s(DateTime(2026, 11, 16, 18), [ClimbOutcome.flash, ClimbOutcome.sent, ClimbOutcome.tried]), // this Monday
      s(DateTime(2026, 11, 20, 9), [ClimbOutcome.flash]),
      s(DateTime(2026, 11, 15, 18), [ClimbOutcome.sent]), // last Sunday
      s(DateTime(2026, 1, 1), [ClimbOutcome.sent]), // too old
      s(DateTime(2026, 11, 21), [ClimbOutcome.sent]), // tomorrow
    ], now: now, weeks: 4);
    expect(w.perWeek, [0, 0, 1, 3]);
    expect(w.flashShare, closeTo(2 / 3, 1e-9));
    expect(weeklyAscents(const [], now: now).flashShare, 0);
  });
}
