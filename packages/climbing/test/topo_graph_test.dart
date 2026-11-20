import 'package:climbing/places/topo.dart';
import 'package:test/test.dart';

void main() {
  // G at the bottom right, F left of it, M in the middle, L at the top
  const base = Topo(
    id: 't',
    placeId: 'b',
    photoPath: 'p',
    marks: [
      TopoMark('G', TopoPoint(0.8, 0.9), hold: true),
      TopoMark('F', TopoPoint(0.5, 0.9), hold: true),
      TopoMark('M', TopoPoint(0.5, 0.5), hold: true),
      TopoMark('L', TopoPoint(0.6, 0.1), hold: true),
    ],
  );

  test('routes share stretches: G-F-M-L then F-M-L adds nothing new', () {
    final a = base.withRoute('r1', ['G', 'F', 'M', 'L']);
    expect(a.overlay.edges.length, 3);
    expect(a.lines.single.via, ['G', 'F', 'M', 'L']);
    expect(a.lines.single.alone, isTrue, reason: 'the overview draws the stretches, not each route');
    expect(a.lines.single.points.first, const TopoPoint(0.8, 0.9));
    expect(a.lines.single.points.last, const TopoPoint(0.6, 0.1));
    final b = a.withRoute('r2', ['F', 'M', 'L']);
    expect(b.overlay.edges.length, 3);
    // the other way round reuses the stretch too
    final c = b.withRoute('r3', ['L', 'M'], end: TopoEnd.hold);
    expect(c.overlay.edges.length, 3);
    expect(c.lines.last.points, [const TopoPoint(0.6, 0.1), const TopoPoint(0.5, 0.5)]);
    // redrawing a route replaces it; a stretch only it used goes
    final d = c.withRoute('r1', ['G', 'M']);
    expect(d.lines.where((l) => l.problemId == 'r1').single.via, ['G', 'M']);
    expect(d.overlay.edges.any((e) => e.joins('G', 'F')), isFalse);
    expect(d.withoutRoute('r1').overlay.edges.any((e) => e.joins('G', 'M')), isFalse);
  });

  test('bending a stretch curves it through the finger and redraws its routes', () {
    final t = base.withRoute('r1', ['G', 'F', 'M']).withRoute('r2', ['F', 'M', 'L']);
    final i = t.overlay.edges.indexWhere((e) => e.joins('F', 'M'));
    final a = t.marks[1].at, b = t.marks[2].at;
    const finger = TopoPoint(0.4, 0.7); // pulled left from the middle
    final bent = t.withBend(i, bendThrough(a, b, finger, 0.5));
    final mid = bent.overlay.edges[i].points[8];
    expect(mid.x, closeTo(0.4, 1e-9));
    expect(mid.y, closeTo(0.7, 1e-9));
    for (final l in bent.lines) {
      expect(l.points.length, greaterThan(3), reason: 'both routes follow the curve');
    }
    final r2 = bent.lines.firstWhere((l) => l.problemId == 'r2');
    expect(r2.points.first, a);
    // straight again
    expect(bent.withBend(i, null).overlay.edges[i].points, [a, b]);
  });

  test('holds: rename and move carry their stretches and routes; removing drops routes through it', () {
    final t = base.withRoute('r1', ['G', 'F', 'M', 'L']);
    expect(t.withHoldRenamed('F', 'M'), isNull, reason: 'taken');
    final r = t.withHoldRenamed('F', 'Jug')!;
    expect(r.lines.single.via, ['G', 'Jug', 'M', 'L']);
    expect(r.overlay.edges.where((e) => e.joins('G', 'Jug')).length, 1);
    final m = t.withHoldAt('M', const TopoPoint(0.45, 0.55));
    expect(m.lines.single.points, contains(const TopoPoint(0.45, 0.55)));
    final gone = t.withoutHold('M');
    expect(gone.lines, isEmpty);
    expect(gone.overlay.edges, isEmpty);
    expect(gone.marks.map((x) => x.label), ['G', 'F', 'L']);
  });

  test('stretches and holds survive the database', () {
    final t = base.withRoute('r1', ['G', 'F']).withBend(0, const TopoPoint(0.6, 0.8));
    final back = Topo.fromRow(t.toRow());
    expect(back.marks.first.hold, isTrue);
    expect((back.overlay.edges.single.from, back.overlay.edges.single.to, back.overlay.edges.single.bend), ('G', 'F', const TopoPoint(0.6, 0.8)));
  });
}
