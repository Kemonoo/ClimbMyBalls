part of '../climbing_map.dart';

Color _hex(String h) {
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16);
  return v == null ? Colors.white : Color(0xFF000000 | v);
}

const _startGreen = Color(0xFF3DDC84);

/// Draws a topo's lines and letters over its photo, the way hand-drawn
/// guides do: dotted lines with a dark edge, a bar at the start, an arrow
/// for a top-out or a circle for a finish at a hold, and the route's number.
/// With [lit] set, the other lines fade. With [only] set, just that line is
/// drawn, its start as a green dot.
class TopoPainter extends CustomPainter {
  TopoPainter(this.topo, {this.lit = const {}, this.only, this.litMark, this.draft, this.numbers = const {}});

  final Topo topo;
  final Set<int> lit;
  final int? only;

  /// A letter that was tapped, ringed.
  final String? litMark;

  /// A line being drawn (not yet in [topo]).
  final TopoLine? draft;

  /// The number shown on each problem's line, by problem id.
  final Map<String, String> numbers;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(TopoPoint p) => Offset(p.x * size.width, p.y * size.height);
    final scale = (size.shortestSide / 400).clamp(0.6, 2.5);

    void line(TopoLine l, {required bool faded, required bool strong, String? label, bool greenStart = false}) {
      if (l.points.isEmpty) return;
      final color = _hex(l.color).withValues(alpha: faded ? 0.35 : 1);
      final edge = Colors.black.withValues(alpha: faded ? 0.2 : 0.7);
      final r = (strong ? 3.0 : 2.2) * scale;
      final step = (strong ? 8.0 : 7.0) * scale;
      final pts = [for (final p in l.points) at(p)];
      // dots along the line
      final dots = <Offset>[pts.first];
      var carry = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final len = (b - a).distance;
        var d = step - carry;
        while (d <= len) {
          dots.add(Offset.lerp(a, b, d / len)!);
          d += step;
        }
        carry = len - (d - step);
      }
      final edgePaint = Paint()..color = edge;
      final dotPaint = Paint()..color = color;
      for (final d in dots) {
        canvas.drawCircle(d, r + 1.2 * scale, edgePaint);
      }
      for (final d in dots) {
        canvas.drawCircle(d, r, dotPaint);
      }
      // start: a bar, or a green dot on a route's own page
      final s = pts.first;
      if (greenStart) {
        canvas.drawCircle(s, 9 * scale, Paint()..color = Colors.black.withValues(alpha: 0.7));
        canvas.drawCircle(s, 7 * scale, Paint()..color = _startGreen);
      }
      final bar = Paint()
        ..color = color
        ..strokeWidth = 3 * scale
        ..strokeCap = StrokeCap.round;
      final barEdge = Paint()
        ..color = edge
        ..strokeWidth = 5.5 * scale
        ..strokeCap = StrokeCap.round;
      if (!greenStart) {
        canvas.drawLine(s.translate(-8 * scale, 6 * scale), s.translate(8 * scale, 6 * scale), barEdge);
        canvas.drawLine(s.translate(-8 * scale, 6 * scale), s.translate(8 * scale, 6 * scale), bar);
      }
      if (l.sitStart) _text(canvas, 'SD', s.translate(0, 18 * scale), 10 * scale, color, faded);
      // end
      if (pts.length >= 2) {
        final e = pts.last, before = pts[pts.length - 2];
        if (l.end == TopoEnd.hold) {
          final ring = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * scale;
          canvas.drawCircle(
            e,
            6 * scale,
            ring
              ..color = edge
              ..strokeWidth = 4.5 * scale,
          );
          canvas.drawCircle(
            e,
            6 * scale,
            ring
              ..color = color
              ..strokeWidth = 2.5 * scale,
          );
        } else {
          final dir = (e - before);
          final u = dir / (dir.distance == 0 ? 1 : dir.distance);
          final n = Offset(-u.dy, u.dx);
          final tip = e + u * 6 * scale;
          final path = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo((e - u * 6 * scale + n * 6 * scale).dx, (e - u * 6 * scale + n * 6 * scale).dy)
            ..lineTo((e - u * 6 * scale - n * 6 * scale).dx, (e - u * 6 * scale - n * 6 * scale).dy)
            ..close();
          canvas.drawPath(
            path,
            Paint()
              ..color = edge
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * scale,
          );
          canvas.drawPath(path, Paint()..color = color);
        }
      }
      // number label beside the middle of the line
      if (label != null && pts.length >= 2) {
        final mid = pts.length.isEven ? Offset.lerp(pts[pts.length ~/ 2 - 1], pts[pts.length ~/ 2], 0.5)! : pts[pts.length ~/ 2];
        _text(canvas, label, mid.translate(14 * scale, 0), (strong ? 15 : 13) * scale, color, faded);
      }
    }

    final through = only != null && only! < topo.lines.length ? _lettersNear(topo, topo.lines[only!]) : null;
    for (var i = 0; i < topo.lines.length; i++) {
      if (only != null ? only != i : topo.lines[i].alone) continue;
      final l = topo.lines[i];
      final n = numbers[l.problemId];
      line(
        l,
        faded: only == null && lit.isNotEmpty && !lit.contains(i),
        strong: only == i || lit.contains(i),
        label: n == null || n.isEmpty ? null : '$n.',
        greenStart: only == i,
      );
    }
    if (draft != null) line(draft!, faded: false, strong: true);
    for (final m in topo.marks) {
      final ringed = m.label == litMark;
      if (ringed) {
        canvas.drawCircle(at(m.at), 13 * scale, Paint()..color = Colors.black.withValues(alpha: 0.5));
        canvas.drawCircle(
          at(m.at),
          13 * scale,
          Paint()
            ..color = const Color(0xFFF2C94C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * scale,
        );
      }
      final dim = through != null ? !through.contains(m.label) : (lit.isNotEmpty && !ringed);
      _text(canvas, m.label, at(m.at), 15 * scale, Colors.white, dim, bold: true);
    }
  }

  void _text(Canvas canvas, String s, Offset centre, double size, Color color, bool faded, {bool bold = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color.withValues(alpha: faded ? 0.4 : 1),
          shadows: [Shadow(blurRadius: 3, color: Colors.black.withValues(alpha: faded ? 0.3 : 0.9))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(TopoPainter old) =>
      old.topo != topo || !setEquals(old.lit, lit) || old.only != only || old.litMark != litMark || old.draft != draft || old.numbers != numbers;
}

/// The letters a line passes: listed in its `via`, or drawn near.
Set<String> _lettersNear(Topo t, TopoLine l) => {
  for (final m in t.marks)
    if (l.via.contains(m.label) || t.linesThrough(m.label).contains(t.lines.indexOf(l))) m.label,
};

/// The photo with the drawing on top, zoomable, reporting taps in 0..1.
class TopoCanvas extends StatelessWidget {
  const TopoCanvas({
    super.key,
    required this.topo,
    required this.photo,
    this.lit = const {},
    this.only,
    this.litMark,
    this.draft,
    this.numbers = const {},
    this.onTap,
    this.controller,
  });

  final Topo topo;
  final ImageProvider photo;
  final Set<int> lit;
  final int? only;
  final String? litMark;
  final TopoLine? draft;
  final Map<String, String> numbers;
  final TransformationController? controller;
  final ValueChanged<TopoPoint>? onTap;

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    maxScale: 6,
    transformationController: controller,
    child: Center(
      child: AspectRatio(
        aspectRatio: topo.aspect,
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTap == null
                ? null
                : (d) => onTap!(TopoPoint((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0), (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0))),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: photo,
                  fit: BoxFit.fill,
                  errorBuilder: (_, e, _) => const ColoredBox(
                    color: Colors.black26,
                    child: Center(child: Text('Photo not loaded')),
                  ),
                ),
                CustomPaint(
                  painter: TopoPainter(topo, lit: lit, only: only, litMark: litMark, draft: draft, numbers: numbers),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
