import 'dart:convert';
import 'dart:io';

import 'package:climb/shared_places.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/places/near.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/topo.dart';

void main() {
  for (final MapEntry(key: name, value: dir) in kGuides.entries) {
    test('the $name guide: its photos are bundled, every line is a route of it on the photo, grades are on the scale', () {
      final g = jsonDecode(File('$dir/guide.json').readAsStringSync()) as Map<String, dynamic>;
      final routes = {for (final r in (g['routes'] as List).cast<Map>()) r['number'] as String: r};
      expect(routes, isNotEmpty);
      for (final r in routes.values) {
        final scale = r['scale'] == 'uiaa' ? GradeSystem.uiaa : GradeSystem.font;
        expect(gradeOrder(r['grade'] as String, scale), lessThan(1 << 20), reason: '${r['name']}: ${r['grade']}');
      }
      for (final s in (g['sections'] as List).cast<Map>()) {
        expect(File('$dir/${s['photo']}').existsSync(), isTrue, reason: s['photo'] as String);
        if (s['original'] != null) expect(File('$dir/${s['original']}').existsSync(), isTrue);
        for (final l in (s['lines'] as List).cast<Map>()) {
          expect(routes.containsKey(l['route']), isTrue, reason: '${s['name']}: ${l['route']}');
          final line = TopoLine.fromJson({...l.cast<String, dynamic>(), 'problem': l['route']});
          for (final p in line.points) {
            expect(p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1, isTrue, reason: '${s['name']} ${l['route']}');
          }
        }
      }
    });
  }

  test('Vyhliadka: all 25 routes, both sections; the ones on the east wall too', () {
    final g = jsonDecode(File('assets/guides/vyhliadka/guide.json').readAsStringSync()) as Map<String, dynamic>;
    expect((g['routes'] as List).length, 25);
    final east = (g['sections'] as List).last as Map;
    expect([for (final l in east['lines'] as List) l['route']], ['3', '4', '15', '16', '17', '18', '22', '23', '24', '25']);
  });
}
