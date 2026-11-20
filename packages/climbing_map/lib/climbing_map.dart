// The climbing map (docs/climb/plan.md, step 4): Mapy.com outdoor tiles, your
// position, a "near me" list, outdoor / indoor / grade filters, search, and
// tapping into the place hierarchy. Read-only for now.
//
// Only the standalone Climb app uses this package. Its screen is built when
// the map tab is first opened, so tiles load only then.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing/places/import.dart' show pointInPolygon;
import 'package:climbing/places/near.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:climbing/places/shape.dart';
import 'package:climbing/places/topo.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

part 'src/tiles.dart';
part 'src/locator.dart';
part 'src/place_sheet.dart';
part 'src/editor.dart';
part 'src/topo_paint.dart';
part 'src/topo_screens.dart';
part 'src/boulder_screen.dart';
part 'src/route_filter.dart';

ll.LatLng _ll(LatLng p) => ll.LatLng(p.lat, p.lng);
LatLng _ours(ll.LatLng p) => LatLng(p.latitude, p.longitude);

IconData placeIcon(Place p) => switch (p.kind) {
  PlaceKind.country || PlaceKind.region => Icons.public,
  PlaceKind.area => Icons.terrain_rounded,
  PlaceKind.sector => Icons.landscape_rounded,
  PlaceKind.boulder => Icons.circle,
  PlaceKind.problem => Icons.flag_rounded,
  PlaceKind.gymWall => Icons.home_work_rounded,
};

String kindLabel(PlaceKind k) => switch (k) {
  PlaceKind.country => 'Country',
  PlaceKind.region => 'Region',
  PlaceKind.area => 'Area',
  PlaceKind.sector => 'Sector',
  PlaceKind.boulder => 'Boulder',
  PlaceKind.problem => 'Problem',
  PlaceKind.gymWall => 'Gym',
};

/// The map screen.
class ClimbMapScreen extends StatefulWidget {
  const ClimbMapScreen({
    super.key,
    required this.places,
    this.tiles = const MapTiles(mapyKey: ''),
    this.locator = const DeviceLocator(),
    this.start = const LatLng(48.1745, 16.9790), // Devín
    this.cacheDirectory,
    this.editor,
    this.notice,
  });

  /// A line to show at the top, e.g. why shared places couldn't load.
  final String? notice;

  /// Adding places and problems; null when nothing can be shared.
  final PlaceEditor? editor;

  final PlaceTree places;
  final MapTiles tiles;
  final Locator locator;
  final LatLng start;

  /// Where tiles may be kept (for the server's own cache time only). Null:
  /// the platform's cache folder.
  final String? cacheDirectory;

  @override
  State<ClimbMapScreen> createState() => _ClimbMapScreenState();
}

class _ClimbMapScreenState extends State<ClimbMapScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  var _filter = const PlaceFilter();
  LatLng? _me;
  String? _locateProblem;
  bool _locating = false;
  late LatLng _centre = widget.start;

  // Adding a place: first the spot (a cross in the middle of the map), then
  // what it is, then for a boulder its outline (taps on the map).
  var _mode = _Mode.browse;
  PlaceDraft? _draft;
  LatLng? _spot;

    /// A place whose outline is being changed, instead of a new one.
  Place? _reshaping;

  // Dragging a corner (or the whole shape) with one finger: the map holds
  // still, and a magnifier above the finger shows where it is.
  int? _dragNode; // corner index; -1 for the whole shape
  int? _dragPointer;
  Offset? _finger;
  var _pressedNode = false; // the last press was on a corner: not a new point

  Offset _screenOf(LatLng p) => _map.camera.latLngToScreenOffset(_ll(p));

  void _pointerDown(PointerDownEvent e) {
    _pressedNode = false;
    if (_mode != _Mode.outline || _dragPointer != null || _outline.isEmpty) return;
    int? best;
    var bestD = 30.0;
    for (var i = 0; i < _outline.length; i++) {
      final d = (_screenOf(_outline[i]) - e.localPosition).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best == null && _outline.length >= 3 && (_screenOf(ringCentre(_outline)) - e.localPosition).distance < 28) best = -1;
    if (best == null) return;
    _pressedNode = true;
    setState(() {
      _dragNode = best;
      _dragPointer = e.pointer;
      _finger = e.localPosition;
    });
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _dragPointer || _dragNode == null) return;
    final at = _ours(_map.camera.screenOffsetToLatLng(e.localPosition));
    setState(() {
      _finger = e.localPosition;
      if (_dragNode == -1) {
        final moved = moveRing(_outline, at);
        _outline
          ..clear()
          ..addAll(moved);
      } else {
        _outline[_dragNode!] = at;
      }
    });
  }

  void _pointerUp(PointerEvent e) {
    if (e.pointer != _dragPointer) return;
    setState(() {
      _dragNode = null;
      _dragPointer = null;
      _finger = null;
    });
  }
  final _outline = <LatLng>[];
  var _saving = false;

  /// Outline by a preset shape (drag, resize, rotate) instead of taps.
  var _shapeTool = true;
  var _shapeScale = 1.0, _shapeTurn = 0.0;

  var _style = MapStyle.outdoor;

  /// Where you last tapped empty map: offers "Add a place here".
  LatLng? _tapped;

  /// How much of the screen the near-me sheet covers, so the logo and the
  /// buttons sit just above it.
  var _sheet = 0.14;
  final _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _locate(move: true);
  }

  @override
  void dispose() {
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate({bool move = false}) async {
    setState(() => _locating = true);
    final r = await widget.locator.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _me = r.at ?? _me;
      _locateProblem = r.problem;
    });
    if (move && r.at != null) _map.move(_ll(r.at!), 14);
  }

  void _show(Place p, {bool move = true}) {
    final at = p.geometry?.centre ?? _parentCentre(p);
    if (move && at != null) _map.move(_ll(at), p.kind.index >= PlaceKind.boulder.index ? 17 : 15);
        final e = widget.editor;
    if (p.kind == PlaceKind.boulder && e != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BoulderScreen(
            tree: () => widget.places,
            boulderId: p.id,
            editor: e,
            onShowOnMap: _show,
            onEditShape: _editShape,
            onDelete: _delete,
          ),
        ),
      );
      return;
    }
    showClimbPlaceSheet(
      context,
      widget.places,
      p,
      onShowOnMap: _show,
      onAddProblem: e == null ? null : _addProblem,
      editor: e,
      canDelete: (x) => canEdit(e, x.id),
      onDelete: e == null ? null : _delete,
            onEditShape: e == null ? null : _editShape,
      onOpenBoulder: e == null ? null : (b) => _show(b, move: false),
    );
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  bool _checkSignedIn() {
    final e = widget.editor;
    if (e == null) {
      _say("This build has no server keys, so places can't be shared.");
      return false;
    }
    if (!e.signedIn) {
      _say('Sign in on the Friends tab to add places (new accounts wait to be let in).');
      return false;
    }
    return true;
  }

  Future<void> _addProblem(Place boulder) async {
    if (!_checkSignedIn()) return;
    final p = await showNewProblemSheet(context, boulder, widget.editor!.newId(), number: nextProblemNumber(widget.places, boulder.id), tree: widget.places);
    if (p == null || !mounted) return;
    final err = await widget.editor!.save(p);
    if (!mounted) return;
    if (err != null) return _say(err);
    _say('Saved ${p.name}.');
    final back = widget.places[boulder.id];
    if (back != null) _show(back, move: false);
  }

  Future<void> _delete(Place p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text('It disappears for everyone. Places inside it stay, without a parent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final err = await widget.editor!.delete(p);
    if (mounted) _say(err ?? 'Deleted ${p.name}.');
  }

  /// Adding starts where the map is: you often add boulders from home.
  /// "My GPS" in the banner jumps to where you are.
  void _startAdding() {
    if (!_checkSignedIn()) return;
    setState(() {
      _mode = _Mode.spot;
      _outline.clear();
      _tapped = null;
    });
  }

  Future<void> _addAt(LatLng at) async {
    if (!_checkSignedIn()) return;
    setState(() => _tapped = null);
    _map.move(_ll(at), math.max(_map.camera.zoom, 18));
    await _chosen(at);
  }

  /// A tap on the map: inside a place's outline opens it; on empty map it
  /// offers to add a place there (tap again elsewhere to dismiss).
  void _tapMap(LatLng at) {
        if (_mode == _Mode.outline) {
      if (!_shapeTool && !_pressedNode) setState(() => _outline.add(at));
      return;
    }
    if (_mode != _Mode.browse) return;
    for (final p in placesOnMap(widget.places, _filter).reversed) {
      if (p.geometry case PolygonGeometry(:final ring) when pointInPolygon(at, ring)) {
        setState(() => _tapped = null);
        return _show(p, move: false);
      }
    }
    setState(() => _tapped = _tapped == null ? at : null);
  }

  void _useShape(bool shape) => setState(() {
    _shapeTool = shape;
    _outline.clear();
    if (shape) {
      _shapeScale = 1;
      _shapeTurn = 0;
      _outline.addAll(presetShape(_spot ?? _ours(_map.camera.center)));
    }
  });

  void _undoPoint() => setState(_outline.removeLast);

  void _set(VoidCallback f) => setState(f);

  void _cancelAdding() => setState(() {
    _mode = _Mode.browse;
    _outline.clear();
    _draft = null;
    _reshaping = null;
  });

  /// Changes a place's outline: starts from its own (or a shape around its
  /// point), on the aerial map when it was the plain one.
  void _editShape(Place p) {
    if (!_checkSignedIn()) return;
    final g = p.geometry;
    final at = g?.centre ?? _ours(_map.camera.center);
    _map.move(_ll(at), math.max(_map.camera.zoom, 19));
    setState(() {
      _reshaping = p;
      _spot = at;
      _draft = (kind: p.kind, name: p.name, parentId: p.parentId, outline: true);
      _mode = _Mode.outline;
      _shapeScale = 1;
      _shapeTurn = 0;
      _outline.clear();
      if (g is PolygonGeometry) {
        _shapeTool = false; // its own points, draggable
        _outline.addAll(g.ring);
      } else {
        _shapeTool = true;
        _outline.addAll(presetShape(at));
      }
    });
  }

  Future<void> _spotChosen() => _chosen(_ours(_map.camera.center));

  Future<void> _chosen(LatLng at) async {
    final d = await showNewPlaceSheet(context, widget.places, at);
    if (d == null || !mounted) return;
    _spot = at;
    _draft = d;
    if (d.outline) {
      setState(() => _mode = _Mode.outline);
      _useShape(true);
    } else {
      await _saveNew(PointGeometry(at));
    }
  }

  Future<void> _saveNew(PlaceGeometry g) async {
    final d = _draft!, e = widget.editor!;
    if (_reshaping case final r?) {
      setState(() => _saving = true);
      final changed = r.copyWith(geometry: g);
      final err = await e.save(changed);
      if (!mounted) return;
      setState(() => _saving = false);
      if (err != null) return _say(err);
      _cancelAdding();
      _say('Saved the shape of ${r.name}.');
      return;
    }
    final place = Place(
      id: e.newId(),
      parentId: d.parentId,
      kind: d.kind,
      name: d.name,
      geometry: g,
      indoor: d.kind == PlaceKind.gymWall,
      gradeSystem: d.kind == PlaceKind.gymWall ? GradeSystem.gym('own') : GradeSystem.font,
    );
    setState(() => _saving = true);
    final err = await e.save(place);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) return _say(err);
    _cancelAdding();
    _say('Saved ${place.name}. Next: add problems and a topo photo.');
    // open it straight away, so adding problems and topos is one tap away
    await WidgetsBinding.instance.endOfFrame; // the map has the new place after this frame
    if (!mounted) return;
    _show(widget.places[place.id] ?? place, move: false);
  }

  /// The lowest button's distance from the bottom: just above the sheet.
  double _fabBase(BuildContext context) => _mode == _Mode.browse ? MediaQuery.sizeOf(context).height * _sheet + 40 : 24;

  LatLng? _parentCentre(Place p) {
    for (final a in widget.places.pathTo(p.id).reversed) {
      if (a.geometry != null) return a.geometry!.centre;
    }
    return null;
  }

  Future<void> _pickGrades() async {
    var range = RangeValues(_filter.minRung.toDouble(), _filter.maxRung.toDouble());
    final picked = await showModalBottomSheet<RangeValues>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Font grades ${kGradeLadder[range.start.round()]} – ${kGradeLadder[range.end.round()]}', style: Theme.of(context).textTheme.titleMedium),
              RangeSlider(
                values: range,
                min: 0,
                max: PlaceFilter.topRung.toDouble(),
                divisions: PlaceFilter.topRung,
                labels: RangeLabels(kGradeLadder[range.start.round()], kGradeLadder[range.end.round()]),
                onChanged: (v) => set(() => range = v),
              ),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, const RangeValues(0, PlaceFilter.topRung + 0.0)), child: const Text('Any grade')),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, range), child: const Text('Show')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _filter = _filter.copyWith(minRung: picked.start.round(), maxRung: picked.end.round()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = placesOnMap(widget.places, _filter);
    final near = nearMe(widget.places, _me ?? _centre, _filter);
    return Stack(
      children: [
                Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: FlutterMap(
          key: _mapKey,
          mapController: _map,
          options: MapOptions(
            interactionOptions: InteractionOptions(
              flags: _dragNode != null ? InteractiveFlag.none : InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            initialCenter: _ll(widget.start),
            initialZoom: 13,
            minZoom: 5,
            maxZoom: 21,
            backgroundColor: const Color(0xFFE8E4DA),
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture) setState(() => _centre = _ours(pos.center));
            },
            onTap: (_, at) => _tapMap(_ours(at)),
          ),
          children: [
            if (widget.tiles.hasKey)
              TileLayer(
                urlTemplate: widget.tiles.urlFor(_style),
                maxNativeZoom: 19,
                additionalOptions: {'key': widget.tiles.mapyKey},
                userAgentPackageName: 'app.hibi.climb',
                tileProvider: NetworkTileProvider(
                  cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
                    cacheDirectory: widget.cacheDirectory,
                    maxCacheSize: 200000000,
                    tileKeyGenerator: MapTiles.cacheKey,
                  ),
                ),
              ),
            PolygonLayer(
              polygons: [
                for (final p in shown)
                  if (p.geometry case PolygonGeometry(:final ring))
                    Polygon(points: [for (final v in ring) _ll(v)], color: cs.primary.withValues(alpha: 0.18), borderColor: cs.primary, borderStrokeWidth: 2),
                if (_mode == _Mode.outline && _outline.length >= 3)
                  Polygon(
                    points: [for (final v in _outline) _ll(v)],
                    color: cs.tertiary.withValues(alpha: 0.3),
                    borderColor: cs.tertiary,
                    borderStrokeWidth: 3,
                  ),
              ],
            ),
            if (_mode == _Mode.outline && _outline.length == 2)
              PolylineLayer(
                polylines: [
                  Polyline(points: [for (final v in _outline) _ll(v)], color: cs.tertiary, strokeWidth: 3),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final p in shown)
                  if (p.geometry != null)
                    Marker(
                      point: _ll(p.geometry!.centre),
                      width: p.geometry is PolygonGeometry ? 24 : 34,
                      height: p.geometry is PolygonGeometry ? 24 : 34,
                      child: _PlaceMarker(place: p, onTap: () => _show(p)),
                    ),
                if (_tapped != null && _mode == _Mode.browse)
                  Marker(
                    point: _ll(_tapped!),
                    width: 36,
                    height: 36,
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(child: Icon(Icons.place, color: cs.tertiary, size: 36)),
                  ),
                if (_me != null) Marker(point: _ll(_me!), width: 22, height: 22, child: const _MeDot()),
                if (_mode == _Mode.outline) ...[
                  if (_spot != null)
                    Marker(
                      point: _ll(_spot!),
                      width: 14,
                      height: 14,
                      child: Icon(Icons.close, size: 14, color: cs.tertiary),
                    ),
                  for (var i = 0; i < _outline.length; i++)
                    Marker(
                      point: _ll(_outline[i]),
                      width: 36,
                      height: 36,
                                            child: IgnorePointer(
                        child: Center(
                          child: Container(
                            width: _dragNode == i ? 24 : 18,
                            height: _dragNode == i ? 24 : 18,
                            decoration: BoxDecoration(
                              color: _dragNode == i ? Colors.white : cs.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(color: _dragNode == i ? cs.tertiary : Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_outline.length >= 3)
                    Marker(
                      point: _ll(ringCentre(_outline)),
                      width: 44,
                      height: 44,
                                            child: IgnorePointer(
                        child: Icon(
                          Icons.open_with,
                          color: cs.tertiary,
                          size: 28,
                          shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
                        ),
                      ),
                    ),
                ],
              ],
            ),
                        _MapCredit(hasTiles: widget.tiles.hasKey, bottom: _mode == _Mode.browse ? MediaQuery.sizeOf(context).height * _sheet + 4 : 8),
          ],
        ),
        ),
        if (_finger != null && _dragNode != null) _magnifier(context, _finger!),
        if (_mode == _Mode.spot)
          IgnorePointer(
            child: Center(
              child: Icon(
                Icons.add,
                size: 44,
                color: cs.tertiary,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ),
        if (_mode != _Mode.browse)
          SafeArea(
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: _addBanner(context)),
          )
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SearchBar(
                    controller: _search,
                    hintText: 'Search crags, boulders, problems',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_filter.query.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() {
                            _search.clear();
                            _filter = _filter.copyWith(query: '');
                          }),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                    onChanged: (q) => setState(() => _filter = _filter.copyWith(query: q)),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final w in ClimbWhere.values) ...[
                          ChoiceChip(
                            label: Text(switch (w) {
                              ClimbWhere.all => 'All',
                              ClimbWhere.outdoor => 'Outdoor',
                              ClimbWhere.indoor => 'Indoor',
                            }),
                            selected: _filter.where == w,
                            onSelected: (_) => setState(() => _filter = _filter.copyWith(where: w)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        ActionChip(
                          avatar: const Icon(Icons.tune, size: 18),
                          label: Text(_filter.anyGrade ? 'Any grade' : '${kGradeLadder[_filter.minRung]}–${kGradeLadder[_filter.maxRung]}'),
                          onPressed: _pickGrades,
                        ),
                      ],
                    ),
                  ),
                  if (!widget.tiles.hasKey)
                    const _Notice('No map key in this build, so there is no background map. Build with --dart-define-from-file (see apps/climb/README.md).'),
                  if (_locateProblem != null) _Notice(_locateProblem!),
                  if (widget.notice != null) _Notice(widget.notice!),
                ],
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: _fabBase(context) + 100,
          child: PopupMenuButton<MapStyle>(
            tooltip: 'Map type',
            initialValue: _style,
            onSelected: (s) => setState(() => _style = s),
            itemBuilder: (_) => [for (final s in MapStyle.values) PopupMenuItem(value: s, child: Text(s.label))],
            child: IgnorePointer(
              child: FloatingActionButton.small(heroTag: 'layers', onPressed: () {}, child: const Icon(Icons.layers_outlined)),
            ),
          ),
        ),
        if (_mode == _Mode.browse && widget.editor != null)
          Positioned(
            right: 12,
            bottom: _fabBase(context) + 50,
            child: FloatingActionButton.small(
              heroTag: 'add',
              tooltip: 'Add a place',
              onPressed: _startAdding,
              child: const Icon(Icons.add_location_alt_outlined),
            ),
          ),
        Positioned(
          right: 12,
          bottom: _fabBase(context),
          child: FloatingActionButton.small(
            heroTag: 'locate',
            tooltip: 'Where am I',
            onPressed: _locating ? null : () => _locate(move: true),
            child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
          ),
        ),
        if (_mode == _Mode.browse)
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() => _sheet = n.extent);
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.14,
              minChildSize: 0.08,
              maxChildSize: 0.85,
              builder: (context, scroll) => Material(
                color: cs.surface,
                elevation: 8,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(_me != null ? 'Near you' : 'Near the map centre', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (near.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here matches. Try another filter.')),
                    for (final r in near)
                      ListTile(
                        leading: Icon(placeIcon(r.place)),
                        title: Text(r.place.name),
                        subtitle: Text(
                          [
                            kindLabel(r.place.kind),
                            if (gradeSpan(widget.places, r.place.id) case final g when g.isNotEmpty) g,
                            if (widget.places[r.place.parentId ?? ''] case final parent?) parent.name,
                          ].join(' · '),
                        ),
                        trailing: Text(distanceLabel(r.metres)),
                        onTap: () => _show(r.place),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_tapped != null && _mode == _Mode.browse)
          Positioned(
            left: 12,
            right: 64,
            bottom: MediaQuery.sizeOf(context).height * _sheet + 8,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _addAt(_tapped!),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add a place here'),
                      ),
                    ),
                    IconButton(tooltip: 'Close', onPressed: () => setState(() => _tapped = null), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _Mode { browse, spot, outline }

extension on _ClimbMapScreenState {
  /// A round lens above the finger showing the map under it, twice as big,
  /// with a cross at the exact spot (below the finger near the top).
  Widget _magnifier(BuildContext context, Offset finger) {
    const size = 120.0, gap = 110.0;
    final above = finger.dy > size + gap;
    final centre = finger + Offset(0, above ? -gap : gap);
    return Positioned(
      left: centre.dx - size / 2,
      top: centre.dy - size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(size, size),
          magnificationScale: 2.5,
          focalPointOffset: Offset(0, above ? gap : -gap),
          decoration: const MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
            shadows: [BoxShadow(blurRadius: 8, color: Colors.black54)],
          ),
          child: Center(child: Icon(Icons.add, size: 22, color: Theme.of(context).colorScheme.tertiary)),
        ),
      ),
    );
  }
}

extension on _ClimbMapScreenState {
  Widget _addBanner(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final spot = _mode == _Mode.spot;
    final n = _outline.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(spot ? 'Where is it?' : 'Outline of ${_draft?.name ?? 'the boulder'}', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              spot
                  ? 'Move the map so the + is on the spot, or use your GPS.'
                  : _shapeTool
                  ? 'Drag a corner to fit the shape, the cross in the middle to move it. A magnifier shows what is under your finger.'
                  : "Tap around the boulder's edge, point by point; drag a point to fix it. $n ${n == 1 ? 'point' : 'points'}${n < 3 ? ', at least 3' : ''}.",
            ),
            if (!spot) ...[
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Shape', maxLines: 1, softWrap: false), icon: Icon(Icons.crop_square)),
                  ButtonSegment(value: false, label: Text('Tap points', maxLines: 1, softWrap: false), icon: Icon(Icons.touch_app_outlined)),
                ],
                selected: {_shapeTool},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _useShape(s.first),
              ),
              if (_shapeTool && n >= 3) ...[
                Row(
                  children: [
                    const SizedBox(width: 56, child: Text('Size')),
                    Expanded(
                      child: Slider(
                        value: _shapeScale,
                        min: 0.25,
                        max: 5,
                        onChanged: (v) => _set(() {
                          final scaled = scaleRing(_outline, v / _shapeScale);
                          _outline
                            ..clear()
                            ..addAll(scaled);
                          _shapeScale = v;
                        }),
                      ),
                    ),
                    Text('${ringWidthMetres(_outline).round()} m'),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 56, child: Text('Turn')),
                    Expanded(
                      child: Slider(
                        value: _shapeTurn,
                        min: 0,
                        max: 180,
                        onChanged: (v) => _set(() {
                          final turned = rotateRing(_outline, v - _shapeTurn);
                          _outline
                            ..clear()
                            ..addAll(turned);
                          _shapeTurn = v;
                        }),
                      ),
                    ),
                    Text('${_shapeTurn.round()}°'),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Oval'),
                      onPressed: () => _set(
                        () => _outline
                          ..clear()
                          ..addAll(rotateRing(scaleRing(presetShape(ringCentre(_outline)), _shapeScale), _shapeTurn)),
                      ),
                    ),
                    ActionChip(
                      label: const Text('Rectangle'),
                      onPressed: () => _set(
                        () => _outline
                          ..clear()
                          ..addAll(rotateRing(scaleRing(presetShape(ringCentre(_outline), oval: false), _shapeScale), _shapeTurn)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: _saving ? null : _cancelAdding, child: const Text('Cancel')),
                if (spot) ...[
                  OutlinedButton.icon(
                    onPressed: _locating
                        ? null
                        : () async {
                            await _locate();
                            if (_me != null) _map.move(_ll(_me!), 19);
                          },
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('My GPS'),
                  ),
                  FilledButton(onPressed: _spotChosen, child: const Text('Here')),
                ] else ...[
                  if (!_shapeTool) OutlinedButton(onPressed: n == 0 || _saving ? null : _undoPoint, child: const Text('Undo')),
                  FilledButton(
                    onPressed: n < 3 || _saving ? null : () => _saveNew(PolygonGeometry(List.of(_outline))),
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({required this.place, required this.onTap});
  final Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final indoor = place.indoor;
    return Semantics(
      button: true,
      label: place.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: indoor ? cs.tertiary : cs.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
          child: Icon(placeIcon(place), size: place.kind == PlaceKind.boulder ? 12 : 18, color: indoor ? cs.onTertiary : cs.onPrimary),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF2F7DF6),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
    ),
  );
}

/// Mapy.com's logo and copyright (their terms say they must stay visible),
/// and OpenStreetMap's for the imported places.
class _MapCredit extends StatelessWidget {
  const _MapCredit({required this.hasTiles, required this.bottom});
  final bool hasTiles;
  final double bottom;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Padding(
      padding: EdgeInsets.only(left: 8, bottom: bottom),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTiles)
            GestureDetector(
              onTap: () => launchUrl(Uri.https('mapy.com', '/')),
              child: SvgPicture.network(MapTiles.logoUrl, height: 22, placeholderBuilder: (_) => const Text('Mapy.com')),
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: Colors.white70,
            child: Text([if (hasTiles) MapTiles.mapyCopyright, MapTiles.osmCopyright].join(' · '), style: const TextStyle(fontSize: 10, color: Colors.black87)),
          ),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(padding: const EdgeInsets.all(10), child: Text(text)),
  );
}
