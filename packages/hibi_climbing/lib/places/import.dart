// Turning open data into places (docs/climb/plan.md, step 5).
//
// Only two sources: OpenStreetMap (ODbL) and OpenBeta (CC0). Every place keeps
// its source and licence. Pure functions over the JSON each service returns;
// the network calls live in tool/import_places.dart, never in the app.
import '../climbing.dart';
import 'place.dart';

/// The Overpass query for climbing in one country (ISO 3166-1 code, e.g. SK).
/// `out geom` gives closed ways their outline; relations list their members.
String overpassQuery(String iso) => '''
[out:json][timeout:120];
area["ISO3166-1"="${iso.toUpperCase()}"][admin_level=2]->.c;
(
  nwr["sport"="climbing"](area.c);
  nwr["climbing"](area.c);
);
out tags geom;
''';

/// OSM elements (the `elements` of an Overpass answer) as places under
/// [countryId]. Mapping: climbing=area → area, crag → sector, boulder →
/// boulder, route_bottom / route → problem. `climbing:grade:font` is the
/// grade; other scales are left out until a problem gets Font votes.
///
/// Parents come from site relations first (a relation tagged climbing=area or
/// crag lists its members), then from the smallest OSM area or crag outline
/// the place sits inside. Anything left goes straight under the country.
/// A gym (climbing=gym, or sport=climbing on a sports centre or building)
/// becomes an indoor gym wall with its own scale.
List<Place> placesFromOverpass(List<dynamic> elements, {required String countryId}) {
  final out = <String, Place>{};
  final parentOf = <String, String>{};
  final outlines = <String, PolygonGeometry>{};
  for (final e in elements.cast<Map<String, dynamic>>()) {
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final type = e['type'] as String;
    final id = 'osm-$type-${e['id']}';
    final kind = _osmKind(tags);
    if (kind == null) continue;
    final name = (tags['name'] ?? tags['name:sk'] ?? tags['name:cs'] ?? tags['name:en'] ?? '') as String;
    if (name.trim().isEmpty && kind != PlaceKind.problem) continue;
    final geometry = _osmGeometry(e);
    if (geometry is PolygonGeometry && (kind == PlaceKind.area || kind == PlaceKind.sector)) outlines[id] = geometry;
    final indoor = kind == PlaceKind.gymWall;
    out[id] = Place(
      id: id,
      kind: kind,
      name: name.trim().isEmpty ? 'Unnamed' : name.trim(),
      geometry: geometry,
      indoor: indoor,
      gradeSystem: indoor ? GradeSystem.gym('own') : GradeSystem.font,
      grade: _osmGrade(tags),
      source: 'osm:$type/${e['id']}',
      licence: 'ODbL',
    );
    if (type == 'relation') {
      for (final m in (e['members'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        parentOf.putIfAbsent('osm-${m['type']}-${m['ref']}', () => id);
      }
    }
  }
  String? containing(Place p) {
    final at = p.geometry?.centre;
    if (at == null) return null;
    String? best;
    var bestRank = -1;
    for (final MapEntry(key: id, value: ring) in outlines.entries) {
      if (id == p.id) continue;
      final container = out[id]!;
      if (container.kind.index >= p.kind.index) continue; // only places above it
      if (!pointInPolygon(at, ring.ring)) continue;
      if (container.kind.index > bestRank) {
        best = id;
        bestRank = container.kind.index;
      }
    }
    return best;
  }

  return [
    for (final p in out.values)
      Place(
        id: p.id,
        parentId: _validParent(parentOf[p.id], p, out) ?? containing(p) ?? countryId,
        kind: p.kind,
        name: p.name,
        geometry: p.geometry,
        gradeSystem: p.gradeSystem,
        indoor: p.indoor,
        grade: p.grade,
        source: p.source,
        licence: p.licence,
      ),
  ];
}

String? _validParent(String? parentId, Place p, Map<String, Place> all) {
  final parent = parentId == null ? null : all[parentId];
  return parent != null && parent.kind.index < p.kind.index ? parentId : null;
}

PlaceKind? _osmKind(Map<String, dynamic> t) {
  if (t['climbing'] == 'gym' || (t['sport'] == 'climbing' && (t['leisure'] == 'sports_centre' || t['building'] != null))) return PlaceKind.gymWall;
  return switch (t['climbing']) {
    'area' => PlaceKind.area,
    'crag' => PlaceKind.sector,
    'boulder' => PlaceKind.boulder,
    'route_bottom' || 'route' => PlaceKind.problem,
    _ => t['sport'] == 'climbing' && t['natural'] == 'stone' ? PlaceKind.boulder : null,
  };
}

String _osmGrade(Map<String, dynamic> t) {
  final font = t['climbing:grade:font'] as String?;
  if (font != null) {
    final g = normaliseGrade(font);
    if (gradeIndex(g) != null) return g;
  }
  return '';
}

PlaceGeometry? _osmGeometry(Map<String, dynamic> e) {
  if (e['lat'] != null) return PointGeometry(LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()));
  final g = e['geometry'] as List?;
  if (g != null && g.length >= 3) {
    final pts = [for (final p in g.cast<Map<String, dynamic>>()) LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())];
    if (pts.first == pts.last) pts.removeLast();
    if (pts.length >= 3) return PolygonGeometry(pts);
  }
  final c = e['center'] as Map?;
  if (c != null) return PointGeometry(LatLng((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()));
  final b = e['bounds'] as Map?;
  if (b != null) {
    return PointGeometry(LatLng(((b['minlat'] as num) + (b['maxlat'] as num)) / 2, ((b['minlon'] as num) + (b['maxlon'] as num)) / 2));
  }
  return null;
}

/// Ray casting; [ring] without the closing vertex.
bool pointInPolygon(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.lat > p.lat) != (b.lat > p.lat) && p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) inside = !inside;
  }
  return inside;
}

/// The OpenBeta GraphQL query for one area and everything under it, to
/// [depth] levels. Send it to https://api.openbeta.io with `{"uuid": ...}`.
String openBetaQuery({int depth = 6}) {
  String level(int d) => d == 0
      ? ''
      : 'children { uuid areaName metadata { lat lng leaf isBoulder } '
          'climbs { uuid name type { bouldering } grades { font vscale } } ${level(d - 1)} }';
  return 'query Area(\$uuid: ID) { area(uuid: \$uuid) { uuid areaName metadata { lat lng leaf isBoulder } '
      'climbs { uuid name type { bouldering } grades { font vscale } } ${level(depth)} } }';
}

/// An OpenBeta area tree (the `data.area` of [openBetaQuery]) as places. The
/// root becomes [rootKind] (a country by default) with [parentId] above it.
/// Depth gives the kind (country, region, then area), a boulder area becomes a
/// boulder, and an area deeper than area level becomes a sector. Only
/// bouldering climbs are kept; they become problems with their Font grade.
List<Place> placesFromOpenBeta(Map<String, dynamic> area, {String? parentId, PlaceKind rootKind = PlaceKind.country}) {
  final out = <Place>[];
  void walk(Map<String, dynamic> a, String? parent, PlaceKind kind) {
    final meta = (a['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isBoulder = meta['isBoulder'] == true;
    final k = isBoulder && kind.index >= PlaceKind.area.index ? PlaceKind.boulder : kind;
    final id = 'ob-${a['uuid']}';
    final lat = meta['lat'] as num?, lng = meta['lng'] as num?;
    out.add(Place(
      id: id,
      parentId: parent,
      kind: k,
      name: ((a['areaName'] as String?) ?? '').trim(),
      geometry: lat != null && lng != null && (lat != 0 || lng != 0) ? PointGeometry(LatLng(lat.toDouble(), lng.toDouble())) : null,
      source: 'openbeta:${a['uuid']}',
      licence: 'CC0',
    ));
    for (final c in (a['climbs'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      if ((c['type'] as Map?)?['bouldering'] != true) continue;
      final font = ((c['grades'] as Map?)?['font'] as String?) ?? '';
      final g = normaliseGrade(font);
      out.add(Place(
        id: 'ob-${c['uuid']}',
        parentId: id,
        kind: PlaceKind.problem,
        name: ((c['name'] as String?) ?? '').trim(),
        grade: gradeIndex(g) != null ? g : '',
        source: 'openbeta:${c['uuid']}',
        licence: 'CC0',
      ));
    }
    final next = switch (k) {
      PlaceKind.country => PlaceKind.region,
      PlaceKind.region => PlaceKind.area,
      _ => PlaceKind.sector,
    };
    for (final c in (a['children'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      walk(c, id, next);
    }
  }

  walk(area, parentId, rootKind);
  return out;
}
