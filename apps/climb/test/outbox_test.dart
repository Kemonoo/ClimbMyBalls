import 'dart:async';

import 'package:climb/outbox.dart';
import 'package:climb/shared_places.dart';
import 'package:climb/storage/text_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/topo.dart';
import 'package:climbing_cloud/climbing_cloud.dart';

class _Box implements TextBox {
  String? text;
  @override
  String? read() => text;
  @override
  void write(String t) => text = t;
}

Map<String, dynamic> _tick(String id, String problem, {String day = '2026-11-21'}) => {
  'id': id,
  'user_id': 'me',
  'problem_id': problem,
  'outcome': 'flash',
  'day': day,
  'created_at': '2026-11-21T10:00:00Z',
};

void main() {
  test('changes go out in order; no signal keeps the rest; a refused one is dropped and reported', () async {
    final file = _Box();
    final o = Outbox(file: file)
      ..add('tick.add', _tick('a', 'p1'))
      ..add('opinion', {'problem_id': 'p1', 'user_id': 'me', 'grade': '6A', 'stars': 3, 'tags': <String>[], 'project': false})
      ..add('comment.add', {'id': 'c1', 'user_id': 'me', 'problem_id': 'p1', 'body': 'nice', 'created_at': '2026-11-21T10:00:00Z'});

    // no signal at the second: the first went, two wait
    var calls = <String>[];
    expect(
      await o.flush((op) async {
        calls.add(op.kind);
        if (op.kind == 'opinion') throw TimeoutException('no signal');
      }),
      1,
    );
    expect(calls, ['tick.add', 'opinion']);
    expect(o.ops.map((x) => x.kind), ['opinion', 'comment.add']);

    // they survive a restart
    final again = Outbox.load(file);
    expect(again.ops.map((x) => x.kind), ['opinion', 'comment.add']);

    // the server refuses the opinion: dropped, said, the comment still goes
    calls = [];
    expect(
      await again.flush((op) async {
        calls.add(op.kind);
        if (op.kind == 'opinion') throw Exception('permission denied');
      }),
      2,
    );
    expect(again.ops, isEmpty);
    expect(again.refused, contains('opinion'));
  });

  test('waiting changes show on top of what the server last said', () {
    final o = Outbox()
      ..add('tick.add', _tick('new', 'p1'))
      ..add('tick.remove', {'id': 'old'})
      ..add('tick.day', {'id': 'kept', 'day': '2026-11-19'})
      ..add('opinion', {
        'problem_id': 'p1',
        'user_id': 'me',
        'grade': '6B',
        'stars': 4,
        'tags': ['crimps'],
        'project': true,
      })
      ..add('comment.add', {'id': 'c2', 'user_id': 'me', 'problem_id': 'p1', 'body': 'wet today', 'created_at': '2026-11-21T10:00:00Z'})
      ..add('comment.remove', {'id': 'c1'});
    final server = [CloudTick.fromRow(_tick('old', 'p1')), CloudTick.fromRow(_tick('kept', 'p1'))];
    final ticks = o.overTicks(server, problemId: 'p1');
    expect(ticks.map((t) => t.id), ['kept', 'new']);
    expect(ticks.first.day, DateTime(2026, 11, 19));
    expect(o.overTicks(server, problemId: 'p2').map((t) => t.id), ['kept'], reason: 'the new one is on p1');

    final ops = o.overOpinions(
      [const CloudOpinion(userId: 'me', problemId: 'p1', grade: '6A'), const CloudOpinion(userId: 'friend', problemId: 'p1', grade: '6C')],
      {'p1'},
    );
    expect(ops.map((x) => '${x.userId} ${x.grade}'), ['friend 6C', 'me 6B']);

    final comments = o.overComments([CloudComment(id: 'c1', userId: 'friend', problemId: 'p1', body: 'hi', createdAt: DateTime.utc(2026, 11, 20))], 'p1');
    expect(comments.map((c) => c.body), ['wet today']);
  });

  test('a new route made without signal shows at once and waits in the outbox', () async {
    final p = SharedPlaces(
      bundled: const [Place(id: 'b', kind: PlaceKind.boulder, name: 'Lúčka')],
      cloud: ClimbCloud(SupabaseClient('https://example.supabase.co', 'public-key')), // signed out: nothing is sent
      cacheFile: _Box(),
      outbox: Outbox(file: _Box()),
    );
    expect(p.waitingNote, isNull);
    final route = const Place(id: 'r1', parentId: 'b', kind: PlaceKind.problem, name: 'New line', grade: '6A');
    expect(await p.change('place.save', placeToRow(route)), isNull);
    expect(p.tree['r1']?.name, 'New line');
    expect(p.tree.childrenOf('b').map((x) => x.id), ['r1']);
    expect(p.outbox.ops.single.kind, 'place.save');
    expect(p.waitingNote, '1 change waits for signal (or Wi-Fi) to upload.');
    expect(p.cache.since, isNull, reason: 'a local change must not hide others\' changes from the next fetch');

    await p.change('place.delete', {'id': 'r1'});
    expect(p.tree['r1'], isNull);
  });

  test('publish and verify show at once and wait in the outbox; a new route starts unverified', () async {
    final p = SharedPlaces(
      bundled: const [Place(id: 'b', kind: PlaceKind.boulder, name: 'Lúčka')],
      cloud: ClimbCloud(SupabaseClient('https://example.supabase.co', 'public-key')),
      cacheFile: _Box(),
      outbox: Outbox(file: _Box()),
    );
    final e = CloudPlaceEditor(p);
    await e.save(const Place(id: 'r1', parentId: 'b', kind: PlaceKind.problem, name: 'New line', grade: '6A', draft: true));
    expect((p.tree['r1']!.draft, p.tree['r1']!.verified), (true, false));
    await e.publish(p.tree['r1']!);
    expect((p.tree['r1']!.draft, p.tree['r1']!.verified), (false, false), reason: 'not an editor, so not verified');
    await e.setVerified(p.tree['r1']!, true);
    expect(p.tree['r1']!.verified, isTrue);
    expect(p.outbox.ops.map((o) => o.kind), ['place.save', 'place.publish', 'place.verify']);
  });

  test('lines of routes you cannot see (a private one of someone else) are hidden on a section', () {
    final p = SharedPlaces(
      bundled: const [
        Place(id: 'b', kind: PlaceKind.boulder, name: 'Lúčka'),
        Place(id: 'seen', parentId: 'b', kind: PlaceKind.problem, name: 'A'),
      ],
      cacheFile: _Box(),
    );
    p.topos.merge([
      CloudTopo(
        topo: const Topo(
          id: 't',
          placeId: 'b',
          photoPath: 'x.jpg',
          lines: [
            TopoLine(problemId: 'seen', points: [TopoPoint(0, 0), TopoPoint(1, 1)]),
            TopoLine(problemId: 'hidden', points: [TopoPoint(0, 1), TopoPoint(1, 0)]),
          ],
        ),
        updatedAt: DateTime.utc(2026, 11, 21),
      ),
    ]);
    expect(CloudPlaceEditor(p).toposOf('b').single.lines.map((l) => l.problemId), ['seen']);

    // another angle of the section (#469): not a section of its own
    p.topos.merge([
      CloudTopo(
        topo: const Topo(id: 'a', placeId: 'b', photoPath: 'y.jpg', angleOf: 't'),
        updatedAt: DateTime.utc(2026, 11, 21, 1),
      ),
    ]);
    final e = CloudPlaceEditor(p);
    expect(e.toposOf('b').map((t) => t.id), ['t']);
    expect(e.anglesOf(e.toposOf('b').single).map((t) => t.id), ['a']);
  });

  test("lines come from their own rows (#516); drawing on someone else's photo saves only your line", () async {
    const t = Topo(
      id: 't',
      placeId: 'b',
      photoPath: 'x.jpg',
      createdBy: 'owner',
      lines: [TopoLine(problemId: 'old', points: [TopoPoint(0, 0), TopoPoint(1, 1)])], // the copy in the section's row
    );
    CloudLine row(String id, String problem, int ord, {String by = 'owner'}) => CloudLine(
      topoId: 't',
      ord: ord,
      updatedAt: DateTime.utc(2026, 11, 22),
      line: TopoLine(id: id, problemId: problem, createdBy: by, points: const [TopoPoint(0, 1), TopoPoint(1, 0)]),
    );
    final p = SharedPlaces(
      bundled: const [
        Place(id: 'b', kind: PlaceKind.boulder, name: 'Lúčka'),
        Place(id: 'p1', parentId: 'b', kind: PlaceKind.problem, name: 'One'),
        Place(id: 'p2', parentId: 'b', kind: PlaceKind.problem, name: 'Two'),
        Place(id: 'mine', parentId: 'b', kind: PlaceKind.problem, name: 'Mine'),
        Place(id: 'old', parentId: 'b', kind: PlaceKind.problem, name: 'Old'),
      ],
      cloud: ClimbCloud(SupabaseClient('https://example.supabase.co', 'public-key')), // signed out: not an editor
      cacheFile: _Box(),
      outbox: Outbox(file: _Box()),
    );
    p.topos.merge([CloudTopo(topo: t, updatedAt: DateTime.utc(2026, 11, 22))]);
    final e = CloudPlaceEditor(p);
    expect(e.toposOf('b').single.lines.map((l) => l.problemId), ['old'], reason: "before lines have rows: the section's own");

    p.lines.merge([row('l2', 'p2', 1), row('l1', 'p1', 0)]);
    final shown = e.toposOf('b').single;
    expect(shown.lines.map((l) => l.problemId), ['p1', 'p2'], reason: 'from the rows, in their order');

    // add your route's line; someone else's line you can't take away
    await e.saveTopo(shown.copyWith(lines: [shown.lines[1], const TopoLine(problemId: 'mine', points: [TopoPoint(.5, .5), TopoPoint(.6, .1)])]));
    final ops = p.outbox.ops.map((o) => o.kind).toList();
    expect(ops, ['line.save'], reason: "not the section (not yours), not the others' lines");
    final saved = p.outbox.ops.single.data;
    expect((saved['problem_id'], saved['ord'], saved['in_guide']), ('mine', 1, false), reason: 'a community line');
    expect(e.toposOf('b').single.lines.map((l) => l.problemId), ['p1', 'p2', 'mine'], reason: 'shown at once');
  });

  test('stars and favourites work without signal and wait in the outbox (#518)', () async {
    final file = _Box();
    final p = SharedPlaces(
      bundled: const [Place(id: 'b', kind: PlaceKind.boulder, name: 'Lúčka')],
      cloud: ClimbCloud(SupabaseClient('https://example.supabase.co', 'public-key')),
      cacheFile: file,
      outbox: Outbox(file: _Box()),
    );
    final e = CloudPlaceEditor(p);
    p.starCounts['place:b'] = 4;
    await e.setStar('place', 'b', true);
    expect((e.starredByMe('place', 'b'), e.starsOf('place', 'b')), (true, 5));
    await e.setStar('place', 'b', true);
    expect(e.starsOf('place', 'b'), 5, reason: 'a second tap on a starred thing does not count twice');
    await e.setFavourite('topo', 't1', true);
    await e.setFavourite('place', 'b', true);
    expect(e.favourites, [('place', 'b'), ('topo', 't1')], reason: 'newest first');
    await e.setFavourite('topo', 't1', false);
    expect(e.favourites, [('place', 'b')]);
    expect(p.outbox.ops.map((o) => o.kind), ['star', 'star', 'fav', 'fav', 'fav']);
    expect(file.text, contains('"stars":["place:b"]'), reason: 'kept on the phone');
  });

  test('Wi-Fi only: nothing is sent on mobile data', () async {
    final o = Outbox(wifiOnly: true)..add('tick.remove', {'id': 'x'});
    final p = SharedPlaces(bundled: const [], outbox: o, onWifi: () async => false);
    expect(await p.send(), isNull);
    expect(o.ops.length, 1);
  });

  test('ids made on the phone are UUIDs', () {
    expect(newUuid(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });
}
