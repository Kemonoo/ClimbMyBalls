// What the map shows and the "near me" list (docs/climb/plan.md, step 4).
// Pure Dart: distance, the outdoor / indoor / grade / search filter, and the
// list of places sorted by distance from where you stand.
import 'dart:math' as math;

import '../climbing.dart';
import 'place.dart';
import 'place_tree.dart';

/// Great-circle distance in metres.
double distanceMetres(LatLng a, LatLng b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// '350 m', '1.2 km', '24 km'.
String distanceLabel(double metres) {
  if (metres < 1000) return '${(metres / 10).round() * 10} m';
  if (metres < 10000) return '${(metres / 1000).toStringAsFixed(1)} km';
  return '${(metres / 1000).round()} km';
}

/// Outdoor, indoor or both; a Font grade range (rungs of [kGradeLadder]); and
/// an optional search text. The full range means "any grade, or none".
class PlaceFilter {
  const PlaceFilter({this.where = ClimbWhere.all, this.minRung = 0, this.maxRung = topRung, this.query = ''});

  /// The hardest rung of [kGradeLadder] (8C+).
  static const topRung = 35;

  final ClimbWhere where;
  final int minRung, maxRung;
  final String query;

  bool get anyGrade => minRung <= 0 && maxRung >= topRung;

  PlaceFilter copyWith({ClimbWhere? where, int? minRung, int? maxRung, String? query}) =>
      PlaceFilter(where: where ?? this.where, minRung: minRung ?? this.minRung, maxRung: maxRung ?? this.maxRung, query: query ?? this.query);

  bool _gradeIn(String grade) {
    final i = gradeIndex(grade);
    return i != null && i >= minRung && i <= maxRung;
  }

  bool _whereOk(Place p) => switch (where) {
    ClimbWhere.all => true,
    ClimbWhere.indoor => p.indoor,
    ClimbWhere.outdoor => !p.indoor,
  };

  /// Whether [p] passes: indoor or outdoor, and with a grade range set, it
  /// or something under it has a Font grade inside the range.
  bool matches(Place p, PlaceTree tree) {
    if (!_whereOk(p)) return false;
    if (anyGrade) return true;
    if (_gradeIn(p.grade)) return true;
    return tree.descendantsOf(p.id).any((d) => _gradeIn(d.grade));
  }
}

/// The places to draw on the map: everything with a location that passes
/// [filter] (a search narrows it to the matches).
List<Place> placesOnMap(PlaceTree tree, PlaceFilter filter) {
  final pool = filter.query.trim().isEmpty ? tree.all : tree.search(filter.query, limit: 1 << 20);
  return [
    for (final p in pool)
      if (p.geometry != null && filter.matches(p, tree)) p,
  ];
}

/// One row of the "near me" list.
typedef NearPlace = ({Place place, double metres});

/// Places with a location around [at], nearest first. Problems are left out
/// (they show under their boulder) unless [problems] is set.
List<NearPlace> nearMe(PlaceTree tree, LatLng at, PlaceFilter filter, {int limit = 30, bool problems = false}) {
  final rows = [
    for (final p in placesOnMap(tree, filter))
      if (problems || p.kind != PlaceKind.problem) (place: p, metres: distanceMetres(at, p.geometry!.centre)),
  ]..sort((a, b) => a.metres.compareTo(b.metres));
  return rows.take(limit).toList();
}

/// The Font grades of the problems at or under [id], easiest first, as
/// '5B–7A' (or one grade, or '' when none are graded).
String gradeSpan(PlaceTree tree, String id) {
  final rungs = <int>[
    for (final p in [if (tree[id] != null) tree[id]!, ...tree.descendantsOf(id)])
      if (gradeIndex(p.grade) case final i?) i,
  ]..sort();
  if (rungs.isEmpty) return '';
  final lo = kGradeLadder[rungs.first], hi = kGradeLadder[rungs.last];
  return lo == hi ? lo : '$lo–$hi';
}

/// A grade as typed for a problem, checked against its scale. Font: '6b+',
/// 'fb7A' or a split grade like '7A+/B' (kept as written; the first grade
/// counts for points). UIAA: '9', '9+/10-', '10-'. Returns the grade to
/// store, or null when it isn't one.
String? checkGrade(String raw, GradeSystem scale) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (t.isEmpty) return null;
  if (scale.isUiaa) {
    return RegExp(r'^(1[0-2]|[1-9])[+-]?(/(1[0-2]|[1-9])?[+-]?)?$').hasMatch(t) ? t : null;
  }
  if (!scale.isFont) return t; // a gym's own scale: anything goes
  final parts = t.split('/');
  final first = normaliseGrade(parts.first);
  if (gradeIndex(first) == null) return null;
  if (parts.length == 1) return first;
  if (parts.length > 2) return null;
  final second = parts[1].toUpperCase();
  final ok = second.isEmpty || second == '+' || RegExp(r'^[ABC]\+?$').hasMatch(second) || gradeIndex(normaliseGrade(second)) != null;
  return ok ? '$first/$second' : null;
}

/// The places a new place of [kind] at [at] can go under: the ones above it
/// in the hierarchy, outline containing [at] first, then nearest, within
/// [radiusMetres].
List<NearPlace> parentCandidates(PlaceTree tree, LatLng at, PlaceKind kind, {double radiusMetres = 3000, int limit = 6}) {
  final rows =
      [
          for (final p in tree.all)
            if (p.geometry != null && p.kind.index < kind.index && p.kind.index >= PlaceKind.area.index && p.kind != PlaceKind.gymWall)
              (
                place: p,
                metres: switch (p.geometry!) {
                  PolygonGeometry(:final ring) when _inside(at, ring) => 0.0,
                  final g => distanceMetres(at, g.centre),
                },
              ),
        ].where((r) => r.metres <= radiusMetres).toList()
        ..sort((a, b) => a.metres != b.metres ? a.metres.compareTo(b.metres) : b.place.kind.index.compareTo(a.place.kind.index));
  return rows.take(limit).toList();
}

bool _inside(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) inside = !inside;
  }
  return inside;
}

/// The grades to pick from for a new problem, easiest first, with the
/// in-between grades guides use: Font 3A to 9A+ ('7A+/B', '7C+/8A'), UIAA
/// 3- to 12 ('9+/10-').
List<String> gradeChoices(GradeSystem scale) {
  if (scale.isUiaa) {
    final steps = [
      for (var n = 3; n <= 12; n++) ...['$n-', '$n', '$n+'],
    ];
    return [
      for (var i = 0; i < steps.length; i++) ...[steps[i], if (i + 1 < steps.length && steps[i].endsWith('+')) '${steps[i]}/${steps[i + 1]}'],
    ];
  }
  final steps = [
    for (var n = 3; n <= 9; n++)
      for (final l in ['A', 'B', 'C'])
        for (final p in ['', '+'])
          if (n < 9 || l == 'A') '$n$l$p',
  ];
  return [
    for (var i = 0; i < steps.length; i++) ...[
      steps[i],
      if (i + 1 < steps.length) '${steps[i]}/${steps[i + 1][0] == steps[i][0] ? steps[i + 1].substring(1) : steps[i + 1]}',
    ],
  ];
}

/// Where [grade] falls among [gradeChoices], for sorting by grade; grades
/// not in the list (a gym's own) sort last. '7A+/B' sorts between 7A+ and
/// 7B, '7C/' (7C or harder) with 7C.
int gradeOrder(String grade, GradeSystem scale) {
  final all = gradeChoices(scale);
  var i = all.indexOf(grade);
  if (i < 0 && grade.endsWith('/')) i = all.indexOf(grade.substring(0, grade.length - 1));
  if (i < 0) i = all.indexOf(grade.split('/').first);
  return i < 0 ? 1 << 20 : i;
}
