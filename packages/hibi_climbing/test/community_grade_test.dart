import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/places/community_grade.dart';
import 'package:test/test.dart';

void main() {
  test('median: odd takes the middle, even rounds the middle pair up', () {
    expect(medianRung([20, 18, 30]), 20);
    expect(medianRung([18, 19]), 19);
    expect(medianRung([18, 20]), 19);
    expect(medianRung([18, 18, 20, 22]), 19);
    expect(() => medianRung([]), throwsArgumentError);
  });

  test('3 or more votes: the median grade, with the vote count', () {
    final g = communityGrade(votes: ['6A', '6B', '6b+', '7A', 'nonsense'], firstAscentGrade: '6C', ascents: 9);
    expect(g.grade, '6B+');
    expect(g.basis, GradeBasis.votes);
    expect(g.votes, 4);
    expect(g.ascents, 9);
    expect(g.label, '6B+ · 4 votes');
    expect(g.spread, {'6A': 1, '6B': 1, '6B+': 1, '7A': 1});
    expect(g.spread.keys.first, '6A');
  });

  test('under 3 votes: the first ascender\'s grade; nothing at all: empty', () {
    final g = communityGrade(votes: ['7A', '7A'], firstAscentGrade: 'fb6c+');
    expect(g.grade, '6C+');
    expect(g.basis, GradeBasis.firstAscent);
    expect(g.label, '6C+ · first ascent');
    expect(g.votes, 2);
    final none = communityGrade(votes: ['7A']);
    expect(none.grade, '');
    expect(none.basis, GradeBasis.none);
    expect(none.label, '');
  });

  test('one outlier does not move the median', () {
    expect(communityGrade(votes: ['6A', '6A', '6A', '8C']).grade, '6A');
  });

  test('from ticks: each graded send is a vote and an ascent; tries are neither', () {
    ClimbSession s(String id, List<Climb> climbs) => ClimbSession(id: id, start: DateTime(2026, 11, int.parse(id)), outdoor: true, climbs: climbs);
    final sessions = [
      s('1', [Climb(grade: '6B', outcome: ClimbOutcome.sent, problemId: 'p'), Climb(grade: '6A', outcome: ClimbOutcome.tried, problemId: 'p')]),
      s('2', [Climb(grade: '', outcome: ClimbOutcome.flash, problemId: 'p')]),
      s('3', [Climb(grade: '7A', outcome: ClimbOutcome.sent, problemId: 'other')]),
    ];
    final mine = communityGradeFromTicks('p', sessions, firstAscentGrade: '6B+');
    expect(mine.ascents, 2);
    expect(mine.votes, 1);
    expect(mine.grade, '6B+');
    expect(mine.basis, GradeBasis.firstAscent);
    final shared = communityGradeFromTicks('p', sessions, otherVotes: ['6C', '6B'], otherAscents: 5);
    expect(shared.votes, 3);
    expect(shared.grade, '6B');
    expect(shared.ascents, 7);
  });
}
