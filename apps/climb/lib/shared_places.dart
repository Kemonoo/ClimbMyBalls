// The places on the map: the OpenStreetMap import bundled with the app, plus
// the shared places and topos from the database (docs/climb/plan.md step 7),
// kept on the phone so the map works without signal and only new changes are
// fetched.
import 'dart:convert';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:hibi_climbing/climbing.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/store.dart';
import 'package:hibi_climbing/places/place_tree.dart';
import 'package:hibi_climbing/places/topo.dart';
import 'package:hibi_climbing_cloud/climbing_cloud.dart';
import 'package:hibi_climbing_map/climbing_map.dart';
import 'package:image_picker/image_picker.dart';

import 'storage/text_box.dart';

class SharedPlaces extends ChangeNotifier {
  SharedPlaces({required this.bundled, this.cloud, this.cacheFile, this.store, PlaceCache? cache, TopoCache? topos})
    : cache = cache ?? PlaceCache(),
      topos = topos ?? TopoCache();

  final List<Place> bundled;

  /// Your sessions (the Climbs tab): ascents logged on routes land here.
  final ClimbingStore? store;
  final ClimbCloud? cloud;
  final TextBox? cacheFile;
  final PlaceCache cache;
  final TopoCache topos;

  /// Why the last refresh failed, shown on the map; null when fine.
  String? problem;

  /// Whether this build carries the Devín guide (the public repository
  /// leaves the guide's photos out).
  var hasGuide = false;

  /// People's names by user id, for "added by" and ascents.
  final names = <String, String>{};
  PlaceTree? _tree;

  PlaceTree get tree => _tree ??= PlaceTree([...bundled, ...cache.places]);

  /// Loads the bundled places and the phone's copy of the shared ones.
  static Future<SharedPlaces> load({ClimbCloud? cloud, TextBox? cacheFile, ClimbingStore? store}) async {
    final raw = jsonDecode(await rootBundle.loadString('assets/places/sk.json', cache: false)) as List;
    var guide = false;
    try {
      guide = (await rootBundle.load('assets/guides/devin/guide.json')).lengthInBytes > 0;
    } catch (_) {}
    PlaceCache? cache;
    TopoCache? topos;
    try {
      final text = cacheFile?.read();
      if (text != null) {
        final j = jsonDecode(text) as Map<String, dynamic>;
        cache = PlaceCache.fromJson((j['placeCache'] as Map).cast<String, dynamic>());
        topos = TopoCache.fromJson((j['topoCache'] as Map).cast<String, dynamic>());
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
      cache: cache,
      topos: topos,
    )..hasGuide = guide;
  }

  /// Fetches what changed since last time, when signed in.
  Future<void> refresh() async {
    final c = cloud;
    if (c == null || c.user == null) return;
    try {
      if (c.me == null) await c.myProfile();
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
      await syncTicks();
      problem = null;
      _save();
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
    for (final t in await c.myTicks()) {
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

  void _save() => cacheFile?.write(jsonEncode({'placeCache': cache.toJson(), 'topoCache': topos.toJson()}));
}

/// The map's editor: saves to the shared database, then fetches the change
/// so it shows at once.
class CloudPlaceEditor implements PlaceEditor {
  CloudPlaceEditor(this.places);
  final SharedPlaces places;

  ClimbCloud get _cloud => places.cloud!;

  @override
  bool get signedIn => places.cloud?.approved ?? false;
  @override
  String? get me => places.cloud?.user?.id;
  @override
  bool get isAdmin => signedIn && (places.cloud?.me?.isAdmin ?? false);
  @override
  String? createdBy(String placeId) => places.cache.createdBy(placeId);
  @override
  DateTime? createdAt(String placeId) => places.cache.createdAt(placeId);
  @override
  String nameOf(String? userId) => userId == null ? '' : places.names[userId] ?? '';
  @override
  String newId() => newPlaceId();

  @override
  Future<String?> save(Place p) => _run(() => _cloud.savePlace(p));

  @override
  Future<String?> delete(Place p) => _run(() => _cloud.deletePlace(p.id));

  /// Sections in the guide's order: by the number in their name
  /// ('lúčka 01' before 'jaskynka 02'), then by name.
  @override
  List<Topo> toposOf(String placeId) {
    int n(Topo t) => int.tryParse(RegExp(r'\d+$').stringMatch(t.name.trim()) ?? '') ?? 1 << 20;
    return places.topos.of(placeId)..sort((a, b) => n(a) != n(b) ? n(a).compareTo(n(b)) : a.name.compareTo(b.name));
  }

  @override
  ImageProvider photoOf(Topo t, {bool original = false}) => NetworkImage(_cloud.photoUrl(original && t.originalPath.isNotEmpty ? t.originalPath : t.photoPath));

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
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) => _run(() async {
    var topo = t;
    if (photo != null && t.photoPath.isEmpty) {
      if (photo.bytes.length > 1000000) throw StateError('The photo is over 1 MB even after shrinking.');
      topo = t.copyWith(photoPath: await _cloud.uploadPhoto(t.id, photo.bytes), width: photo.width, height: photo.height);
    }
    await _cloud.saveTopo(topo);
  });

  @override
  Future<String?> deleteTopo(Topo t) => _run(() => _cloud.deleteTopo(t.id));

  @override
  Future<List<Ascent>> ascentsOf(String problemId) async => [
    for (final t in await _cloud.ticksOf(problemId)) (id: t.id, userId: t.userId, who: nameOf(t.userId), day: t.day, outcome: t.outcome),
  ];

  @override
  Future<String?> logAscent(String problemId, String outcome) async {
    try {
      await _cloud.addTick(problemId, outcome, hibiDay());
    } catch (e) {
      return 'Could not log it. Check your connection. ($e)';
    }
    await places.syncTicks().catchError((_) {}); // onto the Climbs tab
    return null;
  }

  @override
  Future<String?> removeAscent(String id) async {
    try {
      await _cloud.removeTick(id);
    } catch (e) {
      return 'Could not remove it. ($e)';
    }
    await places.syncTicks().catchError((_) {});
    return null;
  }

  @override
  Future<String?> setAscentDay(String id, DateTime day) async {
    try {
      await _cloud.setTickDay(id, day);
    } catch (e) {
      return 'Could not change the date. ($e)';
    }
    await places.syncTicks().catchError((_) {});
    return null;
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
      if (haveSections[s['name']] case final old?) {
        // already there: bring its letters and lines up to the guide's
        await _cloud.saveTopo(old.copyWith(marks: marks, lines: lines));
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
      );
      await _cloud.saveTopo(topo);
    }
  });

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
