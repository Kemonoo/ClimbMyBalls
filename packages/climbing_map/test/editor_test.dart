import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:climbing/places/topo.dart';
import 'package:climbing_map/climbing_map.dart';

class _Editor extends PlaceEditor {
  _Editor(this.places);
  final List<Place> places;
  final saved = <Place>[];
  var n = 0;
  @override
  bool signedIn = true;
  @override
  String? get me => 'u1';
  @override
  bool isAdmin = false;
  final scoped = <String>{};
  @override
  bool mayEdit(String placeId) => scoped.contains(placeId);
  @override
  String? createdBy(String placeId) => saved.any((p) => p.id == placeId) ? 'u1' : null;
  @override
  DateTime? createdAt(String placeId) => DateTime(2026, 11, 19);
  @override
  String nameOf(String? userId) => userId == 'u1' ? 'Alex' : '';
  final ascents = <Ascent>[];
  final opinions = <String, Opinion>{};
  final comments = <RouteComment>[];
  @override
  Future<List<Opinion>> opinionsOf(String problemId) async => opinions.values.toList();
  @override
  Future<String?> setOpinion(String problemId, {required String grade, required int stars, required List<String> tags, required bool project}) async {
    opinions['u1'] = (userId: 'u1', who: 'Alex', grade: grade, stars: stars, tags: tags, project: project);
    return null;
  }

  @override
  Future<List<RouteComment>> commentsOf(String problemId) async => List.of(comments);
  @override
  Future<String?> addComment(String problemId, String body) async {
    comments.add((id: 'c${comments.length}', userId: 'u1', who: 'Alex', body: body, at: DateTime(2026, 11, 20, 18)));
    return null;
  }

  @override
  Future<List<Ascent>> ascentsOf(String problemId) async => List.of(ascents);
  @override
  Future<String?> logAscent(String problemId, String outcome) async {
    ascents.insert(0, (id: 'a${ascents.length}', userId: 'u1', who: 'Alex', day: DateTime(2026, 11, 20), outcome: outcome));
    return null;
  }

  @override
  Future<String?> removeAscent(String id) async {
    ascents.removeWhere((a) => a.id == id);
    return null;
  }

    @override
  Future<String?> setAscentDay(String id, DateTime day) async {
    final i = ascents.indexWhere((a) => a.id == id);
    final a = ascents[i];
    ascents[i] = (id: a.id, userId: a.userId, who: a.who, day: day, outcome: a.outcome);
    return null;
  }

  @override
  List<String> get guides => const [];
  @override
  Future<String?> importGuide(String guide, Place boulder) async => null;
  @override
  Future<String?> deleteTopo(Topo t) async {
    topos.removeWhere((x) => x.id == t.id);
    return null;
  }

  @override
  String newId() => 'c-${++n}';
  @override
  Future<String?> save(Place p) async {
    saved.add(p);
    places.add(p);
    return null;
  }

  @override
  Future<String?> delete(Place p) async => null;

  final topos = <Topo>[];
  TopoPhoto? uploaded;
  @override
  List<Topo> toposOf(String placeId) => [
    for (final t in topos)
      if (t.placeId == placeId) t,
  ];
  @override
  ImageProvider photoOf(Topo t, {bool original = false}) => MemoryImage(_png);
  @override
  Future<TopoPhoto?> pickPhoto({required bool camera}) async => TopoPhoto(_png, 400, 300);
  @override
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) async {
    uploaded = photo ?? uploaded;
    topos.removeWhere((x) => x.id == t.id);
    topos.add(t.copyWith(photoPath: t.photoPath.isEmpty ? 'u1/${t.id}.jpg' : null));
    return null;
  }
}

final _topoPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is TopoPainter);

// A 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  final base = [
    const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'),
    const Place(id: 'devin', parentId: 'sk', kind: PlaceKind.area, name: 'Devín', geometry: PointGeometry(LatLng(48.1745, 16.9790))),
  ];

  Future<_Editor> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final e = _Editor([...base]);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) => ClimbMapScreen(
              places: PlaceTree(e.places),
              locator: const FixedLocator(LatLng(48.1748, 16.9786)),
              editor: _RefreshingEditor(e, () => set(() {})),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    return e;
  }

  testWidgets('add a boulder: spot, name and parent, outline by taps, save', (t) async {
    final e = await pump(t);
    await t.tap(find.byTooltip('Add a place'));
    await t.pump();
    expect(find.text('Where is it?'), findsOneWidget);
    await t.tap(find.text('Here'));
    await t.pumpAndSettle();
    expect(find.text('New place'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Lúčka');
    await t.tap(find.text('Next: draw its outline'));
    await t.pumpAndSettle();
    expect(find.text('Outline of Lúčka'), findsOneWidget);
    await t.tap(find.text('Tap points'));
    await t.pump();
    for (final o in const [Offset(180, 380), Offset(240, 380), Offset(240, 440)]) {
      await t.tapAt(o);
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.textContaining('3 points'), findsOneWidget);
    // drag the first point: the map holds still, a magnifier follows the finger
    final g = await t.startGesture(const Offset(180, 380));
    await t.pump();
    await g.moveBy(const Offset(0, -20));
    await t.pump();
    await g.moveBy(const Offset(0, -20));
    await t.pump();
    expect(find.byType(RawMagnifier), findsOneWidget);
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(RawMagnifier), findsNothing);
    expect(find.textContaining('3 points'), findsOneWidget, reason: 'a drag is not a new point');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final b = e.saved.single;
    expect((b.kind, b.name, b.parentId), (PlaceKind.boulder, 'Lúčka', 'devin'));
    final ring = (b.geometry as PolygonGeometry).ring;
    expect(ring, hasLength(3));
    expect(ring[0].lat, greaterThan(ring[1].lat), reason: 'the first point moved up (north), the others stayed level');
    expect(find.text('Where is it?'), findsNothing);
  });

  testWidgets('a boulder from a preset shape: resize, save as an outline; tapping the map offers to add there', (t) async {
    final e = await pump(t);
    await t.tapAt(const Offset(210, 520)); // empty map
    await t.pump(const Duration(milliseconds: 400)); // the map waits to rule out a double tap
    await t.tap(find.text('Add a place here'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Veľký kameň');
    await t.tap(find.text('Next: draw its outline'));
    await t.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget); // the shape tool is the default
    await t.drag(find.byType(Slider).first, const Offset(60, 0));
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final b = e.saved.single;
    expect((b.geometry as PolygonGeometry).ring, hasLength(10));
    // the new boulder's page opens straight away
    expect(find.byTooltip('Add route'), findsOneWidget);
    expect(find.text('New section'), findsOneWidget);
    expect(find.text('Boulders 0'), findsOneWidget);
    expect(b.name, 'Veľký kameň');
  });

  testWidgets('add a problem to a boulder: name and grade needed, the rest optional', (t) async {
    final e = await pump(t);
    e.places.add(const Place(id: 'b', parentId: 'devin', kind: PlaceKind.boulder, name: 'Jaskynka', geometry: PointGeometry(LatLng(48.1749, 16.9787))));
    // open the boulder from the near-me list
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClimbMapScreen(places: PlaceTree(e.places), locator: const FixedLocator(LatLng(48.1748, 16.9786)), editor: e),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.widgetWithText(ListTile, 'Jaskynka'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Add route'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save problem'));
    await t.pump();
    expect(find.text('Give it a name.'), findsOneWidget);
    expect(find.text('Pick a grade.'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Latrinátor');
    await t.tap(find.text('Rope'));
    await t.pump();
    await t.tap(find.byType(DropdownMenu<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('3+/4-').last); // near the top of the list
    await t.pumpAndSettle();
    await t.tap(find.text('Stand').first); // the start menu
    await t.pumpAndSettle();
    await t.tap(find.text('Sit, low (SD low)').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Save problem'));
    await t.tap(find.text('Save problem'));
    await t.pumpAndSettle();
    final p = e.saved.single;
    expect((p.kind, p.parentId, p.grade, p.isRope, p.sitStart, p.sitHeight), (PlaceKind.problem, 'b', '3+/4-', true, true, 'low'));
    expect(p.number, '1');
    expect(p.note, '');
  });

  testWidgets('press and slide on the photo: a magnifier follows, the hold lands where you let go', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final e = _Editor([...base, const Place(id: 'b', parentId: 'devin', kind: PlaceKind.boulder, name: 'Lúčka', geometry: PointGeometry(LatLng(48.1749, 16.9787)))]);
    final tree = PlaceTree(e.places);
    const topo = Topo(id: 't1', placeId: 'b', photoPath: '', width: 400, height: 300, createdBy: 'u1');
    await t.pumpWidget(
      MaterialApp(
        home: TopoEditorScreen(tree: tree, boulder: tree['b']!, topo: topo, editor: e, newPhoto: TopoPhoto(_png, 400, 300)),
      ),
    );
    await t.pumpAndSettle();
    Offset at(double x, double y) {
      final photo = t.getRect(_topoPaint);
      return Offset(photo.left + photo.width * x, photo.top + photo.height * y);
    }

    expect(find.byType(RawMagnifier), findsNothing);
    final g = await t.startGesture(at(0.2, 0.6));
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(at(0.2 + 0.04 * i, 0.6));
      await t.pump();
    }
    expect(find.byType(RawMagnifier), findsOneWidget);
    await g.up();
    await t.pump();
    expect(find.byType(RawMagnifier), findsNothing);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final m = e.topos.single.marks.single;
    expect(m.label, 'A');
    expect(m.at.x, closeTo(0.4, 0.01));
    expect(m.at.y, closeTo(0.6, 0.01));
  });

  testWidgets('a section: holds, a route built from them, a bent line, save; then a hold shows its routes', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    final e = _Editor([
      ...base,
      const Place(id: 'b', parentId: 'devin', kind: PlaceKind.boulder, name: 'Lúčka', geometry: PointGeometry(LatLng(48.1749, 16.9787))),
      const Place(id: 'p1', parentId: 'b', kind: PlaceKind.problem, name: 'Dunaj', grade: '7B', details: {'number': 20, 'note': 'start N, up to X'}),
    ]);
    final tree = PlaceTree(e.places);
    const topo = Topo(id: 't1', placeId: 'b', photoPath: '', width: 400, height: 300, createdBy: 'u1');
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    nav.currentState!.push(
      MaterialPageRoute<Topo>(
        builder: (_) => TopoEditorScreen(tree: tree, boulder: tree['b']!, topo: topo, editor: e, newPhoto: TopoPhoto(_png, 400, 300)),
      ),
    );
    await t.pumpAndSettle();
    Offset at(double x, double y) {
      final photo = t.getRect(_topoPaint);
      return Offset(photo.left + photo.width * x, photo.top + photo.height * y);
    }

    // a new section starts on the Holds tool
    for (final (x, y) in const [(0.3, 0.8), (0.4, 0.5), (0.5, 0.2)]) {
      await t.tapAt(at(x, y));
      await t.pump(const Duration(milliseconds: 400));
    }
    // rename B
    await t.tapAt(at(0.4, 0.5));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Jug');
    await t.tap(find.text('Save name'));
    await t.pumpAndSettle();
    await t.tap(find.text('Routes'));
    await t.pump();
    await t.tap(find.text('Draw a route'));
    await t.pumpAndSettle();
    await t.tap(find.text('20 Dunaj'));
    await t.pumpAndSettle();
    for (final (x, y) in const [(0.3, 0.8), (0.4, 0.5), (0.5, 0.2)]) {
      await t.tapAt(at(x, y));
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(find.textContaining('A → Jug → C'), findsOneWidget);
    await t.tap(find.text('Ends: top out ↑'));
    await t.enterText(find.widgetWithText(TextField, 'Section name'), 'lucka 01');
    await t.tap(find.text('Done'));
    await t.pump();
    // bend the A–Jug stretch to the left from its middle
    await t.tap(find.text('Bend'));
    await t.pump();
    final g = await t.startGesture(at(0.35, 0.65));
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(at(0.35 - 0.02 * i, 0.65));
      await t.pump();
    }
    await g.up();
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final saved = e.topos.single;
    expect(saved.marks.map((m) => m.label), ['A', 'Jug', 'C']);
    expect(saved.marks.every((m) => m.hold), isTrue);
    final line = saved.lines.single;
    expect((line.problemId, line.end, line.alone), ('p1', TopoEnd.hold, true));
    expect(line.via, ['A', 'Jug', 'C']);
    expect(saved.overlay.edges.length, 2);
    final bent = saved.overlay.edges.firstWhere((x) => x.joins('A', 'Jug'));
    expect(bent.bend, isNotNull);
    expect(line.points.length, greaterThan(3), reason: 'the route follows the bend');
    expect(line.points.first.toJson(), [0.3, 0.8]);
    expect(line.points.last.toJson(), [0.5, 0.2]);
    expect(saved.name, 'lucka 01');
    expect(e.uploaded, isNotNull);

    await t.pumpWidget(
      MaterialApp(
        home: TopoScreen(tree: tree, boulder: tree['b']!, topo: saved, editor: e),
      ),
    );
    await t.pump();
    final shown = t.getRect(_topoPaint);
    expect(find.text('lucka 01'), findsOneWidget);
    await t.tapAt(Offset(shown.left + shown.width * 0.3, shown.top + shown.height * 0.8));
    await t.pumpAndSettle();
    expect(find.text('Routes through A: 1'), findsOneWidget);
    expect(find.text('20 Dunaj'), findsOneWidget);
    expect(find.byTooltip('Edit section'), findsOneWidget);
  });

  test('a right on a place lets you edit it and its sections, nothing else', () {
    final e = _Editor([])..scoped.add('b1');
    expect(canEdit(e, 'b1'), isTrue);
    expect(canEdit(e, 'b2'), isFalse);
    expect(canEditTopo(e, const Topo(id: 't1', placeId: 'b1', photoPath: 'u9/t1.jpg', createdBy: 'u9')), isTrue);
    expect(canEditTopo(e, const Topo(id: 't2', placeId: 'b2', photoPath: 'u9/t2.jpg', createdBy: 'u9')), isFalse);
    e.signedIn = false;
    expect(canEdit(e, 'b1'), isFalse);
  });

  test('route numbers: their own first, then by name after them', () {
    final tree = PlaceTree([
      const Place(id: 'b', kind: PlaceKind.boulder, name: 'B'),
      const Place(id: 'x', parentId: 'b', kind: PlaceKind.problem, name: 'Alfa', details: {'number': 7}),
      const Place(id: 'y', parentId: 'b', kind: PlaceKind.problem, name: 'Beta'),
      const Place(id: 'z', parentId: 'b', kind: PlaceKind.problem, name: 'Ceta'),
    ]);
    expect(problemNumbers(tree, 'b'), {'x': '7', 'y': '8', 'z': '9'});
    expect(nextProblemNumber(tree, 'b'), 10);
    expect(newTopoId(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  group('a section with boulders and rope routes', () {
    final places = [
      ...base,
      const Place(id: 'b', parentId: 'devin', kind: PlaceKind.boulder, name: 'Hradná skala', geometry: PointGeometry(LatLng(48.1749, 16.9787))),
      const Place(
        id: 'p7',
        parentId: 'b',
        kind: PlaceKind.problem,
        name: '7 zverokruh',
        grade: '8A',
        details: {'number': '7', 'note': 'traverse the whole boulder'},
      ),
      const Place(id: 'p35', parentId: 'b', kind: PlaceKind.problem, name: '35 diagonal', grade: '6C+', details: {'number': '35', 'sit': true}),
      const Place(
        id: 'p28',
        parentId: 'b',
        kind: PlaceKind.problem,
        name: '28 chlieb',
        grade: '7B',
        details: {'number': '28', 'sit': true, 'sitHeight': 'high'},
      ),
      Place(
        id: 'p8',
        parentId: 'b',
        kind: PlaceKind.problem,
        name: '8 dunaj direkt',
        gradeSystem: GradeSystem.uiaa,
        grade: '10',
        details: const {'number': '8'},
      ),
    ];
    const topo = Topo(
      id: 't1',
      placeId: 'b',
      photoPath: 'x.jpg',
      name: 'lucka 01',
      originalPath: 'x-guide.jpg',
      width: 400,
      height: 300,
      createdBy: 'u9',
      marks: [TopoMark('B', TopoPoint(0.6, 0.85)), TopoMark('Q', TopoPoint(0.4, 0.55))],
      lines: [
        TopoLine(problemId: 'p7', points: [TopoPoint(0.05, 0.7), TopoPoint(0.6, 0.7)], color: '#f2c94c'),
        TopoLine(problemId: 'p35', points: [TopoPoint(0.6, 0.85), TopoPoint(0.4, 0.55)], end: TopoEnd.hold),
        TopoLine(problemId: 'p28', points: [TopoPoint(0.35, 0.9), TopoPoint(0.4, 0.55), TopoPoint(0.45, 0.1)]),
        TopoLine(problemId: 'p8', points: [TopoPoint(0.55, 0.75), TopoPoint(0.55, 0.05)]),
      ],
    );

    Future<_Editor> open(WidgetTester t, {bool admin = false}) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      final e = _Editor([...places])
        ..isAdmin = admin
        ..topos.add(topo);
      final tree = PlaceTree(e.places);
      await t.pumpWidget(
        MaterialApp(
          home: TopoScreen(tree: tree, boulder: tree['b']!, topo: topo, editor: e),
        ),
      );
      await t.pump();
      return e;
    }

    testWidgets('boulders by grade in one tab, rope routes in the other; starts on the right', (t) async {
      await open(t);
      expect(find.text('Boulders 3'), findsOneWidget);
      expect(find.text('Rope 1'), findsOneWidget);
      final names = ['35 diagonal', '28 chlieb', '7 zverokruh'];
      final ys = [for (final n in names) t.getTopLeft(find.text(n)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'easiest first');
      expect(find.text('SD high'), findsOneWidget);
      expect(find.text('8 dunaj direkt'), findsNothing);
      await t.tap(find.text('Rope 1'));
      await t.pumpAndSettle();
      expect(find.text('8 dunaj direkt'), findsOneWidget);
      expect(find.byTooltip('Edit section'), findsNothing, reason: 'not yours, not an admin');
    });

    testWidgets('the boulder page: its sections on top, every route, search', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      final e = _Editor([...places])..topos.add(topo);
      await t.pumpWidget(MaterialApp(home: BoulderScreen(tree: () => PlaceTree(e.places), boulderId: 'b', editor: e)));
      await t.pump();
      expect(find.textContaining('lucka 01 · tap to open'), findsOneWidget);
      expect(find.text('Boulders 3'), findsOneWidget);
      expect(find.text('Rope 1'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'chlieb');
      await t.pump();
      expect(find.text('Boulders 1'), findsOneWidget);
      expect(find.text('28 chlieb'), findsOneWidget);
      await t.enterText(find.byType(TextField), '6C+');
      await t.pump();
      expect(find.text('35 diagonal'), findsOneWidget);
      await t.tap(find.text('lucka 01').first);
      await t.pumpAndSettle();
      expect(find.text('Boulders 3'), findsOneWidget, reason: 'the section screen opened');
    });

    testWidgets('tapping a letter shows only the routes through it', (t) async {
      await open(t);
      final r = t.getRect(_topoPaint);
      await t.tapAt(Offset(r.left + r.width * 0.4, r.top + r.height * 0.55)); // Q
      await t.pumpAndSettle();
      expect(find.text('Routes through Q: 2'), findsOneWidget);
      expect(find.text('7 zverokruh'), findsNothing);
      expect(find.text('35 diagonal'), findsOneWidget);
      expect(find.text('28 chlieb'), findsOneWidget);
      await t.tap(find.text('Routes through Q: 2'));
      await t.pumpAndSettle();
      expect(find.text('7 zverokruh'), findsOneWidget);
    });

    testWidgets('a route: its page, log an ascent, admins edit anyone\'s', (t) async {
      final e = await open(t, admin: true);
      expect(find.byTooltip('Edit section'), findsOneWidget);
      expect(find.byTooltip("The guide's original"), findsOneWidget);
      await t.tap(find.text('7 zverokruh'));
      await t.pumpAndSettle();
      expect(find.text('Topped by'), findsOneWidget);
      expect(find.text('Log a Flash or a Top to vote.'), findsOneWidget);
      await t.tap(find.text('Flash'));
      await t.pumpAndSettle();
      expect(find.text('Topped by 1'), findsOneWidget);
      // how did it feel: one grade harder, then the chart counts the vote
      await t.tap(find.byTooltip('Harder'));
      await t.pumpAndSettle();
      expect(e.opinions['u1']!.grade, '8A+');
      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('Feels like 8A+'), findsOneWidget);
      await t.tap(find.byTooltip('4 stars'));
      await t.pumpAndSettle();
      expect(e.opinions['u1']!.stars, 4);
      expect(find.text('★ 4.0 · 1 rating'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Crimps'), 200, scrollable: find.byType(Scrollable).at(1));
      await t.tap(find.text('Crimps'));
      await t.pumpAndSettle();
      expect(e.opinions['u1']!.tags, ['crimps']);
      expect(find.text('Crimps 1'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Project'), 200, scrollable: find.byType(Scrollable).at(1));
      await t.tap(find.text('Project'));
      await t.pumpAndSettle();
      expect(e.opinions['u1']!.project, isTrue);
      expect(e.opinions['u1']!.stars, 4); // the rest of your opinion stays
      await t.scrollUntilVisible(find.text('traverse the whole boulder'), 200, scrollable: find.byType(Scrollable).at(1));
      // comments
      await t.tap(find.text('Comments'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Start hold is wet after rain');
      await t.tap(find.byTooltip('Post comment'));
      await t.pumpAndSettle();
      expect(find.text('Start hold is wet after rain'), findsOneWidget);
      expect(find.text('Comments 1'), findsOneWidget);
      // who topped it: your own ascent's day can change
      await t.tap(find.text('Topped by 1'));
      await t.pumpAndSettle();
      expect(find.textContaining('Flash · 20/11/26'), findsOneWidget);
      await t.tap(find.textContaining('Flash · 20/11/26'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Edit route'), findsOneWidget);
      expect(find.byTooltip('Undo your last log'), findsOneWidget);
      e.isAdmin = false;
    });
  });

  testWidgets('signed out: adding asks you to sign in', (t) async {
    final e = await pump(t);
    e.signedIn = false;
    await t.tap(find.byTooltip('Add a place'));
    await t.pump();
    expect(find.textContaining('Sign in on the Friends tab to add places'), findsOneWidget);
    expect(find.text('Where is it?'), findsNothing);
  });
}

/// Saves, then rebuilds the screen with the new places, like the app does.
class _RefreshingEditor extends PlaceEditor {
  _RefreshingEditor(this.e, this.refresh);
  final _Editor e;
  final VoidCallback refresh;
  @override
  bool get signedIn => e.signedIn;
  @override
  String? get me => e.me;
  @override
  bool get isAdmin => e.isAdmin;
  @override
  bool mayEdit(String id) => e.mayEdit(id);
  @override
  String? createdBy(String id) => e.createdBy(id);
  @override
  DateTime? createdAt(String id) => e.createdAt(id);
  @override
  String nameOf(String? id) => e.nameOf(id);
  @override
  Future<List<Ascent>> ascentsOf(String id) => e.ascentsOf(id);
  @override
  Future<String?> logAscent(String id, String outcome) => e.logAscent(id, outcome);
    @override
  Future<String?> removeAscent(String id) => e.removeAscent(id);
  @override
  Future<String?> setAscentDay(String id, DateTime day) => e.setAscentDay(id, day);
  @override
  List<String> get guides => e.guides;
  @override
  Future<String?> importGuide(String guide, Place boulder) => e.importGuide(guide, boulder);
  @override
  Future<String?> deleteTopo(Topo t) => e.deleteTopo(t);
  @override
  String newId() => e.newId();
  @override
  Future<String?> save(Place p) async {
    final r = await e.save(p);
    refresh();
    return r;
  }

  @override
  Future<String?> delete(Place p) => e.delete(p);
  @override
  List<Topo> toposOf(String placeId) => e.toposOf(placeId);
  @override
  ImageProvider photoOf(Topo t, {bool original = false}) => e.photoOf(t, original: original);
  @override
  Future<TopoPhoto?> pickPhoto({required bool camera}) => e.pickPhoto(camera: camera);
  @override
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) => e.saveTopo(t, photo: photo);
}
