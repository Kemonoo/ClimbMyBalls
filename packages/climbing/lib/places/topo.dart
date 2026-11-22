// Topos (docs/climb/plan.md): a photo of a wall with letters on holds and
// route lines drawn over it, like the Devín guide's pages. Positions are 0..1
// of the photo's width and height, so they don't depend on its size on
// screen. Pure Dart: the shape, JSON, and finding the line under a tap.
import 'dart:math' as math;

/// A point on the photo, 0..1 across and down.
class TopoPoint {
  const TopoPoint(this.x, this.y);
  final double x, y;

  List<double> toJson() => [_r(x), _r(y)];
  factory TopoPoint.fromJson(List<dynamic> j) => TopoPoint((j[0] as num).toDouble(), (j[1] as num).toDouble());

  @override
  bool operator ==(Object other) => other is TopoPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

double _r(double v) => (v * 10000).round() / 10000;

/// A letter on a hold ('A', 'B', …, or any name), which routes and notes
/// refer to. With [hold] it sits on the hold itself (drawn in the app: a
/// small circle with the name beside it, and routes are built between such
/// holds); without, it is a printed guide's letter placed beside the hold.
class TopoMark {
  const TopoMark(this.label, this.at, {this.hold = false});
  final String label;
  final TopoPoint at;
  final bool hold;

  Map<String, dynamic> toJson() => {'label': label, 'x': _r(at.x), 'y': _r(at.y), if (hold) 'hold': true};
  factory TopoMark.fromJson(Map<String, dynamic> j) =>
      TopoMark(j['label'] as String? ?? '', TopoPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble()), hold: j['hold'] == true);
}

/// A guide's drawing of a whole section, drawn once on the overview: each
/// stretch of rock as one [edges] entry, however many routes share it, the
/// route numbers where the guide prints them, and open circles on the start holds.
/// Each route's own line (in [Topo.lines]) is the path along these edges,
/// shown on the route's page.
class TopoOverlay {
  const TopoOverlay({this.edges = const [], this.numbers = const [], this.starts = const []});

  final List<TopoEdge> edges;
  final List<TopoLabel> numbers;
  final List<TopoPoint> starts;

  bool get isEmpty => edges.isEmpty && numbers.isEmpty && starts.isEmpty;

  Map<String, dynamic> toJson() => {
    'edges': [for (final e in edges) e.toJson()],
    'numbers': [for (final n in numbers) n.toJson()],
    'starts': [for (final b in starts) b.toJson()],
  };

  factory TopoOverlay.fromJson(Map<String, dynamic>? j) => j == null
      ? const TopoOverlay()
      : TopoOverlay(
          edges: [for (final e in (j['edges'] as List? ?? const [])) TopoEdge.fromJson((e as Map).cast<String, dynamic>())],
          numbers: [for (final n in (j['numbers'] as List? ?? const [])) TopoLabel.fromJson((n as Map).cast<String, dynamic>())],
          starts: [for (final b in (j['starts'] as List? ?? const [])) TopoPoint.fromJson(b as List)],
        );
}

/// One drawn stretch between two junctions; [arrow] when it ends on top.
/// Stretches built in the app join two holds ([from], [to]: their labels)
/// and may be bent: [bend] is the control point of a gentle curve.
class TopoEdge {
  const TopoEdge(this.points, {this.color = '#ffffff', this.arrow = false, this.from = '', this.to = '', this.bend});
  final List<TopoPoint> points;
  final String color;
  final bool arrow;
  final String from, to;
  final TopoPoint? bend;

  /// Joins holds [a] and [b], either way round.
  bool joins(String a, String b) => from.isNotEmpty && ((from == a && to == b) || (from == b && to == a));

  TopoEdge copyWith({List<TopoPoint>? points, String? from, String? to, TopoPoint? Function()? bend}) =>
      TopoEdge(points ?? this.points, color: color, arrow: arrow, from: from ?? this.from, to: to ?? this.to, bend: bend != null ? bend() : this.bend);

  Map<String, dynamic> toJson() => {
    'pts': [for (final p in points) p.toJson()],
    if (color != '#ffffff') 'color': color,
    if (arrow) 'arrow': true,
    if (from.isNotEmpty) 'from': from,
    if (to.isNotEmpty) 'to': to,
    if (bend != null) 'bend': bend!.toJson(),
  };

  factory TopoEdge.fromJson(Map<String, dynamic> j) => TopoEdge(
    [for (final p in (j['pts'] as List? ?? const [])) TopoPoint.fromJson(p as List)],
    color: j['color'] as String? ?? '#ffffff',
    arrow: j['arrow'] == true,
    from: j['from'] as String? ?? '',
    to: j['to'] as String? ?? '',
    bend: j['bend'] == null ? null : TopoPoint.fromJson(j['bend'] as List),
  );
}

/// The points of a stretch from [a] to [b], curved through control [c] when
/// given (a quadratic curve, [n] pieces), else straight.
List<TopoPoint> stretchPoints(TopoPoint a, TopoPoint b, TopoPoint? c, {int n = 16}) {
  if (c == null) return [a, b];
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = i / n, u = 1 - t;
        return TopoPoint(u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y);
      }(),
  ];
}

/// The control point that makes the curve from [a] to [b] pass through [p]
/// at [t] (0..1 along it): grabbed in the middle it bulges evenly, near one
/// end it leans that way.
TopoPoint bendThrough(TopoPoint a, TopoPoint b, TopoPoint p, double t) {
  final tt = t.clamp(0.1, 0.9), u = 1 - tt;
  final k = 2 * tt * u;
  return TopoPoint((p.x - u * u * a.x - tt * tt * b.x) / k, (p.y - u * u * a.y - tt * tt * b.y) / k);
}

/// A route number printed on the photo ('28.').
class TopoLabel {
  const TopoLabel(this.text, this.at, {this.color = '#ffffff'});
  final String text;
  final TopoPoint at;
  final String color;

  Map<String, dynamic> toJson() => {'t': text, 'x': _r(at.x), 'y': _r(at.y), if (color != '#ffffff') 'color': color};
  factory TopoLabel.fromJson(Map<String, dynamic> j) =>
      TopoLabel(j['t'] as String? ?? '', TopoPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble()), color: j['color'] as String? ?? '#ffffff');
}

/// How a line ends: on top of the boulder (an arrow) or at a hold (a
/// circle).
enum TopoEnd { topOut, hold }

/// One route drawn on the photo: a problem, its points from the start, and
/// how it starts and ends. [color] is '#rrggbb' (white by default; the
/// guide draws traverses in yellow).
class TopoLine {
  const TopoLine({
    required this.problemId,
    required this.points,
    this.sitStart = false,
    this.end = TopoEnd.topOut,
    this.color = '#ffffff',
    this.via = const [],
    this.alone = false,
  });

  final String problemId;
  final List<TopoPoint> points;
  final bool sitStart;
  final TopoEnd end;
  final String color;

  /// Letters the route passes, for routes listed on the photo without a
  /// drawn line ("start G, end H"). Drawn lines also pass the letters near
  /// them; see [Topo.linesThrough].
  final List<String> via;

  /// Drawn only on the route's own page: a variant that shares its holds
  /// with lines already on the photo, so the overview doesn't stack them.
  final bool alone;

  TopoLine copyWith({List<TopoPoint>? points, bool? sitStart, TopoEnd? end, String? color, List<String>? via, bool? alone}) => TopoLine(
    problemId: problemId,
    points: points ?? this.points,
    sitStart: sitStart ?? this.sitStart,
    end: end ?? this.end,
    color: color ?? this.color,
    via: via ?? this.via,
    alone: alone ?? this.alone,
  );

  Map<String, dynamic> toJson() => {
    'problem': problemId,
    'points': [for (final p in points) p.toJson()],
    'start': sitStart ? 'sit' : 'stand',
    'end': end.name,
    'color': color,
    if (via.isNotEmpty) 'via': via,
    if (alone) 'alone': true,
  };

  factory TopoLine.fromJson(Map<String, dynamic> j) => TopoLine(
    problemId: j['problem'] as String,
    points: [for (final p in (j['points'] as List? ?? const [])) TopoPoint.fromJson(p as List)],
    sitStart: j['start'] == 'sit',
    end: switch (j['end']) {
      'hold' || 'top' => TopoEnd.hold,
      _ => TopoEnd.topOut,
    },
    color: j['color'] as String? ?? '#ffffff',
    via: [for (final v in (j['via'] as List? ?? const [])) v as String],
    alone: j['alone'] == true,
  );
}

/// A section: a named photo of one part of a boulder (or a wall) with its
/// marks and lines. A long wall has several. [originalPath] is an optional
/// second photo, such as a printed guide's own drawing. [bearing] is the way the camera faced, in degrees (0 = north), so
/// the map can show which side the photo is of; null when unknown.
class Topo {
  const Topo({
    required this.id,
    required this.placeId,
    required this.photoPath,
    this.name = '',
    this.originalPath = '',
    this.bearing,
    this.width = 0,
    this.height = 0,
    this.marks = const [],
    this.lines = const [],
    this.overlay = const TopoOverlay(),
    this.createdBy,
    this.angleOf,
  });

  final String id, placeId, photoPath;

  /// The section's name ('lucka 01'); '' when it has none.
  final String name;
  final String originalPath;
  final int? bearing;
  final int width, height;
  final List<TopoMark> marks;
  final List<TopoLine> lines;

  /// The guide's drawing, when the section came from one; empty otherwise.
  final TopoOverlay overlay;
  final String? createdBy;

  /// Another photo of the section with this id, from a different angle
  /// (#469); null for a section itself.
  final String? angleOf;

  double get aspect => width > 0 && height > 0 ? width / height : 4 / 3;

  Topo copyWith({
    String? photoPath,
    String? name,
    String? originalPath,
    int? Function()? bearing,
    int? width,
    int? height,
    List<TopoMark>? marks,
    List<TopoLine>? lines,
    TopoOverlay? overlay,
  }) => Topo(
    id: id,
    placeId: placeId,
    photoPath: photoPath ?? this.photoPath,
    name: name ?? this.name,
    originalPath: originalPath ?? this.originalPath,
    bearing: bearing != null ? bearing() : this.bearing,
    width: width ?? this.width,
    height: height ?? this.height,
    marks: marks ?? this.marks,
    lines: lines ?? this.lines,
    overlay: overlay ?? this.overlay,
    createdBy: createdBy,
    angleOf: angleOf,
  );

  /// The next free letter: A, B, … Z, then AA.
  String nextLabel() {
    final used = {for (final m in marks) m.label};
    for (var i = 0; ; i++) {
      final l = i < 26 ? String.fromCharCode(65 + i) : '${String.fromCharCode(65 + i ~/ 26 - 1)}${String.fromCharCode(65 + i % 26)}';
      if (!used.contains(l)) return l;
    }
  }

  /// The line nearest to [p], if one passes within [within] (in the same
  /// 0..1 units across). Distances are measured on the photo's real shape,
  /// so a tall photo isn't squashed. Returns its index in [lines].
  int? lineAt(TopoPoint p, {double within = 0.04}) {
    int? best;
    var bestD = within;
    final a = aspect;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].alone) continue; // not drawn on the overview
      final pts = lines[i].points;
      for (var k = 0; k < pts.length; k++) {
        final d = k == 0 ? _dist(p, pts[0], a) : _segDist(p, pts[k - 1], pts[k], a);
        if (d <= bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  /// The lines that pass the mark labelled [label]: listed in their `via`,
  /// or drawn within [within] of it.
  Set<int> linesThrough(String label, {double within = 0.03}) {
    final m = [
      for (final m in marks)
        if (m.label == label) m,
    ];
    final out = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.via.contains(label)) {
        out.add(i);
        continue;
      }
      if (m.isEmpty) continue;
      final at = m.first.at;
      for (var k = 0; k < l.points.length; k++) {
        final d = k == 0 ? _dist(at, l.points[0], aspect) : _segDist(at, l.points[k - 1], l.points[k], aspect);
        if (d <= within) {
          out.add(i);
          break;
        }
      }
    }
    return out;
  }

  /// The mark nearest to [p] within [within].
  int? markAt(TopoPoint p, {double within = 0.04}) {
    int? best;
    var bestD = within;
    for (var i = 0; i < marks.length; i++) {
      final d = _dist(p, marks[i].at, aspect);
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  TopoMark? markNamed(String label) => marks.where((m) => m.label == label).firstOrNull;

  /// The route along [holds] (labels, start first), drawn through stretches
  /// that already join two of them and new straight ones for the rest; it
  /// replaces [problemId]'s line. Stretches no route uses any more go.
  Topo withRoute(String problemId, List<String> holds, {TopoEnd end = TopoEnd.topOut, String color = '#ffffff', bool sitStart = false}) {
    final edges = List.of(overlay.edges);
    for (var i = 1; i < holds.length; i++) {
      final a = holds[i - 1], b = holds[i];
      if (a == b || edges.any((e) => e.joins(a, b))) continue;
      final pa = markNamed(a)?.at, pb = markNamed(b)?.at;
      if (pa == null || pb == null) continue;
      edges.add(TopoEdge(stretchPoints(pa, pb, null), from: a, to: b));
    }
    final line = TopoLine(problemId: problemId, points: _along(edges, holds), sitStart: sitStart, end: end, color: color, via: holds, alone: true);
    final lines = [
      for (final l in this.lines)
        if (l.problemId != problemId) l,
      line,
    ];
    return copyWith(lines: lines, overlay: _pruned(edges, lines));
  }

  /// Takes [problemId]'s line off the photo, with stretches only it used.
  Topo withoutRoute(String problemId) {
    final lines = [
      for (final l in this.lines)
        if (l.problemId != problemId) l,
    ];
    return copyWith(lines: lines, overlay: _pruned(overlay.edges, lines));
  }

  /// Bends stretch [i] through control [c] (null: straight again), and
  /// redraws the routes along it.
  Topo withBend(int i, TopoPoint? c) {
    final e = overlay.edges[i];
    final a = markNamed(e.from)?.at, b = markNamed(e.to)?.at;
    if (a == null || b == null) return this;
    final edges = List.of(overlay.edges)..[i] = e.copyWith(points: stretchPoints(a, b, c), bend: () => c);
    return _relaid(edges, marks);
  }

  /// Moves hold [label] to [at]; its stretches and routes follow.
  Topo withHoldAt(String label, TopoPoint at) {
    final marks = [for (final m in this.marks) m.label == label ? TopoMark(m.label, at, hold: m.hold) : m];
    final moved = copyWith(marks: marks);
    final edges = [
      for (final e in overlay.edges)
        if (e.from == label || e.to == label) e.copyWith(points: stretchPoints(moved.markNamed(e.from)!.at, moved.markNamed(e.to)!.at, e.bend)) else e,
    ];
    return moved._relaid(edges, marks);
  }

  /// Renames hold [from] to [to] everywhere: its stretches and the routes
  /// through it. Null when [to] is empty or taken.
  Topo? withHoldRenamed(String from, String to) {
    final name = to.trim();
    if (name.isEmpty || (name != from && markNamed(name) != null)) return null;
    String n(String x) => x == from ? name : x;
    return copyWith(
      marks: [for (final m in marks) m.label == from ? TopoMark(name, m.at, hold: m.hold) : m],
      lines: [for (final l in lines) l.copyWith(via: [for (final v in l.via) n(v)])],
      overlay: TopoOverlay(
        edges: [for (final e in overlay.edges) e.copyWith(from: n(e.from), to: n(e.to))],
        numbers: overlay.numbers,
        starts: overlay.starts,
      ),
    );
  }

  /// Removes hold [label], its stretches, and the routes built through it.
  Topo withoutHold(String label) {
    final lines = [
      for (final l in this.lines)
        if (!(l.alone && l.via.contains(label))) l,
    ];
    final edges = [
      for (final e in overlay.edges)
        if (e.from != label && e.to != label) e,
    ];
    return copyWith(
      marks: [
        for (final m in marks)
          if (m.label != label) m,
      ],
      lines: lines,
      overlay: _pruned(edges, lines),
    );
  }

  /// The routes built from holds, redrawn along [edges].
  Topo _relaid(List<TopoEdge> edges, List<TopoMark> marks) => copyWith(
    marks: marks,
    lines: [for (final l in lines) _builtFromHolds(l, edges) ? l.copyWith(points: _along(edges, l.via)) : l],
    overlay: TopoOverlay(edges: edges, numbers: overlay.numbers, starts: overlay.starts),
  );

  static bool _builtFromHolds(TopoLine l, List<TopoEdge> edges) =>
      l.alone && l.via.length >= 2 && [for (var i = 1; i < l.via.length; i++) edges.any((e) => e.joins(l.via[i - 1], l.via[i]))].every((x) => x);

  /// The points along [holds] through [edges], each stretch the right way round.
  static List<TopoPoint> _along(List<TopoEdge> edges, List<String> holds) {
    final pts = <TopoPoint>[];
    for (var i = 1; i < holds.length; i++) {
      final e = edges.where((e) => e.joins(holds[i - 1], holds[i])).firstOrNull;
      if (e == null) continue;
      final p = e.from == holds[i - 1] ? e.points : e.points.reversed.toList();
      pts.addAll(pts.isEmpty ? p : p.skip(1));
    }
    return pts;
  }

  /// [edges] without the built stretches no route in [lines] uses; a guide's
  /// own drawing (stretches without holds) always stays.
  TopoOverlay _pruned(List<TopoEdge> edges, List<TopoLine> lines) => TopoOverlay(
    edges: [
      for (final e in edges)
        if (e.from.isEmpty ||
            lines.any((l) {
              for (var i = 1; i < l.via.length; i++) {
                if (e.joins(l.via[i - 1], l.via[i])) return true;
              }
              return false;
            }))
          e,
    ],
    numbers: overlay.numbers,
    starts: overlay.starts,
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'place_id': placeId,
    'photo_path': photoPath,
    'name': name,
    'original_path': originalPath,
    'bearing': bearing,
    'width': width,
    'height': height,
    'marks': [for (final m in marks) m.toJson()],
    'lines': [for (final l in lines) l.toJson()],
    if (!overlay.isEmpty) 'overlay': overlay.toJson(),
    if (angleOf != null) 'angle_of': angleOf,
  };

  factory Topo.fromRow(Map<String, dynamic> r) => Topo(
    id: r['id'] as String,
    placeId: r['place_id'] as String,
    photoPath: r['photo_path'] as String,
    name: r['name'] as String? ?? '',
    originalPath: r['original_path'] as String? ?? '',
    bearing: (r['bearing'] as num?)?.toInt(),
    width: (r['width'] as num?)?.toInt() ?? 0,
    height: (r['height'] as num?)?.toInt() ?? 0,
    marks: [for (final m in (r['marks'] as List? ?? const [])) TopoMark.fromJson((m as Map).cast<String, dynamic>())],
    lines: [for (final l in (r['lines'] as List? ?? const [])) TopoLine.fromJson((l as Map).cast<String, dynamic>())],
    overlay: TopoOverlay.fromJson((r['overlay'] as Map?)?.cast<String, dynamic>()),
    createdBy: r['created_by'] as String?,
    angleOf: r['angle_of'] as String?,
  );
}

// Distances with x scaled by the aspect ratio, so units are "photo heights".
double _dist(TopoPoint a, TopoPoint b, double aspect) {
  final dx = (a.x - b.x) * aspect, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy) / aspect;
}

double _segDist(TopoPoint p, TopoPoint a, TopoPoint b, double aspect) {
  final ax = a.x * aspect, bx = b.x * aspect, px = p.x * aspect;
  final dx = bx - ax, dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (p.y - a.y) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = a.y + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (p.y - cy) * (p.y - cy)) / aspect;
}

/// Compass point for a bearing: 'N', 'NE', … ('' when null).
String bearingLabel(int? b) => b == null ? '' : const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][((b % 360) / 45).round() % 8];
