// The community grade of a problem (docs/climb/plan.md, step 3).
//
// Font grades sit on the rungs of kGradeLadder (3A = 0, … 6A = 18, 6A+ = 19),
// so votes can be put in order. The shown grade is the median vote, rounded to
// a rung. With fewer than [kMinVotes] votes it is the first ascender's grade.
import '../climbing.dart';

/// Votes needed before the median replaces the first ascender's grade.
const kMinVotes = 3;

/// Where the shown grade came from.
enum GradeBasis { votes, firstAscent, none }

class CommunityGrade {
  /// The grade to show ('6B+'), or '' when there is nothing to go on.
  final String grade;
  final GradeBasis basis;

  /// Valid votes counted (unknown grades are ignored).
  final int votes;

  /// Ticks on the problem: everyone who sent it.
  final int ascents;

  /// Votes per grade, for the "proposed grades" bar: '6B' → 4.
  final Map<String, int> spread;

  /// The first ascender's (or setter's) grade, normalised; '' if unknown.
  final String firstAscentGrade;

  const CommunityGrade({
    required this.grade,
    required this.basis,
    required this.votes,
    required this.ascents,
    required this.spread,
    required this.firstAscentGrade,
  });

  /// "6B+ · 7 votes", "6B · first ascent", or "".
  String get label => switch (basis) {
        GradeBasis.votes => '$grade · $votes vote${votes == 1 ? '' : 's'}',
        GradeBasis.firstAscent => '$grade · first ascent',
        GradeBasis.none => '',
      };
}

/// The median of [rungs], rounded to the nearest rung (a tie between two
/// middle votes rounds up, so 6A and 6A+ give 6A+).
int medianRung(List<int> rungs) {
  if (rungs.isEmpty) throw ArgumentError('No votes.');
  final s = [...rungs]..sort();
  final mid = s.length ~/ 2;
  if (s.length.isOdd) return s[mid];
  return ((s[mid - 1] + s[mid]) / 2).round();
}

/// The community grade from [votes] (grade strings, one per voter), the first
/// ascender's grade and the number of ticks.
CommunityGrade communityGrade({
  Iterable<String> votes = const [],
  String firstAscentGrade = '',
  int ascents = 0,
}) {
  final rungs = <int>[];
  final spread = <String, int>{};
  for (final v in votes) {
    final i = gradeIndex(v);
    if (i == null) continue;
    rungs.add(i);
    final g = kGradeLadder[i];
    spread[g] = (spread[g] ?? 0) + 1;
  }
  final fa = gradeIndex(firstAscentGrade);
  final faGrade = fa == null ? '' : kGradeLadder[fa];
  final (grade, basis) = rungs.length >= kMinVotes
      ? (kGradeLadder[medianRung(rungs)], GradeBasis.votes)
      : faGrade.isNotEmpty
          ? (faGrade, GradeBasis.firstAscent)
          : ('', GradeBasis.none);
  final ordered = Map.fromEntries(spread.entries.toList()..sort((a, b) => gradeIndex(a.key)!.compareTo(gradeIndex(b.key)!)));
  return CommunityGrade(
    grade: grade,
    basis: basis,
    votes: rungs.length,
    ascents: ascents,
    spread: ordered,
    firstAscentGrade: faGrade,
  );
}

/// [communityGrade] for one problem from the climber's own sessions: each
/// send's grade is a vote, and each send counts as an ascent. Shared votes
/// from other people (step 7) are added through [otherVotes].
CommunityGrade communityGradeFromTicks(
  String problemId,
  Iterable<ClimbSession> sessions, {
  String firstAscentGrade = '',
  Iterable<String> otherVotes = const [],
  int otherAscents = 0,
}) {
  final sends = [for (final (c, _) in ticksOn(problemId, sessions)) if (c.outcome.isSend) c];
  return communityGrade(
    votes: [...otherVotes, for (final c in sends) if (c.isGraded) c.grade],
    firstAscentGrade: firstAscentGrade,
    ascents: otherAscents + sends.length,
  );
}
