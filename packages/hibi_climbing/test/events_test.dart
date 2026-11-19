import 'dart:convert';

import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/events.dart';
import 'package:hibi_protocol/hibi_protocol.dart';
import 'package:test/test.dart';

// Protocol v0.1, section 7: climbing history survives the move to events.
void main() {
  final sessions = [
    ClimbSession.fromJson({
      'id': 's1',
      'start': '2026-11-10T18:00:00.000',
      'end': '2026-11-10T20:00:00.000',
      'place': 'Boulder Bar',
      'source': 'toplogger',
      'topLoggerId': 'tl-42',
      'climbs': [
        {'grade': '6B', 'outcome': 'flash', 'angle': 'overhang', 'attempts': 1},
        {'grade': '6C', 'outcome': 'sent', 'angle': 'vertical', 'attempts': 4, 'name': 'Blue crimp'},
        {'grade': '7A', 'outcome': 'tried', 'angle': 'slab'},
      ],
    }),
    ClimbSession.fromJson({
      'id': 's2',
      'start': '2026-11-12T10:00:00.000',
      'place': 'Sloup',
      'outdoor': true,
      'source': 'manual',
      'note': 'cold',
      'style': 'lead',
      'climbs': [
        {'grade': '6A', 'outcome': 'sent', 'angle': 'vertical'},
      ],
    }),
  ];

  test('sessions and climbs go to events and come back the same', () {
    final events = sessionsToEvents(sessions);
    expect(events.where((e) => e.type == 'climbing.session').length, 2);
    expect(events.where((e) => e.type == 'climbing.ascent').length, 4);
    expect(events.first.source.id, 'web.toplogger');
    // Through JSON too, as they'd be stored or shared.
    final stored = [for (final e in events) Event.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map)];
    final back = sessionsFromEvents(stored);
    expect([for (final s in back) s.toJson()], [for (final s in sessions) s.toJson()]);
  });

  test('a corrected ascent replaces the old one', () {
    final events = sessionsToEvents(sessions);
    final old = events.firstWhere((e) => e.id == 'climb-ascent-s1-1');
    final fix = Event(
      id: 'fix1',
      module: 'climbing',
      type: 'climbing.ascent',
      at: old.at,
      data: {...old.data, 'grade': '6C+'},
      source: old.source,
      recordedAt: DateTime(2026, 11, 11),
      replaces: old.id,
    );
    final back = sessionsFromEvents([...events, fix]);
    expect(back.first.climbs[1].grade, '6C+');
  });

  test('places too; the manifest is a skill module and survives JSON', () {
    final places = [ClimbPlace(name: 'Sloup', outdoor: true, address: 'Moravský kras')];
    expect([for (final p in placesFromEvents(placesToEvents(places, recordedAt: DateTime(2026, 11, 12)))) p.toJson()], [for (final p in places) p.toJson()]);
    expect(kClimbingManifest.kind, ModuleKind.skill);
    expect(ModuleManifest.fromJson(kClimbingManifest.toJson()).toJson(), kClimbingManifest.toJson());
  });
}
