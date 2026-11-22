part of '../climbing_map.dart';

/// A place's sheet: the path above it (tap to go up), what it is, its grades,
/// the places under it (tap to go down), and links to show it on the map or
/// open it in Mapy.com.
Future<void> showClimbPlaceSheet(
  BuildContext context,
  PlaceTree tree,
  Place start, {
  ValueChanged<Place>? onShowOnMap,
  ValueChanged<Place>? onAddProblem,
  bool Function(Place)? canDelete,
  ValueChanged<Place>? onDelete,
    ValueChanged<Place>? onEditShape,
  ValueChanged<Place>? onOpenBoulder,
  PlaceEditor? editor,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _PlaceSheet(
    tree: tree,
    start: start,
    onShowOnMap: onShowOnMap,
    onAddProblem: onAddProblem,
    canDelete: canDelete,
    onDelete: onDelete,
            onEditShape: onEditShape,
        onOpenBoulder: onOpenBoulder,
        editor: editor,
  ),
);

/// A problem's grade as shown: '7A+/B', '9+/10- UIAA', with ' ?' and the
/// start ('SD low').
String problemGradeLabel(Place p) => [
  if (p.grade.isNotEmpty) '${p.grade}${p.gradeSystem.isUiaa ? ' UIAA' : ''}${p.gradeUncertain ? ' ?' : ''}',
  if (startLabel(p).isNotEmpty) startLabel(p),
].join(' · ');

class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({
    required this.tree,
    required this.start,
    this.onShowOnMap,
    this.onAddProblem,
    this.canDelete,
    this.onDelete,
        this.onEditShape,
    this.onOpenBoulder,
    this.editor,
  });
    final ValueChanged<Place>? onEditShape;

  /// Opens a boulder's own page (the sheet closes).
  final ValueChanged<Place>? onOpenBoulder;
  final PlaceEditor? editor;
  final PlaceTree tree;
  final Place start;
  final ValueChanged<Place>? onShowOnMap;
  final ValueChanged<Place>? onAddProblem;
  final bool Function(Place)? canDelete;
  final ValueChanged<Place>? onDelete;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  late Place _p = widget.start;

  /// The list below ordered by stars (#518) instead of as it comes.
  var _byStars = false;

  Future<void> _sortByStars(List<Place> children) async {
    final e = widget.editor;
    if (e == null) return;
    setState(() => _byStars = !_byStars);
    if (_byStars) {
      await e.loadStars(StarOn.place, [for (final c in children) c.id]);
      if (mounted) setState(() {});
    }
  }
  late PlaceTree _tree = widget.tree;

  void _say(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));

  Future<void> _rename() async {
    final c = TextEditingController(text: _p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${kindLabel(_p.kind).toLowerCase()}'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _p.name || !mounted) return;
    final changed = _p.copyWith(name: name);
    final err = await widget.editor!.save(changed);
    if (!mounted) return;
    if (err != null) return _say(err);
    setState(() {
      _p = changed;
      _tree = PlaceTree([for (final x in _tree.all) x.id == changed.id ? changed : x]);
    });
  }

  Future<void> _openRoute(Place problem) async {
    final boulder = _tree[problem.parentId ?? ''] ?? _p;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteScreen(tree: _tree, boulder: boulder, problem: problem, editor: widget.editor!),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _importGuide(String guide) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add the $guide guide to ${_p.name}?'),
        content: const Text("Its sections (photos with lines) and routes go on this boulder for everyone. Run it once."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _say('Adding the $guide guide…');
    final err = await widget.editor!.importGuide(guide, _p);
    if (!mounted) return;
    _say(err ?? 'Added. Close and reopen this boulder to see it.');
    setState(() {});
  }

  LatLng? get _at {
    if (_p.geometry != null) return _p.geometry!.centre;
    for (final a in widget.tree.pathTo(_p.id).reversed) {
      if (a.geometry != null) return a.geometry!.centre;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final path = _tree.pathTo(_p.id);
    final above = path.length > 1 ? path.sublist(0, path.length - 1) : const <Place>[];
    final e = widget.editor;
    final children = [..._tree.childrenOf(_p.id)];
    if (_byStars && e != null) {
      children.sort((a, b) => e.starsOf(StarOn.place, b.id).compareTo(e.starsOf(StarOn.place, a.id)));
    }
    final span = gradeSpan(_tree, _p.id);
    final mayEdit = canEdit(widget.editor, _p.id);
    final numbers = _p.kind == PlaceKind.boulder || _p.kind == PlaceKind.sector ? problemNumbers(_tree, _p.id) : const <String, String>{};
    final at = _at;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (above.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final a in above) ...[
                  InkWell(
                    onTap: () => setState(() => _p = a),
                    child: Text(a.name, style: text.bodyMedium?.copyWith(color: cs.primary)),
                  ),
                  Text('  ›  ', style: text.bodyMedium?.copyWith(color: cs.outline)),
                ],
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(_p.kind == PlaceKind.problem ? displayName(_p) : _p.name, style: text.headlineSmall)),
              if (mayEdit && _p.kind != PlaceKind.problem)
                IconButton(tooltip: 'Rename', visualDensity: VisualDensity.compact, onPressed: _rename, icon: const Icon(Icons.edit_outlined, size: 20)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [kindLabel(_p.kind), if (_p.indoor) 'indoor', if (_p.kind == PlaceKind.problem) problemGradeLabel(_p) else if (span.isNotEmpty) span].join(' · '),
            style: text.bodyLarge,
          ),
          if (_p.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_p.note, style: text.bodyMedium),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (at != null && widget.onShowOnMap != null)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onShowOnMap!(_p);
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Show on map'),
                ),
              if (at != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(MapTiles.mapyLink(at), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Open in Mapy.com'),
                ),
              if (widget.onAddProblem != null && (_p.kind == PlaceKind.boulder || _p.kind == PlaceKind.sector))
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onAddProblem!(_p);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add problem'),
                ),
              if (mayEdit && widget.onEditShape != null && _p.kind.index >= PlaceKind.area.index && _p.kind != PlaceKind.problem)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEditShape!(_p);
                  },
                  icon: const Icon(Icons.pentagon_outlined),
                  label: const Text('Edit shape'),
                ),
              if (_p.kind == PlaceKind.problem && widget.editor != null)
                FilledButton.icon(onPressed: () => _openRoute(_p), icon: const Icon(Icons.open_in_full), label: const Text('Open route')),
              if (widget.editor != null && const {PlaceKind.area, PlaceKind.sector, PlaceKind.boulder, PlaceKind.gymWall}.contains(_p.kind))
                OfflineButton(key: ValueKey(_p.id), editor: widget.editor!, placeId: _p.id),
              if (e != null && e.signedIn && _p.kind != PlaceKind.country && _p.kind != PlaceKind.region) ...[
                StarButton(key: ValueKey('star${_p.id}'), editor: e, kind: StarOn.place, id: _p.id),
                FavouriteButton(key: ValueKey('fav${_p.id}'), editor: e, kind: StarOn.place, id: _p.id),
              ],
            ],
          ),
          if (widget.editor != null && (_p.kind == PlaceKind.boulder || _p.kind == PlaceKind.sector)) _topos(context),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(_childrenTitle(children), style: text.titleMedium)),
                if (e != null && e.signedIn && children.length > 1)
                  TextButton.icon(
                    onPressed: () => _sortByStars(children),
                    icon: Icon(_byStars ? Icons.star_rounded : Icons.sort, size: 18),
                    label: Text(_byStars ? 'Most stars' : 'Sort by stars', maxLines: 1, softWrap: false),
                  ),
              ],
            ),
            for (final c in children)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: c.kind == PlaceKind.problem,
                leading: c.kind == PlaceKind.problem
                    ? SizedBox(
                        width: 52,
                        child: Text(
                          c.grade,
                          textAlign: TextAlign.center,
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      )
                    : Icon(placeIcon(c)),
                title: Text(c.kind == PlaceKind.problem ? displayName(c, numbers[c.id]) : c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: c.kind == PlaceKind.problem
                    ? (startLabel(c).isEmpty && !c.isRope ? null : Text([if (c.isRope) 'rope', if (startLabel(c).isNotEmpty) startLabel(c)].join(' · ')))
                    : Text([kindLabel(c.kind), if (gradeSpan(_tree, c.id) case final g when g.isNotEmpty) g].join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e != null && e.starsOf(StarOn.place, c.id) > 0)
                      Text('★${e.starsOf(StarOn.place, c.id)}', style: text.labelMedium?.copyWith(color: Colors.amber.shade700)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () {
                  if (c.kind == PlaceKind.problem && widget.editor != null) {
                    _openRoute(c);
                  } else if (c.kind == PlaceKind.boulder && widget.onOpenBoulder != null) {
                    Navigator.pop(context);
                    widget.onOpenBoulder!(c);
                  } else {
                    setState(() => _p = c);
                  }
                },
              ),
          ],
          const SizedBox(height: 16),
          Text('Source: ${_p.source} · ${_p.licence}', style: text.bodySmall?.copyWith(color: cs.outline)),
          if (widget.onDelete != null && (widget.canDelete?.call(_p) ?? false) && _p.kind != PlaceKind.problem)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDelete!(_p);
                },
                icon: Icon(Icons.delete_outline, color: cs.error),
                label: Text('Delete ${kindLabel(_p.kind).toLowerCase()}', style: TextStyle(color: cs.error)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topos(BuildContext context) {
    final e = widget.editor!;
    final topos = e.toposOf(_p.id);
    Future<void> add(bool camera) async {
      if (!e.signedIn) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Sign in on the Friends tab to add topos.')));
        return;
      }
      final photo = await e.pickPhoto(camera: camera);
      if (photo == null || !context.mounted) return;
      final t = Topo(id: newTopoId(), placeId: _p.id, photoPath: '', width: photo.width, height: photo.height, createdBy: e.me);
      await Navigator.of(context).push<Topo>(
        MaterialPageRoute(
          builder: (_) => TopoEditorScreen(tree: _tree, boulder: _p, topo: t, editor: e, newPhoto: photo),
        ),
      );
      if (mounted) setState(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(topos.isEmpty ? 'Sections' : '${topos.length} ${topos.length == 1 ? 'section' : 'sections'}', style: Theme.of(context).textTheme.titleMedium),
        if (topos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'A section is a photo of one part of the boulder with its routes drawn on. Take one, then draw.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        if (topos.isNotEmpty)
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: topos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = topos[i];
                return InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TopoScreen(tree: _tree, boulder: _p, topo: t, editor: e),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 130 * t.aspect,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: e.photoOf(t),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                          ),
                          CustomPaint(painter: TopoPainter(guideView(t, _tree, all: showCommunity.value), numbers: problemNumbers(_tree, _p.id))),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Text(
                                [
                                  t.name.isEmpty ? 'Section ${i + 1}' : t.name,
                                  '${t.lines.length} ${t.lines.length == 1 ? 'route' : 'routes'}',
                                  if (bearingLabel(t.bearing).isNotEmpty) bearingLabel(t.bearing),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(onPressed: () => add(true), icon: const Icon(Icons.photo_camera_outlined), label: const Text('New section photo')),
            OutlinedButton.icon(onPressed: () => add(false), icon: const Icon(Icons.photo_library_outlined), label: const Text('From gallery')),
          ],
        ),
        if (e.isAdmin && _p.kind == PlaceKind.boulder)
          for (final g in e.guides)
            TextButton.icon(onPressed: () => _importGuide(g), icon: const Icon(Icons.menu_book_outlined), label: Text('Add the $g guide here')),
      ],
    );
  }

  String _childrenTitle(List<Place> cs) {
    final n = cs.length;
    return cs.every((c) => c.kind == PlaceKind.problem) ? '$n ${n == 1 ? 'problem' : 'problems'}' : '$n inside';
  }
}
