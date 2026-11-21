import 'dart:async';

import 'package:climb/outbox.dart';
import 'package:climb/shared_places.dart';
import 'package:climb/storage/text_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/place.dart';
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
