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
      // the logo's tail tip: a heart whose lobes flare back past where the
      // line joins it, the point just past the line's end
      const tip = 62.0, w = 46.0;
      final k = 16 * scale / tip;
      final o = e + u * (4.5 * scale) - u * (tip * k);
      Offset p(double x, double y) => o + u * (x * k) + n * (y * k);
      final a = p(-4, -8), b = p(-20, -w * .7), c = p(-8, -w);
      final d = p(8, -w * 1.2), f = p(tip * .5, -w * .6), t = p(tip, 0);
      final d2 = p(tip * .5, w * .6), f2 = p(8, w * 1.2), c2 = p(-8, w);
      final b2 = p(-20, w * .7), a2 = p(-4, 8);
      final path = Path()
        ..moveTo(o.dx, o.dy)
        ..cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy)
        ..cubicTo(d.dx, d.dy, f.dx, f.dy, t.dx, t.dy)
        ..cubicTo(d2.dx, d2.dy, f2.dx, f2.dy, c2.dx, c2.dy)
        ..cubicTo(b2.dx, b2.dy, a2.dx, a2.dy, o.dx, o.dy)
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

    // the polyline cut back to the edge of any circle at its ends, so lines
    // meet a hold's circle instead of running under it
    List<Offset> trimmed(List<Offset> pts, List<Offset> circles, double r) {
      List<Offset> cutFront(List<Offset> p) {
        if (p.length < 2) return p;
        final c = circles.where((c) => (c - p.first).distance < r * 1.2).firstOrNull;
        if (c == null) return p;
        for (var i = 1; i < p.length; i++) {
          if ((p[i] - c).distance >= r) {
            // the point on segment i-1 → i that is r from the circle's centre
            final a = p[i - 1], b = p[i];
            var lo = 0.0, hi = 1.0;
            for (var k = 0; k < 20; k++) {
              final m = (lo + hi) / 2;
              if ((Offset.lerp(a, b, m)! - c).distance < r) {
                lo = m;
              } else {
                hi = m;
              }
            }
            return [Offset.lerp(a, b, hi)!, ...p.sublist(i)];
          }
        }
        return const [];
      }

      return cutFront(cutFront(pts).reversed.toList()).reversed.toList();
    }

    final big = 8 * scale, small = 5.5 * scale;
    const finishPink = Color(0xFFFF7EB6);

    void ring(Offset c, Color color, {double? radius}) {
      final rr = radius ?? big;
      final p = Paint()..style = PaintingStyle.stroke;
      canvas.drawCircle(
        c,
        rr,
        p
          ..color = halo
          ..strokeWidth = 3 * scale,
      );
      canvas.drawCircle(
        c,
        rr,
        p
          ..color = color
          ..strokeWidth = 1.6 * scale,
      );
    }

    // one route on its own: thin, see-through, rings on the start and finish
    void single(TopoLine l) {
      if (l.points.isEmpty) return;
      final all = [for (final p in l.points) at(p)];
      final color = _hex(l.color).withValues(alpha: 0.85);
      final hold = l.end == TopoEnd.hold && all.length >= 2;
      final pts = trimmed(all, [all.first, if (hold) all.last], big);
      if (pts.isEmpty) return;
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
      ring(all.first, _startGreen);
      if (l.sitStart) _text(canvas, 'SD', all.first.translate(0, 18 * scale), 10 * scale, _startGreen, false);
      if (hold) {
        ring(all.last, finishPink);
      } else if (pts.length >= 2) {
        arrow(pts.last, pts[pts.length - 2], finishPink);
      }
    }

    // a route drawn in the app, on the overview: dotted, a circle at the start,
    // an arrow for a top-out, its number beside it
    void overviewLine(TopoLine l, {required bool faded, String? label}) {
      if (l.points.isEmpty) return;
      final color = _hex(l.color).withValues(alpha: faded ? 0.35 : 0.9);
      final all = [for (final p in l.points) at(p)];
      final pts = trimmed(all, [all.first], small);
      dotted(pts, color);
      ring(all.first, color, radius: small);
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
      // holds placed in the app are circles too: lines stop at their edge
      final starts = [
        for (final b in o.starts) at(b),
        for (final m in topo.marks)
          if (m.hold) at(m.at),
      ];
      for (final e in o.edges) {
        final pts = trimmed([for (final p in e.points) at(p)], starts, small);
        final color = _hex(e.color).withValues(alpha: faded ? 0.3 : 0.9);
        dotted(pts, color);
        if (e.arrow && pts.length >= 2) arrow(pts.last, pts[pts.length - 2], color);
      }
      for (final c in starts) {
        ring(c, Colors.white.withValues(alpha: faded ? 0.3 : 0.9), radius: small);
      }
      for (final n in o.numbers) {
        _text(canvas, n.text, at(n.at), 11 * scale, _hex(n.color), faded);
      }
      // routes built from holds, without a guide's printed numbers: their
      // numbers under the start hold ("12. 15.")
      if (o.numbers.isEmpty) {
        final byStart = <String, List<String>>{};
        for (final l in topo.lines) {
          final n = numbers[l.problemId];
          if (l.alone && l.via.length >= 2 && n != null && n.isNotEmpty) (byStart[l.via.first] ??= []).add('$n.');
        }
        for (final MapEntry(key: hold, value: ns) in byStart.entries) {
          final m = topo.markNamed(hold);
          if (m != null) _text(canvas, ns.join(' '), at(m.at).translate(0, 16 * scale), 11 * scale, Colors.white, faded);
        }
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
      if (m.hold) {
        // a hold placed in the app: its circle (the overview draws it with
        // the start circles), its name beside it
        if (only != null) ring(at(m.at), Colors.white.withValues(alpha: dim ? 0.25 : 0.6), radius: small);
        _text(canvas, m.label, at(m.at).translate(-12 * scale, -12 * scale), 12 * scale, Colors.white, dim, bold: true);
      } else {
        _text(canvas, m.label, at(m.at), 13 * scale, Colors.white, dim, bold: true);
      }
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
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
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

  /// Dragging on the photo (bending a line, moving a hold): while these are
  /// set, the photo doesn't pan or zoom.
  final ValueChanged<TopoPoint>? onDragStart, onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final view = Center(
      child: AspectRatio(
        aspectRatio: topo.aspect,
        child: LayoutBuilder(
          builder: (context, box) {
            TopoPoint p(Offset o) => TopoPoint((o.dx / box.maxWidth).clamp(0.0, 1.0), (o.dy / box.maxHeight).clamp(0.0, 1.0));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onTap == null ? null : (d) => onTap!(p(d.localPosition)),
              dragStartBehavior: DragStartBehavior.down, // where the finger went down, not where the drag was noticed
            onPanStart: onDragStart == null ? null : (d) => onDragStart!(p(d.localPosition)),
              onPanUpdate: onDragUpdate == null ? null : (d) => onDragUpdate!(p(d.localPosition)),
              onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
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
            );
          },
        ),
      ),
    );
    // dragging on the photo: no pan or zoom, they would take the drag
    return onDragUpdate != null ? view : InteractiveViewer(maxScale: 6, transformationController: controller, child: view);
  }
}
