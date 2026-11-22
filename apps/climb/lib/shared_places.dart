// The places on the map: the OpenStreetMap import bundled with the app, plus
// the shared places and topos from the database (docs/climb/plan.md step 7),
// kept on the phone so the map works without signal and only new changes are
// fetched.
import 'dart:async';
import 'dart:convert';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/store.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:climbing/places/topo.dart';
import 'package:climbing_cloud/climbing_cloud.dart';
import 'package:climbing_map/climbing_map.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'outbox.dart';

import 'storage/photo_box.dart';
import 'storage/text_box.dart';

class SharedPlaces extends ChangeNotifier {
  SharedPlaces({
    required this.bundled,
    this.cloud,
    this.cacheFile,
    this.store,
    this.photos,
    PlaceCache? cache,
    TopoCache? topos,
    LineCache? lines,
    Set<String>? offline,
    this.fetch = _download,
    Outbox? outbox,
    Future<bool> Function()? onWifi,
  }) : cache = cache ?? PlaceCache(),
       topos = topos ?? TopoCache(),
       lines = lines ?? LineCache(),
       offline = offline ?? {},
       outbox = outbox ?? Outbox(),
       onWifi = onWifi ?? (() async => true);

  final List<Place> bundled;

  /// Your sessions (the Climbs tab): ascents logged on routes land here.
  final ClimbingStore? store;
  final ClimbCloud? cloud;
  final TextBox? cacheFile;
  final PlaceCache cache;
  final TopoCache topos;

  /// Route lines as their own rows (#516); see [withLines].
  final LineCache lines;

  /// [t] with its lines from their own rows, once those have been fetched;
  /// before that (or before 010_guides.sql), the lines stored in it.
  Topo withLines(Topo t) => lines.synced ? t.copyWith(lines: lines.of(t.id)) : t;

  /// Section photos kept on the device (#459): every photo you open, and all
  /// of a place you saved offline. Null where photos can't be kept (web).
  final PhotoBox? photos;

  /// The places saved for use without signal, by id.
  final Set<String> offline;

  /// Changes waiting to reach the server, and the server's last answers (#460).
  final Outbox outbox;

  /// Whether the phone is on Wi-Fi now (for "upload only on Wi-Fi").
  final Future<bool> Function() onWifi;

  /// Downloads one photo (tests pass a fake).
  final Future<Uint8List> Function(Uri url) fetch;

  static Future<Uint8List> _download(Uri url) async {
    final r = await http.get(url);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return r.bodyBytes;
  }

  /// Why the last refresh failed, shown on the map; null when fine.
  String? problem;

  /// Whether this build carries the Devín guide (the public repository
  /// leaves the guide's photos out).
  var hasGuide = false;

  /// People's names by user id, for "added by" and ascents.
  final names = <String, String>{};
  PlaceTree? _tree;

  PlaceTree get tree => _tree ??= PlaceTree([...bundled, ...cache.places]);

  /// What an edit right can cover, for the Friends tab: areas and gyms,
  /// sectors and walls, boulders.
  List<ScopePlace> get scopePlaces => [
    for (final p in [...bundled, ...cache.places])
      if (const {PlaceKind.area, PlaceKind.sector, PlaceKind.boulder, PlaceKind.gymWall}.contains(p.kind))
        (id: p.id, label: '${p.name} · ${kindLabel(p.kind)}', parentId: p.parentId),
  ];

  /// Loads the bundled places and the phone's copy of the shared ones.
  static Future<SharedPlaces> load({ClimbCloud? cloud, TextBox? cacheFile, ClimbingStore? store, PhotoBox? photos, Outbox? outbox, Future<bool> Function()? onWifi}) async {
    final raw = jsonDecode(await rootBundle.loadString('assets/places/sk.json', cache: false)) as List;
    var guide = false;
    try {
      guide = (await rootBundle.load('assets/guides/devin/guide.json')).lengthInBytes > 0;
    } catch (_) {}
    PlaceCache? cache;
    TopoCache? topos;
    LineCache? lines;
    var offline = <String>{};
    Map<String, dynamic>? saved;
    try {
      final text = cacheFile?.read();
      if (text != null) {
        final j = saved = jsonDecode(text) as Map<String, dynamic>;
        cache = PlaceCache.fromJson((j['placeCache'] as Map).cast<String, dynamic>());
        topos = TopoCache.fromJson((j['topoCache'] as Map).cast<String, dynamic>());
        if (j['lineCache'] case final Map l) lines = LineCache.fromJson(l.cast<String, dynamic>());
        offline = {...((j['offline'] as List?) ?? const []).cast<String>()};
      }
    } catch (_) {
      cache = null; // a broken copy is fetched again in full
      topos = null;
    }
    return SharedPlaces(
      bundled: [for (final j in raw.cast<Map<String, dynamic>>()) Place.fromJson(j)],
      cloud: cloud,
      cacheFile: cacheFile,
      store: store,
      photos: photos,
      cache: cache,
      topos: topos,
      lines: lines,
      offline: offline,
      outbox: outbox,
      onWifi: onWifi,
    )
      ..hasGuide = guide
      .._restore(saved);
  }

  // ---- stars, favourites and guides (#518), kept on the phone ----

  /// Your stars, as 'kind:id'.
  final myStars = <String>{};

  /// Your favourites, as 'kind:id', newest first.
  final favourites = <String>[];

  /// Everyone's stars on what you looked at, by 'kind:id'.
  final starCounts = <String, int>{};

  /// Guide names and credits (010_guides.sql).
  var guides = <CloudGuide>[];

  void _restore(Map<String, dynamic>? j) {
    if (j == null) return;
    try {
      myStars.addAll(((j['stars'] as List?) ?? const []).cast<String>());
      favourites.addAll(((j['favourites'] as List?) ?? const []).cast<String>());
      starCounts.addAll(((j['starCounts'] as Map?) ?? const {}).cast<String, int>());
      guides = [for (final g in ((j['guides'] as List?) ?? const []).cast<Map>()) CloudGuide.fromRow({...g.cast<String, dynamic>(), 'id': g['id']})];
    } catch (_) {} // fetched again
  }

  /// Star counts of [ids] from the server, with your waiting changes on top;
  /// the last known ones without signal.
  Future<void> loadStars(String kind, List<String> ids) async {
    final c = cloud;
    if (c == null || c.user == null || ids.isEmpty) return;
    try {
      final got = await c.starCounts(StarKind.values.byName(kind), ids);
      for (final id in ids) {
        starCounts['$kind:$id'] = got[id] ?? 0;
      }
      for (final op in outbox.ops.where((o) => o.kind == 'star' && o.data['kind'] == kind && ids.contains(o.data['id']))) {
        final k = '$kind:${op.data['id']}';
        starCounts[k] = (starCounts[k] ?? 0) + (op.data['on'] == true ? 1 : -1);
      }
      _save();
    } catch (_) {}
  }

  final _ascents = <String, ({int tops, int flashes})>{};

  /// Tops and flashes per route; the last answer without signal.
  Future<Map<String, ({int tops, int flashes})>> ascentCounts(List<String> ids) async {
    try {
      _ascents.addAll(await cloud!.ascentCounts(ids));
    } catch (_) {}
    return {for (final id in ids) id: ?_ascents[id]};
  }

  void _applyMark(String kind, Map<String, dynamic> d) {
    final k = '${d['kind']}:${d['id']}', on = d['on'] == true;
    if (kind == 'star') {
      if (on ? myStars.add(k) : myStars.remove(k)) starCounts[k] = ((starCounts[k] ?? 0) + (on ? 1 : -1)).clamp(0, 1 << 30);
    } else {
      favourites.remove(k);
      if (on) favourites.insert(0, k);
    }
  }

  /// Fetches what changed since last time, when signed in.
  Future<void> refresh() async {
    final c = cloud;
    if (c == null || c.user == null) return;
    try {
      if (c.me == null) await c.myProfile();
      if (c.approved) await send();
      if (!c.approved) {
        problem = 'Your account is waiting to be let in (see the Friends tab).';
        notifyListeners();
        return;
      }
      cache.merge(await c.placesSince(cache.since));
      topos.merge(await c.toposSince(topos.since));
      try {
        lines.merge(await c.linesSince(lines.since));
      } catch (_) {} // before 010_guides.sql: sections keep their own lines
      try {
        names
          ..clear()
          ..addAll({for (final p in await c.allProfiles()) p.id: p.name});
      } catch (_) {} // names are a nicety
      await c.allGrants();
      await syncTicks();
      try {
        final stars = await c.myStars(), favs = await c.myFavourites();
        myStars
          ..clear()
          ..addAll(stars);
        favourites
          ..retainWhere(favs.contains)
          ..addAll(favs.where((f) => !favourites.contains(f)));
        guides = await c.guides();
        // what still waits to be sent stays as you left it
        for (final op in outbox.ops.where((o) => o.kind == 'fav' || (o.kind == 'star'))) {
          final k = '${op.data['kind']}:${op.data['id']}';
          if (op.kind == 'star') {
            op.data['on'] == true ? myStars.add(k) : myStars.remove(k);
          } else {
            favourites.remove(k);
            if (op.data['on'] == true) favourites.insert(0, k);
          }
        }
      } catch (_) {} // before 010_guides.sql
      problem = null;
      _save();
      _tree = null;
      for (final id in [...offline]) {
        await keep(id); // new sections in saved places come down too
      }
    } catch (e) {
      problem = 'Could not fetch shared places, showing the last copy. ($e)';
    }
    _tree = null;
    notifyListeners();
  }

  /// Your ascents from the shared database, as one outdoor session a day on
  /// the Climbs tab (and in "Export for hibi"). Those sessions follow the
  /// database: log or remove an ascent on a route and the day changes.
  Future<void> syncTicks() async {
    final c = cloud, s = store;
    if (c == null || s == null || c.user == null) return;
    final byDay = <String, List<CloudTick>>{};
    for (final t in await myTicks()) {
      byDay.putIfAbsent(_dayKey(t.day), () => []).add(t);
    }
    for (final old in [...s.sessions]) {
      if (old.source == 'climb-cloud' && !byDay.containsKey(old.id.replaceFirst('cloud-', ''))) s.remove(old.id);
    }
    final t = tree;
    for (final MapEntry(key: day, value: ticks) in byDay.entries) {
      final climbs = [for (final k in ticks) _climbFor(t, k)];
      final first = t[ticks.first.problemId];
      final boulder = first == null ? null : t[first.parentId ?? ''];
      final area = boulder == null ? null : t[boulder.parentId ?? ''];
      final place = [?area?.name, ?boulder?.name].join(' · ');
      final id = 'cloud-$day';
      final old = [
        for (final x in s.sessions)
          if (x.id == id) x,
      ].firstOrNull;
      if (old != null &&
          old.place == place &&
          old.climbs.length == climbs.length &&
          [for (final x in old.climbs) '${x.name}${x.outcome}'].join() == [for (final x in climbs) '${x.name}${x.outcome}'].join()) {
        continue; // unchanged
      }
      final d = ticks.first.day;
      s.update(
        ClimbSession(
          id: id,
          start: ticks.first.createdAt?.toLocal() ?? DateTime(d.year, d.month, d.day, 12),
          place: place,
          outdoor: true,
          climbs: climbs,
          source: 'climb-cloud',
        ),
      );
    }
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Climb _climbFor(PlaceTree t, CloudTick k) {
    final p = t[k.problemId];
    final font = p != null && !p.isRope ? normaliseGrade(p.grade.split('/').first) : '';
    return Climb(
      grade: gradeIndex(font) == null ? '' : font,
      outcome: switch (k.outcome) {
        'flash' => ClimbOutcome.flash,
        'sent' => ClimbOutcome.sent,
        _ => ClimbOutcome.tried,
      },
      name: p == null ? 'A route' : '${displayName(p)}${p.isRope ? ' (${p.grade} UIAA)' : ''}',
      problemId: k.problemId,
    );
  }

  // ---- changes: kept in the outbox, sent when there is signal (#460) ----

  /// "3 changes wait for signal" for the map, or null.
  String? get waitingNote => switch (outbox.ops.length) {
    0 => null,
    1 => '1 change waits for signal (or Wi-Fi) to upload.',
    final n => '$n changes wait for signal (or Wi-Fi) to upload.',
  };

  /// Whether changes may go out now (signal is found out by trying).
  Future<bool> get _maySend async => !outbox.wifiOnly || await onWifi();

  /// Makes a change: shown at once, kept in the outbox, and sent now if it
  /// can be. Null when it worked or waits for signal; else why it failed.
  Future<String?> change(String kind, Map<String, dynamic> data) => changes([(kind, data)]);

  /// Several changes at once, sent together (a section and its lines).
  Future<String?> changes(List<(String, Map<String, dynamic>)> all) async {
    for (final (kind, data) in all) {
      _applyLocal(kind, data);
      outbox.add(kind, data);
    }
    notifyListeners();
    return send();
  }

  var _sending = false;

  /// Sends the waiting changes; null unless the server refused one.
  Future<String?> send() async {
    final c = cloud;
    if (_sending || c == null || c.user == null || outbox.ops.isEmpty || !await _maySend) return null;
    _sending = true;
    try {
      await outbox.flush((op) => _send(c, op));
    } finally {
      _sending = false;
    }
    notifyListeners();
    return outbox.refused;
  }

  Future<void> _send(ClimbCloud c, PendingOp op) async {
    final d = op.data;
    switch (op.kind) {
      case 'tick.add':
        await c.addTick(d['problem_id'] as String, d['outcome'] as String, DateTime.parse(d['day'] as String), id: d['id'] as String);
      case 'tick.remove':
        await c.removeTick(d['id'] as String);
      case 'tick.day':
        await c.setTickDay(d['id'] as String, DateTime.parse(d['day'] as String));
      case 'opinion':
        await c.setOpinion(
          d['problem_id'] as String,
          grade: d['grade'] as String,
          stars: (d['stars'] as num).toInt(),
          tags: (d['tags'] as List).cast<String>(),
          project: d['project'] == true,
        );
      case 'comment.add':
        await c.addComment(d['problem_id'] as String, d['body'] as String, id: d['id'] as String);
      case 'comment.remove':
        await c.removeComment(d['id'] as String);
      case 'place.save':
        await c.savePlace(CloudPlace.fromRow({...d, 'updated_at': DateTime.now().toUtc().toIso8601String()}).place);
      case 'place.delete':
        await c.deletePlace(d['id'] as String);
      case 'place.publish':
        await c.publishPlace(d['id'] as String, verify: d['verify'] == true);
      case 'place.verify':
        await c.verifyPlace(d['id'] as String, d['verified'] == true);
      case 'topo.save':
        final t = Topo.fromRow(d);
        if (d['upload'] == true) {
          final bytes = await photos?.read(t.photoPath);
          if (bytes == null) throw StateError('The photo of ${t.name} is no longer on this phone.');
          await c.uploadPhoto(t.id, bytes);
        }
        await c.saveTopo(t);
      case 'topo.delete':
        await c.deleteTopo(d['id'] as String);
      case 'star':
        await c.setStar(StarKind.values.byName(d['kind'] as String), d['id'] as String, d['on'] == true);
      case 'fav':
        await c.setFavourite(StarKind.values.byName(d['kind'] as String), d['id'] as String, d['on'] == true);
      case 'topo.marks':
        await c.saveTopoMarks(d['id'] as String, d['marks'] as List);
      case 'place.guide':
        await c.addRouteToGuide(d['id'] as String, (d['photos'] as List).cast<String>());
      case 'line.save':
        await c.saveLine(CloudLine.fromRow(d));
      case 'line.delete':
        await c.deleteLine(d['id'] as String);
    }
  }

  /// Shows a place or section change on the phone before it is sent.
  void _applyLocal(String kind, Map<String, dynamic> d) {
    final now = DateTime.now().toUtc();
    final me = cloud?.user?.id;
    switch (kind) {
      case 'place.save':
        cache.merge([CloudPlace.fromRow({...d, 'created_by': cache.createdBy(d['id'] as String) ?? me, 'updated_at': now.toIso8601String()})], local: true);
      case 'place.delete':
        final p = tree[d['id'] as String];
        if (p != null) cache.merge([CloudPlace(place: p, createdBy: me, updatedAt: now, deleted: true)], local: true);
      case 'place.publish' || 'place.verify':
        final p = tree[d['id'] as String];
        if (p == null) return;
        final changed = kind == 'place.publish' ? p.copyWith(draft: false, verified: d['verify'] == true ? true : null) : p.copyWith(verified: d['verified'] == true);
        cache.merge([CloudPlace(place: changed, createdBy: cache.createdBy(p.id), createdAt: cache.createdAt(p.id), updatedAt: now)], local: true);
      case 'topo.save':
        topos.merge([CloudTopo(topo: Topo.fromRow(d), updatedAt: now)], local: true);
      case 'topo.delete':
        final t = topos.byId(d['id'] as String);
        if (t != null) topos.merge([CloudTopo(topo: t, updatedAt: now, deleted: true)], local: true);
      case 'star' || 'fav':
        _applyMark(kind, d);
      case 'place.guide':
        final p = tree[d['id'] as String];
        if (p == null) return;
        cache.merge([CloudPlace(place: p.copyWith(inGuide: true), createdBy: cache.createdBy(p.id), createdAt: cache.createdAt(p.id), updatedAt: now)], local: true);
      case 'topo.marks':
        final t = topos.byId(d['id'] as String);
        if (t != null) {
          final marks = [for (final m in (d['marks'] as List).cast<Map>()) TopoMark.fromJson(m.cast<String, dynamic>())];
          topos.merge([CloudTopo(topo: t.copyWith(marks: marks), updatedAt: now)], local: true);
        }
      case 'line.save':
        lines.merge([CloudLine.fromRow(d)], local: true);
      case 'line.delete':
        final l = lines.byId(d['id'] as String);
        if (l != null) lines.merge([CloudLine(topoId: l.topoId, line: l.line, ord: l.ord, updatedAt: now, deleted: true)], local: true);
      default:
        return;
    }
    _tree = null;
    _save();
  }

  // ---- reads: the server's answer, or its last one without signal ----

  Future<List<T>> _ask<T>(String key, Future<List<T>> Function() fetch, Map<String, dynamic> Function(T) toRow, T Function(Map<String, dynamic>) fromRow) async {
    try {
      final rows = await fetch();
      outbox.remember(key, [for (final r in rows) toRow(r)]);
      return rows;
    } catch (e) {
      final last = outbox.answers[key];
      if (last is List && isNoConnection(e)) return [for (final r in last.cast<Map>()) fromRow(r.cast<String, dynamic>())];
      if (isNoConnection(e)) return const [];
      rethrow;
    }
  }

  Future<List<CloudTick>> myTicks() async {
    final c = cloud!;
    final rows = await _ask('mine', c.myTicks, (t) => t.toRow(), CloudTick.fromRow);
    return outbox.overTicks(rows, userId: c.user?.id);
  }

  Future<List<CloudTick>> ticksOf(String problemId) async =>
      outbox.overTicks(await _ask('ticks:$problemId', () => cloud!.ticksOf(problemId), (t) => t.toRow(), CloudTick.fromRow), problemId: problemId)
        ..sort((a, b) => b.day.compareTo(a.day));

  Future<List<CloudOpinion>> opinionsOf(String problemId) async =>
      outbox.overOpinions(await _ask('opinions:$problemId', () => cloud!.opinionsOf(problemId), (o) => o.toRow(), CloudOpinion.fromRow), {problemId});

  /// Several routes' opinions at once; without signal, from each route's last answer.
  Future<List<CloudOpinion>> opinionsOn(List<String> problemIds) async {
    List<CloudOpinion> rows;
    try {
      rows = await cloud!.opinionsOn(problemIds);
      for (final id in problemIds) {
        outbox.answers['opinions:$id'] = [for (final o in rows) if (o.problemId == id) o.toRow()];
      }
      outbox.save();
    } catch (e) {
      if (!isNoConnection(e)) rethrow;
      rows = [
        for (final id in problemIds)
          for (final r in (outbox.answers['opinions:$id'] as List? ?? const []).cast<Map>()) CloudOpinion.fromRow(r.cast<String, dynamic>()),
      ];
    }
    return outbox.overOpinions(rows, problemIds.toSet());
  }

  Future<List<CloudComment>> commentsOf(String problemId) async =>
      outbox.overComments(await _ask('comments:$problemId', () => cloud!.commentsOf(problemId), (c) => c.toRow(), CloudComment.fromRow), problemId)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void _save() => cacheFile?.write(
    jsonEncode({
      'placeCache': cache.toJson(),
      'topoCache': topos.toJson(),
      'lineCache': lines.toJson(),
      'offline': [...offline],
      'stars': [...myStars],
      'favourites': favourites,
      'starCounts': starCounts,
      'guides': [for (final g in guides) {...g.toRow(), 'created_by': g.createdBy}],
    }),
  );

  /// A place's own sections and those of everything in it.
  List<Topo> toposUnder(String placeId) => [
    for (final id in [placeId, ...tree.descendantsOf(placeId).map((p) => p.id)]) ...topos.of(id),
  ];

  bool isOffline(String placeId) => tree.pathTo(placeId).any((p) => offline.contains(p.id)) || offline.contains(placeId);

  /// The section's photo: from the device when kept, else from the server,
  /// kept as it arrives.
  ImageProvider photoOf(String path) {
    final box = photos;
    if (box != null && box.has(path)) return box.image(path);
    final url = cloud!.photoUrl(path);
    return box == null ? NetworkImage(url) : _KeptPhoto(url, path, box);
  }

  /// Saves [placeId] for use without signal: downloads the photos it is
  /// missing. Null when it worked, else what went wrong.
  Future<String?> keep(String placeId, {void Function(int done, int total)? progress}) async {
    final box = photos, c = cloud;
    if (box == null || c == null) return 'Saving places is not available here.';
    final paths = {
      for (final t in toposUnder(placeId))
        if (t.photoPath.isNotEmpty) t.photoPath,
    }.where((p) => !box.has(p)).toList();
    var done = 0, failed = 0;
    progress?.call(0, paths.length);
    for (final p in paths) {
      try {
        await box.write(p, await fetch(Uri.parse(c.photoUrl(p))));
      } catch (_) {
        failed++;
      }
      progress?.call(++done, paths.length);
    }
    offline.add(placeId);
    _save();
    notifyListeners();
    return failed == 0 ? null : '$failed of ${paths.length} photos did not download (no signal?). Saved the rest; try Update when you have signal.';
  }

  /// Stops keeping [placeId]; its photos go unless another saved place has them.
  Future<void> forget(String placeId) async {
    offline.remove(placeId);
    _save();
    final box = photos;
    if (box != null) {
      final still = {
        for (final id in offline)
          for (final t in toposUnder(id)) t.photoPath,
      };
      for (final t in toposUnder(placeId)) {
        if (!still.contains(t.photoPath) && !isOffline(t.placeId)) await box.delete(t.photoPath);
      }
    }
    notifyListeners();
  }
}

/// A photo from the server that is written to the device once it arrives, so
/// it opens next time without signal.
class _KeptPhoto extends ImageProvider<_KeptPhoto> {
  const _KeptPhoto(this.url, this.path, this.box);
  final String url, path;
  final PhotoBox box;

  @override
  Future<_KeptPhoto> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_KeptPhoto key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw NetworkImageLoadException(statusCode: r.statusCode, uri: Uri.parse(url));
    try {
      await box.write(path, r.bodyBytes);
    } catch (_) {} // keeping it is a nicety
    return decode(await ui.ImmutableBuffer.fromUint8List(r.bodyBytes));
  }

  @override
  bool operator ==(Object other) => other is _KeptPhoto && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// The map's editor: saves to the shared database, then fetches the change
/// so it shows at once.
class CloudPlaceEditor extends PlaceEditor {
  CloudPlaceEditor(this.places);
  final SharedPlaces places;

  ClimbCloud get _cloud => places.cloud!;

  @override
  bool get signedIn => places.cloud?.approved ?? false;
  @override
  String? get me => places.cloud?.user?.id;
  @override
  bool get isAdmin => signedIn && _rights.isAdmin(me);
  @override
  bool mayEdit(String placeId) => signedIn && _rights.canEdit(me, placeId);

  /// Your rights, reaching down the place tree.
  Rights get _rights {
    final c = places.cloud, id = me;
    if (c == null || id == null) return Rights.none;
    final t = places.tree;
    return Rights(owners: {if (c.me?.isOwner ?? false) id}, approved: {if (c.approved) id}, grants: c.grants, parentOf: (p) => t[p]?.parentId);
  }

  @override
  String? createdBy(String placeId) => places.cache.createdBy(placeId);
  @override
  DateTime? createdAt(String placeId) => places.cache.createdAt(placeId);
  @override
  String nameOf(String? userId) => userId == null ? '' : places.names[userId] ?? '';
  @override
  String newId() => newPlaceId();

  @override
  Future<String?> save(Place p) async {
    final old = places.tree[p.id];
    // a new place starts unverified unless an editor publishes it at once;
    // a change keeps what it was (only [setVerified] changes it)
    final verify = old == null && !p.draft && p.kind == PlaceKind.problem && mayVerify(this, p.parentId ?? p.id);
    final err = await _change('place.save', {...placeToRow(p), 'verified': old?.verified ?? (verify || p.kind != PlaceKind.problem)});
    if (err != null || !verify) return err;
    return _change('place.verify', {'id': p.id, 'verified': true});
  }

  @override
  Future<String?> addToGuide(Place route) =>
      _change('place.guide', {'id': route.id, 'photos': [for (final t in places.topos.of(route.parentId ?? '')) if (t.inGuide) t.id]});

  @override
  Future<String?> publish(Place p) => _change('place.publish', {'id': p.id, 'verify': mayVerify(this, p.id)});

  @override
  Future<String?> setVerified(Place p, bool verified) => _change('place.verify', {'id': p.id, 'verified': verified});

  @override
  Future<String?> delete(Place p) => _change('place.delete', {'id': p.id});

  /// Sections in the guide's order: by the number in their name
  /// ('lúčka 01' before 'jaskynka 02'), then by name.
  @override
  List<Topo> toposOf(String placeId) {
    double n(Topo t) {
      final ns = [
        for (final part in t.name.split(' / '))
          ?int.tryParse(RegExp(r'\d+$').stringMatch(part.trim()) ?? ''),
      ];
      return ns.isEmpty ? 1e9 : ns.reduce((a, b) => a + b) / ns.length;
    }
    return [
      for (final t in places.topos.of(placeId))
        if (t.angleOf == null) _visible(t),
    ]..sort((a, b) => n(a) != n(b) ? n(a).compareTo(n(b)) : a.name.compareTo(b.name));
  }

  @override
  List<Topo> anglesOf(Topo section) => [
    for (final t in places.topos.of(section.placeId))
      if (t.angleOf == section.id) _visible(t),
  ];

  /// With its lines from their own rows; lines of routes you can't see
  /// (someone's private route, #462) hidden.
  Topo _visible(Topo topo) {
    final t = places.withLines(topo);
    final tree = places.tree;
    return t.lines.every((l) => tree[l.problemId] != null) ? t : t.copyWith(lines: [for (final l in t.lines) if (tree[l.problemId] != null) l]);
  }

  @override
  ImageProvider photoOf(Topo t, {bool original = false}) => places.photoOf(original && t.originalPath.isNotEmpty ? t.originalPath : t.photoPath);

  @override
  bool get canKeepOffline => places.photos != null && places.cloud != null;
  @override
  bool isOffline(String placeId) => places.isOffline(placeId);
  @override
  Future<String?> keepOffline(String placeId, {void Function(int done, int total)? progress}) => places.keep(placeId, progress: progress);
  @override
  Future<void> forgetOffline(String placeId) => places.forget(placeId);

  /// The phone shrinks the photo (1600 px, JPEG 80): about 250–500 KB.
  @override
  Future<TopoPhoto?> pickPhoto({required bool camera}) async {
    final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final photo = TopoPhoto(bytes, frame.image.width, frame.image.height);
    frame.image.dispose();
    return photo;
  }

  @override
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) async {
    final before = places.topos.byId(t.id);
    final oldLines = before == null ? const <TopoLine>[] : places.withLines(before).lines;
    var topo = t;
    var upload = false;
    if (photo != null && t.photoPath.isEmpty) {
      if (photo.bytes.length > 1000000) return 'The photo is over 1 MB even after shrinking.';
      final box = places.photos;
      final path = '$me/${t.id}.jpg'; // where uploadPhoto puts it
      if (box != null) {
        await box.write(path, photo.bytes); // shown from the phone until it is up
        topo = t.copyWith(photoPath: path, width: photo.width, height: photo.height);
        upload = true;
      } else {
        try {
          topo = t.copyWith(photoPath: await _cloud.uploadPhoto(t.id, photo.bytes), width: photo.width, height: photo.height);
        } catch (e) {
          return 'Could not upload the photo. Check your connection. ($e)';
        }
      }
    }
    // each route keeps its line's row, author and place in the guide
    final editor = mayVerify(this, topo.placeId);
    final was = {for (final l in oldLines) l.problemId: l};
    final lines = [
      for (final l in topo.lines)
        l.id != null ? l : l.copyWith(id: was[l.problemId]?.id ?? newUuid(), createdBy: was[l.problemId]?.createdBy ?? me, inGuide: was[l.problemId]?.inGuide ?? editor),
    ];
    topo = topo.copyWith(lines: lines);
    final now = DateTime.now().toUtc();
    final ops = <(String, Map<String, dynamic>)>[
      // the section's own row, for its maker and editors; older app versions
      // read the guide's lines from it
      if (before == null || canEditTopo(this, before))
        ('topo.save', {...topo.copyWith(lines: [for (final l in lines) if (l.inGuide) l]).toRow(), 'created_by': topo.createdBy, 'upload': upload})
      // someone else's photo: only the letters you added (#519)
      else if (topo.marks.length > before.marks.length)
        ('topo.marks', {'id': topo.id, 'marks': [for (final m in before.marks) m.toJson(), for (final m in topo.marks) if (before.markNamed(m.label) == null) m.toJson()]}),
    ];
    if (places.lines.synced) {
      bool mine(TopoLine l) => editor || l.createdBy == me;
      final oldById = {for (var i = 0; i < oldLines.length; i++) oldLines[i].id: (i, oldLines[i])};
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i], old = oldById[l.id];
        if (!mine(l) || (old != null && old.$1 == i && jsonEncode(old.$2.toJson()) == jsonEncode(l.toJson()))) continue;
        ops.add(('line.save', CloudLine(topoId: topo.id, line: l, ord: i, updatedAt: now).toCacheRow()));
      }
      for (final old in oldLines) {
        if (old.id != null && mine(old) && !lines.any((l) => l.id == old.id)) ops.add(('line.delete', {'id': old.id}));
      }
    }
    if (ops.isEmpty) return null;
    final err = await places.changes(ops);
    if (err == null && places.outbox.ops.isEmpty) unawaited(places.refresh());
    return err;
  }

  @override
  Future<String?> deleteTopo(Topo t) => _change('topo.delete', {'id': t.id});

  @override
  Future<List<Ascent>> ascentsOf(String problemId) async => [
    for (final t in await places.ticksOf(problemId)) (id: t.id, userId: t.userId, who: nameOf(t.userId), day: t.day, outcome: t.outcome),
  ];

  @override
  Future<List<Opinion>> opinionsOf(String problemId) async => [
    for (final o in await places.opinionsOf(problemId))
      (userId: o.userId, who: nameOf(o.userId), grade: o.grade, stars: o.stars, tags: o.tags, project: o.project),
  ];

  @override
  Future<String?> setOpinion(String problemId, {required String grade, required int stars, required List<String> tags, required bool project}) =>
      places.change('opinion', {'problem_id': problemId, 'user_id': me, 'grade': grade, 'stars': stars, 'tags': tags, 'project': project});

  @override
  Future<List<(String, Opinion)>> opinionsOn(List<String> problemIds) async => [
    for (final o in await places.opinionsOn(problemIds))
      (o.problemId, (userId: o.userId, who: nameOf(o.userId), grade: o.grade, stars: o.stars, tags: o.tags, project: o.project)),
  ];

  @override
  Future<void> loadStars(String kind, List<String> ids) => places.loadStars(kind, ids);
  @override
  int starsOf(String kind, String id) => places.starCounts['$kind:$id'] ?? 0;
  @override
  bool starredByMe(String kind, String id) => places.myStars.contains('$kind:$id');
  @override
  Future<String?> setStar(String kind, String id, bool on) => _change('star', {'kind': kind, 'id': id, 'on': on});
  @override
  bool isFavourite(String kind, String id) => places.favourites.contains('$kind:$id');
  @override
  Future<String?> setFavourite(String kind, String id, bool on) => _change('fav', {'kind': kind, 'id': id, 'on': on});
  @override
  List<(String, String)> get favourites => [
    for (final f in places.favourites) (f.substring(0, f.indexOf(':')), f.substring(f.indexOf(':') + 1)),
  ];
  @override
  Topo? topoById(String id) => places.topos.byId(id);
  @override
  GuideInfo? guideById(String id) => _guide(places.guides.where((g) => g.id == id).firstOrNull);
  @override
  GuideInfo? guideOf(String placeId) => _guide(places.guides.where((g) => g.placeId == placeId && g.official).firstOrNull);
  GuideInfo? _guide(CloudGuide? g) => g == null ? null : (id: g.id, placeId: g.placeId, name: g.name, credit: g.credit);
  @override
  Future<Map<String, ({int tops, int flashes})>> ascentCounts(List<String> problemIds) => places.ascentCounts(problemIds);

  @override
  Future<Set<String>> toppedByMe() async => {
    for (final t in await places.myTicks())
      if (t.outcome != 'tried') t.problemId,
  };

  @override
  Future<List<RouteComment>> commentsOf(String problemId) async => [
    for (final c in await places.commentsOf(problemId)) (id: c.id, userId: c.userId, who: nameOf(c.userId), body: c.body, at: c.createdAt.toLocal()),
  ];

  @override
  Future<String?> addComment(String problemId, String body) => places.change('comment.add', {
    'id': newUuid(),
    'user_id': me,
    'problem_id': problemId,
    'body': body,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });

  @override
  Future<String?> removeComment(String id) => places.change('comment.remove', {'id': id});

  @override
  Future<String?> logAscent(String problemId, String outcome) async {
    final d = hibiDay();
    final err = await places.change('tick.add', {
      'id': newUuid(),
      'user_id': me,
      'problem_id': problemId,
      'outcome': outcome,
      'day': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await places.syncTicks().catchError((_) {}); // onto the Climbs tab
    return err;
  }

  @override
  Future<String?> removeAscent(String id) async {
    final err = await places.change('tick.remove', {'id': id});
    await places.syncTicks().catchError((_) {});
    return err;
  }

  @override
  Future<String?> setAscentDay(String id, DateTime day) async {
    final err = await places.change('tick.day', {'id': id, 'day': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'});
    await places.syncTicks().catchError((_) {});
    return err;
  }

  @override
  List<String> get guides => isAdmin && places.hasGuide ? kGuides.keys.toList() : const [];

  /// Adds a bundled guide to [boulder]: its routes as problems, its pages as
  /// sections (the cleaned photo with our lines, the guide's page as the
  /// second photo). A route on several pages is one problem.
  @override
  Future<String?> importGuide(String guide, Place boulder) => _run(() async {
    final dir = kGuides[guide] ?? kGuides.values.first;
    final g = jsonDecode(await rootBundle.loadString('$dir/guide.json')) as Map<String, dynamic>;
    final source = g['source'] as String? ?? guide;
    // run again after a failure: reuse the routes and sections already added
    final have = <String, String>{
      for (final p in places.tree.childrenOf(boulder.id))
        if (p.kind == PlaceKind.problem && p.source == source && p.number.isNotEmpty) p.number: p.id,
    };
    final haveSections = {for (final t in places.topos.of(boulder.id)) t.name: t};
    final ids = <String, String>{};
    for (final r in (g['routes'] as List).cast<Map<String, dynamic>>()) {
      if (have[r['number']] case final known?) {
        ids[r['number'] as String] = known;
        continue;
      }
      final id = newPlaceId();
      ids[r['number'] as String] = id;
      await _cloud.savePlace(
        Place(
          id: id,
          parentId: boulder.id,
          kind: PlaceKind.problem,
          name: r['name'] as String,
          gradeSystem: r['scale'] == 'uiaa' ? GradeSystem.uiaa : GradeSystem.font,
          grade: r['grade'] as String,
          source: source,
          licence: 'guide',
          details: {
            'number': r['number'],
            if (r['sit'] == true) 'sit': true,
            if (r['sitHeight'] != null) 'sitHeight': r['sitHeight'],
            if (r['uncertain'] == true) 'uncertain': true,
            if ((r['note'] as String? ?? '').isNotEmpty) 'note': r['note'],
          },
        ),
      );
    }
    for (final s in (g['sections'] as List).cast<Map<String, dynamic>>()) {
      final marks = [for (final m in (s['marks'] as List).cast<Map>()) TopoMark.fromJson(m.cast<String, dynamic>())];
      final lines = [
        for (final l in (s['lines'] as List).cast<Map>()) TopoLine.fromJson({...l.cast<String, dynamic>(), 'problem': ids[l['route']]}),
      ];
      final overlay = TopoOverlay.fromJson((s['overlay'] as Map?)?.cast<String, dynamic>());
      if (haveSections[s['name']] case final old?) {
        // already there: bring its letters and lines up to the guide's
        final t = old.copyWith(marks: marks, lines: lines, overlay: overlay);
        await _cloud.saveTopo(t);
        await _importLines(t);
        continue;
      }
      final id = newTopoId();
      final photo = (await rootBundle.load('$dir/${s['photo']}')).buffer.asUint8List();
      // a guide page of its own when the photo is a cleaned one; none when
      // the photo is the guide's (Vyhliadka)
      final original = s['original'] == null ? null : (await rootBundle.load('$dir/${s['original']}')).buffer.asUint8List();
      final topo = Topo(
        id: id,
        placeId: boulder.id,
        name: s['name'] as String,
        photoPath: await _cloud.uploadPhoto(id, photo),
        originalPath: original == null ? '' : await _cloud.uploadPhoto('$id-guide', original),
        width: s['width'] as int,
        height: s['height'] as int,
        marks: marks,
        lines: lines,
        overlay: overlay,
      );
      await _cloud.saveTopo(topo);
      await _importLines(topo);
    }
    // the guide's name and credit (010_guides.sql)
    try {
      if (!(await _cloud.guides()).any((x) => x.placeId == boulder.id)) {
        await _cloud.saveGuide(CloudGuide(id: newUuid(), placeId: boulder.id, name: guide, credit: source));
      }
    } catch (_) {} // before 010_guides.sql
  });

  /// A guide section's lines as their own rows, reusing each route's row.
  Future<void> _importLines(Topo t) async {
    try {
      final was = {for (final l in places.lines.of(t.id)) l.problemId: l};
      for (var i = 0; i < t.lines.length; i++) {
        final l = t.lines[i];
        await _cloud.saveLine(CloudLine(topoId: t.id, line: l.copyWith(id: was[l.problemId]?.id ?? newUuid()), ord: i, updatedAt: DateTime.now().toUtc()));
      }
    } catch (_) {} // before 010_guides.sql: the lines are in the section
  }

  /// A place or section change through the outbox; fetches everyone's
  /// changes afterwards when it went out.
  Future<String?> _change(String kind, Map<String, dynamic> data) async {
    final err = await places.change(kind, data);
    if (err == null && places.outbox.ops.isEmpty) unawaited(places.refresh());
    return err;
  }

  Future<String?> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      return 'Could not save. Check your connection and that you are signed in. ($e)';
    }
    await places.refresh();
    return places.problem;
  }
}

/// The guides bundled with the app, by name: where each one's guide.json and
/// photos are. Devín's crag (lúčka, jaskynka) and its Vyhliadka boulder (#465).
const kGuides = {'Devín': 'assets/guides/devin', 'Vyhliadka': 'assets/guides/vyhliadka'};

/// Today, where the day starts at 04:00 (a late session still counts for
/// the evening it began).
DateTime hibiDay([DateTime? now]) {
  final n = (now ?? DateTime.now()).subtract(const Duration(hours: 4));
  return DateTime(n.year, n.month, n.day);
}
