part of '../climbing_cloud.dart';

/// A place as stored in the shared database, with who made it and when.
class CloudPlace {
  const CloudPlace({required this.place, required this.createdBy, required this.updatedAt, this.createdAt, this.deleted = false});

  final Place place;
  final String? createdBy;
  final DateTime updatedAt;
  final DateTime? createdAt;
  final bool deleted;

  factory CloudPlace.fromRow(Map<String, dynamic> r) => CloudPlace(
    place: Place(
      id: r['id'] as String,
      parentId: r['parent_id'] as String?,
      kind: PlaceKind.fromName(r['kind'] as String?),
      name: r['name'] as String? ?? '',
      geometry: PlaceGeometry.fromJson((r['geometry'] as Map?)?.cast<String, dynamic>()),
      gradeSystem: GradeSystem.fromId(r['grade_system'] as String?),
      indoor: r['indoor'] as bool? ?? false,
      grade: r['grade'] as String? ?? '',
      source: r['source'] as String? ?? 'manual',
      licence: r['licence'] as String? ?? 'ODbL',
      details: (r['details'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    createdBy: r['created_by'] as String?,
    updatedAt: DateTime.parse(r['updated_at'] as String),
    createdAt: r['created_at'] == null ? null : DateTime.parse(r['created_at'] as String),
    deleted: r['deleted'] as bool? ?? false,
  );

  /// For the phone's own copy (the same shape as a row).
  Map<String, dynamic> toRow() => {
    ...placeToRow(place),
    'created_by': createdBy,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

/// The columns the app writes; created_by, the times and deleted are set by
/// the database.
Map<String, dynamic> placeToRow(Place p) => {
  'id': p.id,
  'parent_id': p.parentId,
  'kind': p.kind.name,
  'name': p.name,
  'geometry': p.geometry?.toJson(),
  'grade_system': p.gradeSystem.id,
  'indoor': p.indoor,
  'grade': p.grade,
  'source': p.source,
  'licence': p.licence,
  'details': p.details,
};

/// The phone's copy of the shared places: merges what's new and drops what
/// was deleted. [since] is the newest change seen, for the next fetch.
class PlaceCache {
  PlaceCache([Iterable<CloudPlace> rows = const []]) {
    merge(rows);
  }

  final _byId = <String, CloudPlace>{};
  DateTime? since;

  List<Place> get places => [for (final c in _byId.values) c.place];

  void merge(Iterable<CloudPlace> rows) {
    for (final r in rows) {
      if (r.deleted) {
        _byId.remove(r.place.id);
      } else {
        _byId[r.place.id] = r;
      }
      if (since == null || r.updatedAt.isAfter(since!)) since = r.updatedAt;
    }
  }

  String? createdBy(String id) => _byId[id]?.createdBy;
  DateTime? createdAt(String id) => _byId[id]?.createdAt;

  Map<String, dynamic> toJson() => {
    'since': since?.toUtc().toIso8601String(),
    'places': [for (final c in _byId.values) c.toRow()],
  };

  factory PlaceCache.fromJson(Map<String, dynamic> j) {
    final c = PlaceCache([for (final r in (j['places'] as List? ?? const []).cast<Map>()) CloudPlace.fromRow(r.cast<String, dynamic>())]);
    final s = j['since'] as String?;
    if (s != null) c.since = DateTime.parse(s);
    return c;
  }
}

/// A topo as stored in the shared database.
class CloudTopo {
  const CloudTopo({required this.topo, required this.updatedAt, this.deleted = false});
  final Topo topo;
  final DateTime updatedAt;
  final bool deleted;

  factory CloudTopo.fromRow(Map<String, dynamic> r) =>
      CloudTopo(topo: Topo.fromRow(r), updatedAt: DateTime.parse(r['updated_at'] as String), deleted: r['deleted'] as bool? ?? false);

  Map<String, dynamic> toRow() => {...topo.toRow(), 'created_by': topo.createdBy, 'updated_at': updatedAt.toUtc().toIso8601String(), 'deleted': deleted};
}

/// The phone's copy of the shared topos, like [PlaceCache].
class TopoCache {
  TopoCache([Iterable<CloudTopo> rows = const []]) {
    merge(rows);
  }

  final _byId = <String, CloudTopo>{};
  DateTime? since;

  /// The topos of [placeId], newest first.
  List<Topo> of(String placeId) {
    final rows = [
      for (final c in _byId.values)
        if (c.topo.placeId == placeId) c,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [for (final c in rows) c.topo];
  }

  int get length => _byId.length;

  void merge(Iterable<CloudTopo> rows) {
    for (final r in rows) {
      if (r.deleted) {
        _byId.remove(r.topo.id);
      } else {
        _byId[r.topo.id] = r;
      }
      if (since == null || r.updatedAt.isAfter(since!)) since = r.updatedAt;
    }
  }

  Map<String, dynamic> toJson() => {
    'since': since?.toUtc().toIso8601String(),
    'topos': [for (final c in _byId.values) c.toRow()],
  };

  factory TopoCache.fromJson(Map<String, dynamic> j) {
    final c = TopoCache([for (final r in (j['topos'] as List? ?? const []).cast<Map>()) CloudTopo.fromRow(r.cast<String, dynamic>())]);
    final s = j['since'] as String?;
    if (s != null) c.since = DateTime.parse(s);
    return c;
  }
}

/// One person's ascent (or try) of a problem.
class CloudTick {
  const CloudTick({required this.id, required this.userId, required this.problemId, required this.day, required this.outcome, this.note = '', this.createdAt});
  final String id, userId, problemId;
  final DateTime day;

  /// 'flash', 'sent' or 'tried'.
  final String outcome;
    final String note;
  final DateTime? createdAt;

  factory CloudTick.fromRow(Map<String, dynamic> r) => CloudTick(
    id: r['id'] as String,
    userId: r['user_id'] as String,
    problemId: r['problem_id'] as String,
    day: DateTime.parse(r['day'] as String),
    outcome: r['outcome'] as String,
    note: r['note'] as String? ?? '',
    createdAt: r['created_at'] == null ? null : DateTime.parse(r['created_at'] as String),
  );
}

/// What one person thinks of a route: the grade it felt like ('' = no vote)
/// and 1-5 stars (0 = none).
class CloudOpinion {
  const CloudOpinion({required this.userId, required this.problemId, this.grade = '', this.stars = 0, this.tags = const [], this.project = false});
  final String userId, problemId, grade;
  final int stars;

  /// What it's like ('crimps', 'slab'), from [routeTags].
  final List<String> tags;

  /// Marked as a goal of yours.
  final bool project;

  factory CloudOpinion.fromRow(Map<String, dynamic> r) => CloudOpinion(
    userId: r['user_id'] as String,
    problemId: r['problem_id'] as String,
    grade: r['grade'] as String? ?? '',
    stars: (r['stars'] as num?)?.toInt() ?? 0,
    tags: [for (final t in (r['tags'] as List? ?? const [])) t as String],
    project: r['project'] == true,
  );
}

/// One comment under a route.
class CloudComment {
  const CloudComment({required this.id, required this.userId, required this.problemId, required this.body, required this.createdAt});
  final String id, userId, problemId, body;
  final DateTime createdAt;

  factory CloudComment.fromRow(Map<String, dynamic> r) => CloudComment(
    id: r['id'] as String,
    userId: r['user_id'] as String,
    problemId: r['problem_id'] as String,
    body: r['body'] as String? ?? '',
    createdAt: DateTime.parse(r['created_at'] as String),
  );
}
