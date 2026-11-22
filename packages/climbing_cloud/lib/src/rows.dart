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
      draft: r['draft'] == true,
      verified: r['verified'] != false,
      inGuide: r['in_guide'] != false,
      proven: r['proven'] == true,
    ),
    createdBy: r['created_by'] as String?,
    updatedAt: DateTime.parse(r['updated_at'] as String),
    createdAt: r['created_at'] == null ? null : DateTime.parse(r['created_at'] as String),
    deleted: r['deleted'] as bool? ?? false,
  );

  /// For the phone's own copy (the same shape as a row).
  Map<String, dynamic> toRow() => {
    ...placeToRow(place),
    'verified': place.verified,
    'in_guide': place.inGuide,
    'proven': place.proven,
    'created_by': createdBy,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

/// The columns the app writes; created_by, the times and deleted are set by
/// the database. Not `verified`: only [ClimbCloud.publishPlace] and
/// [ClimbCloud.verifyPlace] change it (008_route_status.sql guards it).
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
  'draft': p.draft,
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

  /// [local]: changes made on the phone that wait to be sent; they don't move
  /// [since], so the next fetch still sees everyone's changes.
  void merge(Iterable<CloudPlace> rows, {bool local = false}) {
    for (final r in rows) {
      if (r.deleted) {
        _byId.remove(r.place.id);
      } else {
        _byId[r.place.id] = r;
      }
      if (!local && (since == null || r.updatedAt.isAfter(since!))) since = r.updatedAt;
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

  Map<String, dynamic> toRow() => {
    ...topo.toRow(),
    'in_guide': topo.inGuide,
    'created_by': topo.createdBy,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

/// One route's line on a section photo, as its own row (#516): anyone can
/// draw their route on anyone's photo, and the line keeps its author.
class CloudLine {
  const CloudLine({required this.topoId, required this.line, this.ord = 0, required this.updatedAt, this.deleted = false});
  final String topoId;
  final TopoLine line;

  /// Its place among the photo's lines, drawn in this order.
  final int ord;
  final DateTime updatedAt;
  final bool deleted;

  factory CloudLine.fromRow(Map<String, dynamic> r) => CloudLine(
    topoId: r['topo_id'] as String,
    ord: (r['ord'] as num?)?.toInt() ?? 0,
    line: TopoLine.fromJson({...r, 'problem': r['problem_id']}).copyWith(
      id: r['id'] as String,
      createdBy: r['created_by'] as String?,
      inGuide: r['in_guide'] != false,
    ),
    updatedAt: DateTime.parse(r['updated_at'] as String),
    deleted: r['deleted'] as bool? ?? false,
  );

  /// The columns the app writes; in_guide is the database's (010_guides.sql).
  Map<String, dynamic> toRow() {
    final j = line.toJson()..remove('problem');
    return {
      'id': line.id,
      'topo_id': topoId,
      'problem_id': line.problemId,
      'ord': ord,
      'points': j['points'],
      'start': j['start'],
      'end': j['end'],
      'color': j['color'],
      'via': line.via,
      'alone': line.alone,
    };
  }

  /// For the phone's own copy.
  Map<String, dynamic> toCacheRow() => {
    ...toRow(),
    'in_guide': line.inGuide,
    'created_by': line.createdBy,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

/// The phone's copy of the shared lines, like [TopoCache].
class LineCache {
  LineCache([Iterable<CloudLine> rows = const []]) {
    merge(rows);
  }

  final _byId = <String, CloudLine>{};
  DateTime? since;

  /// Whether lines have come from the database at least once; until then
  /// (or before 010_guides.sql) sections keep the lines stored in them.
  bool get synced => since != null;

  /// The lines on [topoId], in their drawing order.
  List<TopoLine> of(String topoId) {
    final rows = [
      for (final c in _byId.values)
        if (c.topoId == topoId) c,
    ]..sort((a, b) => a.ord != b.ord ? a.ord.compareTo(b.ord) : a.updatedAt.compareTo(b.updatedAt));
    return [for (final c in rows) c.line];
  }

  CloudLine? byId(String id) => _byId[id];

  void merge(Iterable<CloudLine> rows, {bool local = false}) {
    for (final r in rows) {
      final id = r.line.id;
      if (id == null) continue;
      if (r.deleted) {
        _byId.remove(id);
      } else {
        _byId[id] = r;
      }
      if (!local && (since == null || r.updatedAt.isAfter(since!))) since = r.updatedAt;
    }
  }

  Map<String, dynamic> toJson() => {
    'since': since?.toUtc().toIso8601String(),
    'lines': [for (final c in _byId.values) c.toCacheRow()],
  };

  factory LineCache.fromJson(Map<String, dynamic> j) {
    final c = LineCache([for (final r in (j['lines'] as List? ?? const []).cast<Map>()) CloudLine.fromRow(r.cast<String, dynamic>())]);
    final s = j['since'] as String?;
    if (s != null) c.since = DateTime.parse(s);
    return c;
  }
}

/// A guide's name and credit (#500): one official guide per place for now.
class CloudGuide {
  const CloudGuide({required this.id, required this.placeId, required this.name, this.credit = '', this.official = true, this.createdBy});
  final String id, placeId, name, credit;
  final bool official;
  final String? createdBy;

  factory CloudGuide.fromRow(Map<String, dynamic> r) => CloudGuide(
    id: r['id'] as String,
    placeId: r['place_id'] as String,
    name: r['name'] as String? ?? '',
    credit: r['credit'] as String? ?? '',
    official: r['official'] != false,
    createdBy: r['created_by'] as String?,
  );

  Map<String, dynamic> toRow() => {'id': id, 'place_id': placeId, 'name': name, 'credit': credit, 'official': official};
}

/// What a star or a favourite is on (#500): a place (area, boulder, route),
/// a section photo, or a guide.
enum StarKind { place, topo, guide }

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

  Topo? byId(String id) => _byId[id]?.topo;

  void merge(Iterable<CloudTopo> rows, {bool local = false}) {
    for (final r in rows) {
      if (r.deleted) {
        _byId.remove(r.topo.id);
      } else {
        _byId[r.topo.id] = r;
      }
      if (!local && (since == null || r.updatedAt.isAfter(since!))) since = r.updatedAt;
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

  Map<String, dynamic> toRow() => {
    'id': id,
    'user_id': userId,
    'problem_id': problemId,
    'day': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'outcome': outcome,
    'note': note,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };

  CloudTick copyWith({DateTime? day}) => CloudTick(id: id, userId: userId, problemId: problemId, day: day ?? this.day, outcome: outcome, note: note, createdAt: createdAt);
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

  Map<String, dynamic> toRow() => {'user_id': userId, 'problem_id': problemId, 'grade': grade, 'stars': stars, 'tags': tags, 'project': project};
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

  Map<String, dynamic> toRow() => {'id': id, 'user_id': userId, 'problem_id': problemId, 'body': body, 'created_at': createdAt.toUtc().toIso8601String()};
}
