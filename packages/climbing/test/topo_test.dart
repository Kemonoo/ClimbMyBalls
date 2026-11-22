import 'package:climbing/places/topo.dart';
import 'package:test/test.dart';

void main() {
  const lines = [
    // 1: straight up the left side
    TopoLine(problemId: 'p1', points: [TopoPoint(0.2, 0.9), TopoPoint(0.2, 0.1)], sitStart: true),
    // 2: a traverse along the bottom, yellow, carrying on
    TopoLine(problemId: 'p2', points: [TopoPoint(0.1, 0.8), TopoPoint(0.5, 0.75), TopoPoint(0.9, 0.8)], end: TopoEnd.hold, color: '#f2c94c'),
  ];
  const topo = Topo(
    id: 't',
    placeId: 'b',
    photoPath: 'u1/t.jpg',
    bearing: 200,
    width: 1600,
    height: 1200,
    marks: [TopoMark('A', TopoPoint(0.1, 0.8)), TopoMark('B', TopoPoint(0.2, 0.9))],
    lines: lines,
  );

  test('a topo survives the trip through a database row', () {
    final back = Topo.fromRow({...topo.toRow(), 'created_by': 'u1'});
    expect(back.toRow(), topo.toRow());
    expect(back.lines[0].sitStart, isTrue);
    expect(back.lines[1].end, TopoEnd.hold);
    expect(back.lines[1].color, '#f2c94c');
    expect(back.marks.map((m) => m.label), ['A', 'B']);
    expect(back.createdBy, 'u1');
    expect(back.angleOf, isNull);
    expect(topo.toRow().containsKey('angle_of'), isFalse, reason: 'sections work on a database without 009');
    final angle = Topo.fromRow({...topo.toRow(), 'id': 'a2', 'angle_of': topo.id});
    expect((angle.angleOf, angle.copyWith(name: 'x').angleOf, angle.toRow()['angle_of']), (topo.id, topo.id, topo.id));
  });

  test('tapping finds the nearest line within reach, on the real photo shape', () {
    expect(topo.lineAt(const TopoPoint(0.21, 0.5)), 0);
    expect(topo.lineAt(const TopoPoint(0.5, 0.76)), 1);
    expect(topo.lineAt(const TopoPoint(0.7, 0.3)), isNull);
    // where both are close, the nearer one wins
    expect(topo.lineAt(const TopoPoint(0.25, 0.78)), 1);
    expect(topo.markAt(const TopoPoint(0.11, 0.8)), 0);
    expect(topo.markAt(const TopoPoint(0.5, 0.5)), isNull);
  });

  test('the next letter skips used ones', () {
    expect(topo.nextLabel(), 'C');
    expect(const Topo(id: 'x', placeId: 'b', photoPath: '').nextLabel(), 'A');
    final full = Topo(id: 'x', placeId: 'b', photoPath: '', marks: [for (var i = 0; i < 26; i++) TopoMark(String.fromCharCode(65 + i), const TopoPoint(0, 0))]);
    expect(full.nextLabel(), 'AA');
  });

  test('bearing labels', () {
    expect(bearingLabel(0), 'N');
    expect(bearingLabel(200), 'S');
    expect(bearingLabel(350), 'N');
    expect(bearingLabel(null), '');
  });

  test('a section keeps its name, second photo and listed-only routes', () {
    const t = Topo(
      id: 't2',
      placeId: 'b',
      photoPath: 'u1/x.jpg',
      name: 'lucka 01',
      originalPath: 'u1/x-guide.jpg',
      marks: [TopoMark('G', TopoPoint(0.8, 0.8)), TopoMark('H', TopoPoint(0.1, 0.1))],
      lines: [
        TopoLine(problemId: 'p6', points: [], via: ['G', 'H'], end: TopoEnd.hold),
      ],
    );
    final back = Topo.fromRow(t.toRow());
    expect(back.name, 'lucka 01');
    expect(back.originalPath, 'u1/x-guide.jpg');
    expect(back.lines.single.via, ['G', 'H']);
    expect(back.lines.single.end, TopoEnd.hold);
  });

  test('old rows: "top" ends at a hold, "arrow" tops out', () {
    expect(TopoLine.fromJson({'problem': 'p', 'end': 'top'}).end, TopoEnd.hold);
    expect(TopoLine.fromJson({'problem': 'p', 'end': 'arrow'}).end, TopoEnd.topOut);
  });

  test('a letter finds the routes through it, drawn or listed', () {
    // A sits on the traverse's start; B on line 1's start
    expect(topo.linesThrough('A'), {1});
    expect(topo.linesThrough('B'), {0});
    expect(topo.linesThrough('Z'), isEmpty);
    final listed = topo.copyWith(
      lines: [
        ...topo.lines,
        const TopoLine(problemId: 'p3', points: [], via: ['A']),
      ],
    );
    expect(listed.linesThrough('A'), {1, 2});
  });

  test("a guide's drawing survives the database: each stretch once, numbers, start holds", () {
    const t = Topo(
      id: 't',
      placeId: 'b',
      photoPath: 'p',
      overlay: TopoOverlay(
        edges: [TopoEdge([TopoPoint(0.1, 0.9), TopoPoint(0.2, 0.1)], arrow: true), TopoEdge([TopoPoint(0, 0.5), TopoPoint(1, 0.5)], color: '#f2c94c')],
        numbers: [TopoLabel('28.', TopoPoint(0.5, 0.2))],
        starts: [TopoPoint(0.1, 0.92)],
      ),
    );
    final back = Topo.fromRow(t.toRow());
    expect(back.overlay.edges.map((e) => (e.points.length, e.arrow, e.color)), [(2, true, '#ffffff'), (2, false, '#f2c94c')]);
    expect(back.overlay.numbers.single.text, '28.');
    expect(back.overlay.starts.single, const TopoPoint(0.1, 0.92));
    expect(Topo.fromRow(const Topo(id: 'u', placeId: 'b', photoPath: 'p').toRow()).overlay.isEmpty, isTrue);
  });
}
