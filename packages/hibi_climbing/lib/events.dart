// Climbing in the hibi protocol v0.1 (docs/protocol/v0.1.md, section 7):
// its manifest, and today's sessions, climbs and places as events and back,
// without loss. The test of v0.1 is that real climbing history survives this.
import 'package:hibi_protocol/hibi_protocol.dart';

import 'climbing.dart';

const kClimbingManifest = ModuleManifest(
  id: 'climbing',
  name: 'Climbing',
  version: '0.1.0',
  kind: ModuleKind.skill,
  events: [
    EventType('climbing.session', {'place': 'place', 'outdoor': 'bool', 'style': 'enum:boulder,lead,topRope,trad', 'note': 'text'}, span: true),
    EventType('climbing.ascent', {
      'session': 'ref:climbing.session',
      'grade': 'grade:font',
      'outcome': 'enum:flash,sent,tried',
      'angle': 'enum:slab,vertical,overhang',
      'attempts': 'int',
      'name': 'text',
      'hold': 'text',
      'problem': 'text',
      'gymGrade': 'text',
    }),
    EventType('climbing.place', {'name': 'text', 'outdoor': 'bool', 'address': 'text', 'maps': 'link', 'note': 'text'}),
  ],
  metrics: [
    MetricDef('climbing.sessions_per_week', of: 'climbing.session', agg: 'count', per: 'week', judge: Judge('range', min: 2, max: 4)),
    MetricDef('climbing.level', of: 'climbing.ascent', agg: 'fn:top10_points', window: '60d', levels: 'dreyfus'),
    MetricDef('climbing.max_grade', of: 'climbing.ascent', agg: 'fn:max_grade', window: '60d'),
  ],
);

SourceRef _sourceOf(ClimbSession s, String device) =>
    SourceRef(s.topLoggerId != null || s.source == 'toplogger' ? 'web.toplogger' : (s.source == 'health' || s.sourceId != null ? 'phone.health' : 'phone.manual'), device: device);

/// Sessions as events: one span per session, one event per climb, in order.
List<Event> sessionsToEvents(Iterable<ClimbSession> sessions, {String device = 'phone', DateTime? recordedAt}) {
  final out = <Event>[];
  for (final s in sessions) {
    final j = s.toJson();
    final src = _sourceOf(s, device);
    final at = recordedAt ?? s.end ?? s.start;
    out.add(Event(
      id: 'climb-session-${s.id}',
      module: 'climbing',
      type: 'climbing.session',
      at: s.start,
      end: s.end,
      data: {for (final e in j.entries) if (!const {'id', 'start', 'end', 'climbs'}.contains(e.key)) e.key: e.value},
      source: src,
      recordedAt: at,
    ));
    for (final (i, c) in s.climbs.indexed) {
      out.add(Event(
        id: 'climb-ascent-${s.id}-$i',
        module: 'climbing',
        type: 'climbing.ascent',
        at: s.start,
        data: {'session': s.id, 'index': i, ...c.toJson()},
        source: src,
        recordedAt: at,
      ));
    }
  }
  return out;
}

/// Back from events: sessions with their climbs in their original order.
List<ClimbSession> sessionsFromEvents(Iterable<Event> events) {
  final live = current(events);
  final ascents = <String, List<Map<String, Object?>>>{};
  for (final e in live.where((e) => e.type == 'climbing.ascent')) {
    (ascents['${e.data['session']}'] ??= []).add(e.data);
  }
  return [
    for (final e in live.where((e) => e.type == 'climbing.session'))
      ClimbSession.fromJson({
        ...e.data.cast<String, dynamic>(),
        'id': e.id.substring('climb-session-'.length),
        'start': e.at.toIso8601String(),
        if (e.end != null) 'end': e.end!.toIso8601String(),
        'climbs': [
          for (final a in (ascents[e.id.substring('climb-session-'.length)] ?? const <Map<String, Object?>>[])
            ..sort((x, y) => (x['index'] as int).compareTo(y['index'] as int)))
            {for (final f in a.entries) if (f.key != 'session' && f.key != 'index') f.key: f.value},
        ],
      }),
  ];
}

List<Event> placesToEvents(Iterable<ClimbPlace> places, {String device = 'phone', required DateTime recordedAt}) => [
      for (final p in places)
        Event(id: 'climb-place-${p.name}', module: 'climbing', type: 'climbing.place', at: recordedAt, data: p.toJson(), source: SourceRef('phone.manual', device: device), recordedAt: recordedAt),
    ];

List<ClimbPlace> placesFromEvents(Iterable<Event> events) => [
      for (final e in current(events))
        if (e.type == 'climbing.place') ClimbPlace.fromJson(e.data.cast<String, dynamic>()),
    ];
