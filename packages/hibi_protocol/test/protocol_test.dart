import 'package:hibi_protocol/hibi_protocol.dart';
import 'package:test/test.dart';

void main() {
  final t = DateTime(2026, 11, 15, 18, 20);
  Event ev(String id, {String? replaces, bool deleted = false}) =>
      Event(id: id, module: 'climbing', type: 'climbing.ascent', at: t, data: {'grade': '6B'}, source: const SourceRef('phone.manual', device: 'phone'), recordedAt: t, replaces: replaces, deleted: deleted);

  test('an event survives JSON', () {
    final e = ev('e1');
    expect(Event.fromJson(e.toJson()).toJson(), e.toJson());
  });

  test('corrections replace, deletions drop out', () {
    final live = current([ev('e1'), ev('e2', replaces: 'e1'), ev('e3'), ev('e4', replaces: 'e3', deleted: true)]);
    expect(live.map((e) => e.id), ['e2']);
  });

  test('a manifest with goals survives JSON', () {
    final m = ModuleManifest(
      id: 'climbing',
      name: 'Climbing',
      version: '0.1.0',
      kind: ModuleKind.skill,
      events: const [EventType('climbing.session', {'place': 'place'}, span: true)],
      metrics: const [MetricDef('climbing.sessions_per_week', of: 'climbing.session', agg: 'count', per: 'week', judge: Judge('range', min: 2, max: 4))],
      goals: [Goal(id: 'g1', module: 'climbing', title: 'Send 7A', metric: 'climbing.max_grade', op: '>=', value: '7A', by: DateTime(2027, 6, 30))],
    );
    expect(ModuleManifest.fromJson(m.toJson()).toJson(), m.toJson());
  });
}
