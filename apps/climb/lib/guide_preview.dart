// A look at a bundled guide without the server: its sections and routes from
// the app's assets, read-only. For checking the screens on a PC
// (`--dart-define=CLIMB_PREVIEW=devin`) and for tests.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:climbing/places/near.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:climbing/places/topo.dart';
import 'package:climbing_map/climbing_map.dart';

import 'shared_places.dart';

class GuidePreview extends PlaceEditor {
  GuidePreview._(this.tree, this.boulder, this._topos);

  final PlaceTree tree;
  final Place boulder;
  final List<Topo> _topos;

  static const _dir = 'assets/guides/devin';

  static Future<GuidePreview> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final g = jsonDecode(await b.loadString('$_dir/guide.json')) as Map<String, dynamic>;
    const boulder = Place(id: 'guide-boulder', kind: PlaceKind.boulder, name: 'Devín castle boulder');
    final problems = [
      for (final r in (g['routes'] as List).cast<Map<String, dynamic>>())
        Place(
          id: 'guide-${r['number']}',
          parentId: boulder.id,
          kind: PlaceKind.problem,
          name: r['name'] as String,
          gradeSystem: r['scale'] == 'uiaa' ? GradeSystem.uiaa : GradeSystem.font,
          grade: r['grade'] as String,
          source: g['source'] as String? ?? 'guide',
          details: {
            'number': r['number'],
            if (r['sit'] == true) 'sit': true,
            if (r['sitHeight'] != null) 'sitHeight': r['sitHeight'],
            if (r['uncertain'] == true) 'uncertain': true,
            if ((r['note'] as String? ?? '').isNotEmpty) 'note': r['note'],
          },
        ),
    ];
    final topos = <Topo>[
      for (final s in (g['sections'] as List).cast<Map<String, dynamic>>())
        Topo(
          id: 'guide-${s['key']}',
          placeId: boulder.id,
          name: s['name'] as String,
          photoPath: '$_dir/${s['photo']}',
          originalPath: '$_dir/${s['original']}',
          width: s['width'] as int,
          height: s['height'] as int,
          marks: [for (final m in (s['marks'] as List).cast<Map>()) TopoMark.fromJson(m.cast<String, dynamic>())],
          lines: [
            for (final l in (s['lines'] as List).cast<Map>()) TopoLine.fromJson({...l.cast<String, dynamic>(), 'problem': 'guide-${l['route']}'}),
          ],
          overlay: TopoOverlay.fromJson((s['overlay'] as Map?)?.cast<String, dynamic>()),
        ),
    ];
    return GuidePreview._(PlaceTree([boulder, ...problems]), boulder, topos);
  }

  // signed in as "you" in memory, with a few made-up friends' votes, so the
  // route page can be looked at without the server
  @override
  bool get signedIn => true;
  @override
  String? get me => 'you';
  @override
  bool get isAdmin => true; // to try the section editor; nothing leaves memory
  @override
  bool mayEdit(String placeId) => false;
  @override
  String? createdBy(String placeId) => null;
  @override
  DateTime? createdAt(String placeId) => null;
  @override
  String nameOf(String? userId) => const {'you': 'You', 'f1': 'Ema', 'f2': 'Jakub', 'f3': 'Lea'}[userId] ?? '';
  @override
  String newId() => 'preview';
  @override
  Future<String?> save(Place p) async => 'Preview only.';
  @override
  Future<String?> delete(Place p) async => 'Preview only.';
  @override
  List<Topo> toposOf(String placeId) => placeId == boulder.id ? _topos : const [];
  @override
  ImageProvider photoOf(Topo t, {bool original = false}) => AssetImage(original && t.originalPath.isNotEmpty ? t.originalPath : t.photoPath);
  // the editor's photo: the guide's cleaned jaskynka photo
  @override
  Future<TopoPhoto?> pickPhoto({required bool camera}) async =>
      TopoPhoto((await rootBundle.load('$_dir/jaskynka-02-clean.jpg')).buffer.asUint8List(), 1596, 896);
  @override
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) async {
    final saved = photo != null ? t.copyWith(photoPath: '$_dir/jaskynka-02-clean.jpg') : t;
    final i = _topos.indexWhere((x) => x.id == t.id);
    if (i < 0) {
      _topos.add(saved);
    } else {
      _topos[i] = saved;
    }
    return null;
  }
  @override
  Future<String?> deleteTopo(Topo t) async => 'Preview only.';
  @override
  Future<List<Ascent>> ascentsOf(String problemId) async => [
    for (final a in _ascents)
      if (a.$1 == problemId) a.$2,
  ].reversed.toList();
  @override
  Future<String?> logAscent(String problemId, String outcome) async {
    _ascents.add((problemId, (id: 'a${_ascents.length}', userId: 'you', who: 'You', day: hibiDay(), outcome: outcome)));
    return null;
  }

  @override
  Future<String?> removeAscent(String id) async {
    _ascents.removeWhere((a) => a.$2.id == id);
    return null;
  }

  final _ascents = <(String, Ascent)>[];
  final _opinions = <String, Map<String, Opinion>>{};
  final _comments = <String, List<RouteComment>>{};

  Map<String, Opinion> _seeded(String problemId) => _opinions.putIfAbsent(problemId, () {
    final p = tree[problemId];
    final scale = p?.gradeSystem ?? GradeSystem.font;
    final steps = gradeSteps(scale);
    final at = p == null ? null : gradeStep(p.grade, scale);
    if (at == null) return {};
    final h = problemId.codeUnits.fold(0, (a, b) => a + b);
    return {
      for (final (i, f) in ['f1', 'f2', 'f3'].indexed)
        f: (userId: f, who: nameOf(f), grade: steps[(at + ((h + i) % 3) - 1).clamp(0, steps.length - 1)], stars: 3 + (h + i) % 3, tags: [routeTags[(h + i) % routeTags.length].id, routeTags[(h * 3 + i) % routeTags.length].id], project: false),
    };
  });

  @override
  Future<List<Opinion>> opinionsOf(String problemId) async => _seeded(problemId).values.toList();
  @override
  Future<String?> setOpinion(String problemId, {required String grade, required int stars, required List<String> tags, required bool project}) async {
    _seeded(problemId)['you'] = (userId: 'you', who: 'You', grade: grade, stars: stars, tags: tags, project: project);
    return null;
  }

  @override
  Future<List<(String, Opinion)>> opinionsOn(List<String> problemIds) async => [
    for (final id in problemIds)
      for (final o in _seeded(id).values) (id, o),
  ];

  @override
  Future<Set<String>> toppedByMe() async => {
    for (final a in _ascents)
      if (a.$2.outcome != 'tried') a.$1,
  };

  @override
  Future<List<RouteComment>> commentsOf(String problemId) async => List.of(_comments[problemId] ?? const []);
  @override
  Future<String?> addComment(String problemId, String body) async {
    (_comments[problemId] ??= []).add((id: 'c$problemId${_comments[problemId]!.length}', userId: 'you', who: 'You', body: body, at: DateTime.now()));
    return null;
  }

  @override
  Future<String?> removeComment(String id) async {
    for (final l in _comments.values) {
      l.removeWhere((c) => c.id == id);
    }
    return null;
  }
  @override
  Future<String?> setAscentDay(String id, DateTime day) async => 'Preview only.';
  @override
  List<String> get guides => const [];
  @override
  Future<String?> importGuide(String guide, Place boulder) async => 'Preview only.';

  /// The boulder's page.
  Widget screen() => BoulderScreen(tree: () => tree, boulderId: boulder.id, editor: this);
}
