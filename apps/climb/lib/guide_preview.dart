// A look at a bundled guide without the server: its sections and routes from
// the app's assets, read-only. For checking the screens on a PC
// (`--dart-define=CLIMB_PREVIEW=devin`) and for tests.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/places/place_tree.dart';
import 'package:hibi_climbing/places/topo.dart';
import 'package:hibi_climbing_map/climbing_map.dart';

class GuidePreview implements PlaceEditor {
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

  @override
  bool get signedIn => false;
  @override
  String? get me => null;
  @override
  bool get isAdmin => false;
  @override
  bool mayEdit(String placeId) => false;
  @override
  String? createdBy(String placeId) => null;
  @override
  DateTime? createdAt(String placeId) => null;
  @override
  String nameOf(String? userId) => '';
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
  @override
  Future<TopoPhoto?> pickPhoto({required bool camera}) async => null;
  @override
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo}) async => 'Preview only.';
  @override
  Future<String?> deleteTopo(Topo t) async => 'Preview only.';
  @override
  Future<List<Ascent>> ascentsOf(String problemId) async => const [];
  @override
  Future<String?> logAscent(String problemId, String outcome) async => 'Preview only.';
  @override
    Future<String?> removeAscent(String id) async => null;
  @override
  Future<String?> setAscentDay(String id, DateTime day) async => 'Preview only.';
  @override
  List<String> get guides => const [];
  @override
  Future<String?> importGuide(String guide, Place boulder) async => 'Preview only.';

  /// The boulder's page.
  Widget screen() => BoulderScreen(tree: () => tree, boulderId: boulder.id, editor: this);
}
