part of '../climbing_map.dart';

Color _hex(String h) {
  final v = int.tryParse(h.replaceFirst('#', ''), radix: 16);
  return v == null ? Colors.white : Color(0xFF000000 | v);
}

const _startGreen = Color(0xFF3DDC84);

/// Draws a topo over its photo the way hand-drawn guides do, but light
/// enough to see the rock. The overview shows the guide's drawing (each
/// stretch once, small dots, the printed numbers) or, for sections drawn in
/// the app, each route's dotted line; no circles. With [only] set, just that
/// route: a thin line, a green ring on the start hold, and a ring on the
/// finishing hold or an arrow for a top-out. With [lit] set, those routes
/// are drawn over a faded overview.
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
    final halo = Colors.black.withValues(alpha: 0.45);

    void arrow(Offset e, Offset before, Color color) {
      final dir = e - before;
      final u = dir / (dir.distance == 0 ? 1 : dir.distance);
      final n = Offset(-u.dy, u.dx);
      final s = 4.5 * scale;
      final path = Path()
        ..moveTo((e + u * s).dx, (e + u * s).dy)
        ..lineTo((e - u * s + n * s).dx, (e - u * s + n * s).dy)
        ..lineTo((e - u * s - n * s).dx, (e - u * s - n * s).dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = halo
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
      canvas.drawPath(path, Paint()..color = color);
    }

    // small dots along a polyline, like the printed guides
    void dotted(List<Offset> pts, Color color) {
      if (pts.isEmpty) return;
      final r = 1.5 * scale, step = 5.5 * scale;
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
      final h = Paint()..color = halo, c = Paint()..color = color;
      for (final d in dots) {
        canvas.drawCircle(d, r + 0.8 * scale, h);
      }
      for (final d in dots) {
        canvas.drawCircle(d, r, c);
      }
    }

    void bar(Offset s, Color color) {
      final p = Paint()..strokeCap = StrokeCap.round;
      canvas.drawLine(
        s.translate(-6 * scale, 0),
        s.translate(6 * scale, 0),
        p
          ..color = halo
          ..strokeWidth = 3.5 * scale,
      );
      canvas.drawLine(
        s.translate(-6 * scale, 0),
        s.translate(6 * scale, 0),
        p
          ..color = color
          ..strokeWidth = 2 * scale,
      );
    }

    void ring(Offset c, Color color) {
      final p = Paint()..style = PaintingStyle.stroke;
      canvas.drawCircle(
        c,
        8 * scale,
        p
          ..color = halo
          ..strokeWidth = 3 * scale,
      );
      canvas.drawCircle(
        c,
        8 * scale,
        p
          ..color = color
          ..strokeWidth = 1.6 * scale,
      );
    }

    // one route on its own: thin, see-through, rings on the start and finish
    void single(TopoLine l) {
      if (l.points.isEmpty) return;
      final pts = [for (final p in l.points) at(p)];
      final color = _hex(l.color).withValues(alpha: 0.85);
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        path,
        stroke
          ..color = halo
          ..strokeWidth = 3.4 * scale,
      );
      canvas.drawPath(
        path,
        stroke
          ..color = color
          ..strokeWidth = 1.8 * scale,
      );
      ring(pts.first, _startGreen);
      if (l.sitStart) _text(canvas, 'SD', pts.first.translate(0, 16 * scale), 10 * scale, _startGreen, false);
      if (pts.length >= 2) {
        if (l.end == TopoEnd.hold) {
          ring(pts.last, Colors.white);
        } else {
          arrow(pts.last, pts[pts.length - 2], color);
        }
      }
    }

    // a route drawn in the app, on the overview: dotted, a bar at the start,
    // an arrow for a top-out, its number beside it
    void overviewLine(TopoLine l, {required bool faded, String? label}) {
      if (l.points.isEmpty) return;
      final color = _hex(l.color).withValues(alpha: faded ? 0.35 : 0.9);
      final pts = [for (final p in l.points) at(p)];
      dotted(pts, color);
      bar(pts.first.translate(0, 5 * scale), color);
      if (pts.length >= 2 && l.end == TopoEnd.topOut) arrow(pts.last, pts[pts.length - 2], color);
      if (label != null && pts.length >= 2) {
        final mid = pts.length.isEven ? Offset.lerp(pts[pts.length ~/ 2 - 1], pts[pts.length ~/ 2], 0.5)! : pts[pts.length ~/ 2];
        _text(canvas, label, mid.translate(12 * scale, 0), 11 * scale, color, faded);
      }
    }

    final o = topo.overlay;
    final through = only != null && only! < topo.lines.length ? _lettersNear(topo, topo.lines[only!]) : null;
    if (only != null) {
      if (only! < topo.lines.length) single(topo.lines[only!]);
    } else {
      final faded = lit.isNotEmpty;
      for (final e in o.edges) {
        final pts = [for (final p in e.points) at(p)];
        final color = _hex(e.color).withValues(alpha: faded ? 0.3 : 0.9);
        dotted(pts, color);
        if (e.arrow && pts.length >= 2) arrow(pts.last, pts[pts.length - 2], color);
      }
      for (final b in o.bars) {
        bar(at(b), Colors.white.withValues(alpha: faded ? 0.3 : 0.9));
      }
      for (final n in o.numbers) {
        _text(canvas, n.text, at(n.at), 11 * scale, _hex(n.color), faded);
      }
      for (var i = 0; i < topo.lines.length; i++) {
        final l = topo.lines[i];
        if (l.alone) continue; // part of the guide's drawing
        final n = numbers[l.problemId];
        overviewLine(l, faded: faded && !lit.contains(i), label: n == null || n.isEmpty ? null : '$n.');
      }
      for (final i in lit) {
        if (i < topo.lines.length && topo.lines[i].alone) single(topo.lines[i]);
      }
    }
    if (draft != null) single(draft!);
    for (final m in topo.marks) {
      final ringed = m.label == litMark;
      if (ringed) {
        canvas.drawCircle(
          at(m.at),
          12 * scale,
          Paint()
            ..color = const Color(0xFFF2C94C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 * scale,
        );
      }
      final dim = through != null ? !through.contains(m.label) : (lit.isNotEmpty && !ringed);
      _text(canvas, m.label, at(m.at), 13 * scale, Colors.white, dim, bold: true);
    }
  }

  void _text(Canvas canvas, String s, Offset centre, double size, Color color, bool faded, {bool bold = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color.withValues(alpha: faded ? 0.35 : 1),
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
