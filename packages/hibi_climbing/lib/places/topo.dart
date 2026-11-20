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

/// A letter on a hold ('A', 'B', …), which routes and notes refer to.
class TopoMark {
  const TopoMark(this.label, this.at);
  final String label;
  final TopoPoint at;

  Map<String, dynamic> toJson() => {'label': label, 'x': _r(at.x), 'y': _r(at.y)};
  factory TopoMark.fromJson(Map<String, dynamic> j) => TopoMark(j['label'] as String? ?? '', TopoPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble()));
}

/// A guide's drawing of a whole section, drawn once on the overview: each
/// stretch of rock as one [edges] entry, however many routes share it, the
/// route numbers where the guide prints them, and bars under the starts.
/// Each route's own line (in [Topo.lines]) is the path along these edges,
/// shown on the route's page.
class TopoOverlay {
  const TopoOverlay({this.edges = const [], this.numbers = const [], this.bars = const []});

  final List<TopoEdge> edges;
  final List<TopoLabel> numbers;
  final List<TopoPoint> bars;

  bool get isEmpty => edges.isEmpty && numbers.isEmpty && bars.isEmpty;

  Map<String, dynamic> toJson() => {
    'edges': [for (final e in edges) e.toJson()],
    'numbers': [for (final n in numbers) n.toJson()],
    'bars': [for (final b in bars) b.toJson()],
  };

  factory TopoOverlay.fromJson(Map<String, dynamic>? j) => j == null
      ? const TopoOverlay()
      : TopoOverlay(
          edges: [for (final e in (j['edges'] as List? ?? const [])) TopoEdge.fromJson((e as Map).cast<String, dynamic>())],
          numbers: [for (final n in (j['numbers'] as List? ?? const [])) TopoLabel.fromJson((n as Map).cast<String, dynamic>())],
          bars: [for (final b in (j['bars'] as List? ?? const [])) TopoPoint.fromJson(b as List)],
        );
}

/// One drawn stretch between two junctions; [arrow] when it ends on top.
class TopoEdge {
  const TopoEdge(this.points, {this.color = '#ffffff', this.arrow = false});
  final List<TopoPoint> points;
  final String color;
  final bool arrow;

  Map<String, dynamic> toJson() => {
    'pts': [for (final p in points) p.toJson()],
    if (color != '#ffffff') 'color': color,
    if (arrow) 'arrow': true,
  };

  factory TopoEdge.fromJson(Map<String, dynamic> j) => TopoEdge(
    [for (final p in (j['pts'] as List? ?? const [])) TopoPoint.fromJson(p as List)],
    color: j['color'] as String? ?? '#ffffff',
    arrow: j['arrow'] == true,
  );
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
