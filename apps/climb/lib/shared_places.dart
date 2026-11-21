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
    Set<String>? offline,
    this.fetch = _download,
    Outbox? outbox,
    Future<bool> Function()? onWifi,
  }) : cache = cache ?? PlaceCache(),
       topos = topos ?? TopoCache(),
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
    var offline = <String>{};
    try {
      final text = cacheFile?.read();
      if (text != null) {
        final j = jsonDecode(text) as Map<String, dynamic>;
        cache = PlaceCache.fromJson((j['placeCache'] as Map).cast<String, dynamic>());
        topos = TopoCache.fromJson((j['topoCache'] as Map).cast<String, dynamic>());
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
      offline: offline,
      outbox: outbox,
      onWifi: onWifi,
    )..hasGuide = guide;
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
        names
          ..clear()
          ..addAll({for (final p in await c.allProfiles()) p.id: p.name});
      } catch (_) {} // names are a nicety
      await c.allGrants();
      await syncTicks();
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
  Future<String?> change(String kind, Map<String, dynamic> data) async {
    _applyLocal(kind, data);
    outbox.add(kind, data);
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
      case 'topo.save':
        topos.merge([CloudTopo(topo: Topo.fromRow(d), updatedAt: now)], local: true);
      case 'topo.delete':
        final t = topos.byId(d['id'] as String);
        if (t != null) topos.merge([CloudTopo(topo: t, updatedAt: now, deleted: true)], local: true);
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
      'offline': [...offline],
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
  Future<String?> save(Place p) => _change('place.save', placeToRow(p));

  @override
  Future<String?> delete(Place p) => _change('place.delete', {'id': p.id});

  /// Sections in the guide's order: by the number in their name
  /// ('lúčka 01' before 'jaskynka 02'), then by name.
  @override
  List<Topo> toposOf(String placeId) {
    int n(Topo t) => int.tryParse(RegExp(r'\d+$').stringMatch(t.name.trim()) ?? '') ?? 1 << 20;
    return places.topos.of(placeId)..sort((a, b) => n(a) != n(b) ? n(a).compareTo(n(b)) : a.name.compareTo(b.name));
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
    return _change('topo.save', {...topo.toRow(), 'created_by': topo.createdBy, 'upload': upload});
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
  List<String> get guides => isAdmin && places.hasGuide ? const ['Devín'] : const [];

  /// Adds a bundled guide to [boulder]: its routes as problems, its pages as
  /// sections (the cleaned photo with our lines, the guide's page as the
  /// second photo). A route on several pages is one problem.
  @override
  Future<String?> importGuide(String guide, Place boulder) => _run(() async {
    const dir = 'assets/guides/devin';
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
        await _cloud.saveTopo(old.copyWith(marks: marks, lines: lines, overlay: overlay));
        continue;
      }
      final id = newTopoId();
      final photo = (await rootBundle.load('$dir/${s['photo']}')).buffer.asUint8List();
      final original = (await rootBundle.load('$dir/${s['original']}')).buffer.asUint8List();
      final topo = Topo(
        id: id,
        placeId: boulder.id,
        name: s['name'] as String,
        photoPath: await _cloud.uploadPhoto(id, photo),
        originalPath: await _cloud.uploadPhoto('$id-guide', original),
        width: s['width'] as int,
        height: s['height'] as int,
        marks: marks,
        lines: lines,
        overlay: overlay,
      );
      await _cloud.saveTopo(topo);
    }
  });

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

/// Today, where the day starts at 04:00 (a late session still counts for
/// the evening it began).
DateTime hibiDay([DateTime? now]) {
  final n = (now ?? DateTime.now()).subtract(const Duration(hours: 4));
  return DateTime(n.year, n.month, n.day);
}
