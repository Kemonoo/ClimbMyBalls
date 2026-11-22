// The places model for Climb (docs/climb/plan.md, step 1).
//
// A place is one node in the hierarchy country → region → area → sector →
// boulder → problem, or a gym wall indoors. Pure Dart, plain data: no app
// state, no network. hibi never reads these; it only sees ticks.

/// Where a place sits in the hierarchy. The order is top to bottom.
enum PlaceKind {
  country,
  region,
  area,
  sector,
  boulder,
  problem,
  gymWall;

  static PlaceKind fromName(String? name) => PlaceKind.values.firstWhere((k) => k.name == name, orElse: () => PlaceKind.area);
}

/// Which grade scale a place uses: Font outdoors (or UIAA, which some local
/// guides use for boulders, e.g. Devín's '9+/10-'), the gym's own scale indoors.
class GradeSystem {
  /// `font`, `uiaa`, or `gym:<scale>` for a gym's own scale.
  final String id;
  const GradeSystem._(this.id);

  static const font = GradeSystem._('font');
  static const uiaa = GradeSystem._('uiaa');

  /// A gym's own scale, e.g. `GradeSystem.gym('Boulder Bar colours')`.
  factory GradeSystem.gym(String scale) => GradeSystem._('gym:${scale.trim()}');

  factory GradeSystem.fromId(String? id) => id == null || id.isEmpty || id == 'font'
      ? font
      : id == 'uiaa'
      ? uiaa
      : GradeSystem._(id.startsWith('gym:') ? id : 'gym:$id');

  bool get isFont => id == 'font';
  bool get isUiaa => id == 'uiaa';

  /// The gym scale's name, or null for Font and UIAA.
  String? get gymScale => id.startsWith('gym:') ? id.substring(4) : null;

  @override
  bool operator ==(Object other) => other is GradeSystem && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}

/// A latitude/longitude pair in degrees (WGS84).
class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  List<double> toJson() => [lat, lng];
  factory LatLng.fromJson(List<dynamic> j) => LatLng((j[0] as num).toDouble(), (j[1] as num).toDouble());

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;
  @override
  int get hashCode => Object.hash(lat, lng);
  @override
  String toString() => '($lat, $lng)';
}

/// Where a place is: a single point, or a polygon outline.
sealed class PlaceGeometry {
  const PlaceGeometry();

  /// A point for the map pin: the point itself, or the polygon's vertex average.
  LatLng get centre;

  Map<String, dynamic> toJson();

  static PlaceGeometry? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return switch (j['type']) {
      'point' => PointGeometry(LatLng.fromJson(j['at'] as List)),
      'polygon' => PolygonGeometry([for (final p in j['ring'] as List) LatLng.fromJson(p as List)]),
      _ => null,
    };
  }
}

class PointGeometry extends PlaceGeometry {
  final LatLng at;
  const PointGeometry(this.at);

  @override
  LatLng get centre => at;

  @override
  Map<String, dynamic> toJson() => {'type': 'point', 'at': at.toJson()};
}

class PolygonGeometry extends PlaceGeometry {
  /// The outline, without repeating the first vertex at the end.
  final List<LatLng> ring;
  PolygonGeometry(List<LatLng> ring) : ring = List.unmodifiable(ring) {
    if (ring.length < 3) throw ArgumentError('A polygon needs at least 3 vertices, got ${ring.length}.');
  }

  @override
  LatLng get centre {
    var lat = 0.0, lng = 0.0;
    for (final p in ring) {
      lat += p.lat;
      lng += p.lng;
    }
    return LatLng(lat / ring.length, lng / ring.length);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'polygon',
    'ring': [for (final p in ring) p.toJson()],
  };
}

/// One node of the hierarchy.
class Place {
  final String id;

  /// The id of the place above this one; null for a top-level place (a country).
  final String? parentId;
  final PlaceKind kind;
  final String name;

  /// Null when nobody has placed it on the map yet.
  final PlaceGeometry? geometry;
  final GradeSystem gradeSystem;
  final bool indoor;

  /// A problem's grade from the setter or first ascender ('6B+'); '' if unknown.
  final String grade;

  /// Where the place came from: 'osm:node/123', 'openbeta:<uuid>', or 'manual'.
  final String source;

  /// The data licence of [source]: 'ODbL' (OSM and our own), 'CC0' (OpenBeta).
  final String licence;

  /// Optional extras, all of them free to leave out. For a problem:
  /// `sit` (sit start, bool), `note` (where it goes), `uncertain` (the grade
  /// has a '?', bool), `standOf` (the id of the sit-start problem this is the
  /// stand-up version of).
  final Map<String, Object?> details;

  /// A route only its maker sees until they publish it (#462).
  final bool draft;

  /// The check mark (#467): a place editor checked it, or 3 people topped
  /// it. Places that never had the question (bundled, OSM) count as verified.
  final bool verified;

  bool get sitStart => details['sit'] == true;
  String get note => details['note'] as String? ?? '';
  bool get gradeUncertain => details['uncertain'] == true;

  /// For sit starts: 'low' or 'high' when the guide says so, else ''.
  String get sitHeight => sitStart ? (details['sitHeight'] as String? ?? '') : '';

  /// The route's number in its guide ('7', '24b'), or '' when it has none.
  String get number => switch (details['number']) {
    final num n => '${n.toInt()}',
    final String s => s,
    _ => '',
  };

  /// A rope route (top rope or lead), graded in UIAA; boulders use Font.
  bool get isRope => gradeSystem.isUiaa;

  const Place({
    required this.id,
    required this.kind,
    required this.name,
    this.parentId,
    this.geometry,
    this.gradeSystem = GradeSystem.font,
    this.indoor = false,
    this.grade = '',
    this.source = 'manual',
    this.licence = 'ODbL',
    this.details = const {},
    this.draft = false,
    this.verified = true,
  });

  Place copyWith({
    String? parentId,
    String? name,
    PlaceGeometry? geometry,
    GradeSystem? gradeSystem,
    bool? indoor,
    String? grade,
    Map<String, Object?>? details,
    bool? draft,
    bool? verified,
  }) => Place(
    id: id,
    parentId: parentId ?? this.parentId,
    kind: kind,
    name: name ?? this.name,
    geometry: geometry ?? this.geometry,
    gradeSystem: gradeSystem ?? this.gradeSystem,
    indoor: indoor ?? this.indoor,
    grade: grade ?? this.grade,
    source: source,
    licence: licence,
    details: details ?? this.details,
    draft: draft ?? this.draft,
    verified: verified ?? this.verified,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (parentId != null) 'parent': parentId,
    'kind': kind.name,
    'name': name,
    if (geometry != null) 'geometry': geometry!.toJson(),
    'grades': gradeSystem.id,
    if (indoor) 'indoor': true,
    if (grade.isNotEmpty) 'grade': grade,
    'source': source,
    'licence': licence,
    if (details.isNotEmpty) 'details': details,
    if (draft) 'draft': true,
    if (!verified) 'verified': false,
  };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    id: j['id'] as String,
    parentId: j['parent'] as String?,
    kind: PlaceKind.fromName(j['kind'] as String?),
    name: j['name'] as String? ?? '',
    geometry: PlaceGeometry.fromJson((j['geometry'] as Map?)?.cast<String, dynamic>()),
    gradeSystem: GradeSystem.fromId(j['grades'] as String?),
    indoor: j['indoor'] as bool? ?? false,
    grade: j['grade'] as String? ?? '',
    source: j['source'] as String? ?? 'manual',
    licence: j['licence'] as String? ?? 'ODbL',
    details: (j['details'] as Map?)?.cast<String, Object?>() ?? const {},
    draft: j['draft'] == true,
    verified: j['verified'] != false,
  );

  @override
  String toString() => 'Place($id, ${kind.name}, $name)';
}
