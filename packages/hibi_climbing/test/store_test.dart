import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/store.dart';
import 'package:test/test.dart';

void main() {
  ClimbSession session(String id, String start, {String place = 'Boulder Bar'}) =>
      ClimbSession.fromJson({'id': id, 'start': start, 'place': place, 'source': 'manual', 'climbs': [{'grade': '6A', 'outcome': 'sent', 'angle': 'vertical'}]});

  test('add keeps the order, update replaces, remove gives it back, and every change is announced', () async {
    final s = MemoryClimbingStore();
    var changes = 0;
    s.changes.listen((_) => changes++);
    s.add(session('b', '2026-11-12T10:00:00.000'));
    s.add(session('a', '2026-11-10T10:00:00.000'));
    expect(s.sessions.map((x) => x.id), ['a', 'b']);
    s.update(session('a', '2026-11-13T10:00:00.000'));
    expect(s.sessions.map((x) => x.id), ['b', 'a']);
    expect(s.remove('b')?.id, 'b');
    expect(s.remove('nope'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 4);
  });

  test('renaming a place moves its sessions with it', () {
    final s = MemoryClimbingStore(sessions: [session('a', '2026-11-10T10:00:00.000', place: 'Old Gym')]);
    s.savePlace(ClimbPlace(name: 'New Gym'), was: 'Old Gym');
    expect(s.sessions.single.place, 'New Gym');
    expect(s.places.map((p) => p.name), contains('New Gym'));
  });

  test('a store saves to events and comes back the same', () {
    final s = MemoryClimbingStore(sessions: [session('a', '2026-11-10T10:00:00.000')], places: [ClimbPlace(name: 'Boulder Bar')]);
    final back = MemoryClimbingStore.fromEvents(s.toEvents(recordedAt: DateTime(2026, 11, 17)));
    expect([for (final x in back.sessions) x.toJson()], [for (final x in s.sessions) x.toJson()]);
    expect(back.places.map((p) => p.name), ['Boulder Bar']);
  });
}
