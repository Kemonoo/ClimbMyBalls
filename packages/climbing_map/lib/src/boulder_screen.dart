part of '../climbing_map.dart';

/// A boulder's own page: its sections' photos on top (swipe through them,
/// tap one to open it), then every route on the boulder, boulders and rope
/// routes in two tabs, with a search. Actions sit in the top bar's menu to
/// leave room for the routes.
class BoulderScreen extends StatefulWidget {
  const BoulderScreen({super.key, required this.tree, required this.boulderId, required this.editor, this.onShowOnMap, this.onEditShape, this.onDelete});

  /// The places as they are now (they change after saving).
  final PlaceTree Function() tree;
  final String boulderId;
  final PlaceEditor editor;
  final ValueChanged<Place>? onShowOnMap, onEditShape, onDelete;

  @override
  State<BoulderScreen> createState() => _BoulderScreenState();
}

enum _BoulderAction { map, mapy, rename, shape, guide, delete }

class _BoulderScreenState extends State<BoulderScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _search = TextEditingController();
  final _pages = PageController();
  var _page = 0;
  String? _open;
  var _filter = const RouteFilter();
  var _sort = RouteSort.grade;
  Map<String, RouteSummary> _summaries = const {};

  @override
  void initState() {
    super.initState();
    showCommunity.addListener(_redraw);
    showNewRoutes.addListener(_redraw);
    _loadSummaries();
  }

  void _redraw() => setState(() {});

  /// What people think of each route here and which you topped, for the
  /// filters and the ticks on the rows.
  Future<void> _loadSummaries() async {
    if (!_e.signedIn) return;
    final routes = {
      for (final p in _tree.childrenOf(widget.boulderId))
        if (p.kind == PlaceKind.problem) p.id: p,
    };
    final ids = routes.keys.toList();
    try {
      await _e.loadStars(StarOn.place, ids);
      final r = await Future.wait([_e.opinionsOn(ids), _e.toppedByMe(), _e.ascentCounts(ids)]);
      if (!mounted) return;
      setState(
        () => _summaries = routeSummaries(
          ids,
          r[0] as List<(String, Opinion)>,
          r[1] as Set<String>,
          _e.me,
          routes: routes,
          stars: {for (final id in ids) id: _e.starsOf(StarOn.place, id)},
          ascents: r[2] as Map<String, ({int tops, int flashes})>,
        ),
      );
    } catch (_) {} // the list works without them
  }

  Future<void> _filters() async {
    final f = await showRouteFilterSheet(context, _filter, rope: _tabs.index == 1);
    if (f != null && mounted) setState(() => _filter = f);
  }

  @override
  void dispose() {
    showCommunity.removeListener(_redraw);
    showNewRoutes.removeListener(_redraw);
    _tabs.dispose();
    _search.dispose();
    _pages.dispose();
    super.dispose();
  }

  PlaceTree get _tree => widget.tree();
  PlaceEditor get _e => widget.editor;

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _openSection(Place b, Topo t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopoScreen(tree: _tree, boulder: b, topo: t, editor: _e),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openRoute(Place b, Place p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteScreen(tree: _tree, boulder: b, problem: p, editor: _e),
      ),
    );
    if (mounted) setState(() {});
    await _loadSummaries();
  }

  Future<void> _addSection(Place b, bool camera) async {
    if (!_e.signedIn) return _say('Sign in on the Friends tab to add sections.');
    final sections = _e.toposOf(b.id);
    String title(Topo t) => t.name.isNotEmpty ? t.name : 'Section ${sections.indexOf(t) + 1}';
    // most routes fit a photo that's already here (#519); a new one has a place
    final (String, Topo?, Topo?)? where = sections.isEmpty
        ? ('new', null, null)
        : await showModalBottomSheet<(String, Topo?, Topo?)>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (context) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(
                      title: Text('Draw on a photo that is here'),
                      subtitle: Text('Usually the best: add your route and any letters it needs to an existing photo.'),
                    ),
                    for (final s in sections)
                      ListTile(leading: const Icon(Icons.draw_outlined), title: Text(title(s)), onTap: () => Navigator.pop(context, ('draw', s, null))),
                    const Divider(),
                    const ListTile(title: Text('Or a new photo')),
                    ListTile(
                      leading: const Icon(Icons.add_a_photo_outlined),
                      title: const Text('Another part of the boulder'),
                      onTap: () => Navigator.pop(context, ('new', null, null)),
                    ),
                    for (var i = 0; i + 1 < sections.length; i++)
                      ListTile(
                        leading: const Icon(Icons.compare_arrows),
                        title: Text('Between ${title(sections[i])} and ${title(sections[i + 1])}'),
                        onTap: () => Navigator.pop(context, ('between', sections[i], sections[i + 1])),
                      ),
                    for (final s in sections)
                      ListTile(
                        leading: const Icon(Icons.threesixty),
                        title: Text('${title(s)} from another angle'),
                        onTap: () => Navigator.pop(context, ('angle', s, null)),
                      ),
                  ],
                ),
              ),
            ),
          );
    if (where == null || !mounted) return;
    final (kind, a, z) = where;
    if (kind == 'draw') {
      await Navigator.of(context).push<Topo>(
        MaterialPageRoute(builder: (_) => TopoEditorScreen(tree: _tree, boulder: b, topo: a!, editor: _e)),
      );
      if (mounted) setState(() {});
      return;
    }
    final photo = await _e.pickPhoto(camera: camera);
    if (photo == null || !mounted) return;
    final t = Topo(
      id: newTopoId(),
      placeId: b.id,
      photoPath: '',
      width: photo.width,
      height: photo.height,
      createdBy: _e.me,
      name: switch (kind) {
        'between' => '${title(a!)} / ${title(z!)}',
        'angle' => a!.name,
        _ => '',
      },
      angleOf: kind == 'angle' ? a!.id : null,
    );
    await Navigator.of(context).push<Topo>(
      MaterialPageRoute(
        builder: (_) => TopoEditorScreen(tree: _tree, boulder: b, topo: t, editor: _e, newPhoto: photo, reference: a),
      ),
    );
    if (mounted) setState(() {});
  }

  /// The editors' list (#520): proven community routes, added with a tap.
  Future<void> _candidates(List<Place> routes) async {
    final numbers = problemNumbers(_tree, widget.boulderId);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Proven community routes'),
                subtitle: Text("They join the guide by themselves once they beat its average route and are drawn on a guide photo through its letters. These haven't yet; add them if they belong."),
              ),
              for (final p in routes)
                ListTile(
                  leading: Text(p.grade, style: const TextStyle(fontWeight: FontWeight.w800)),
                  title: Text(displayName(p, numbers[p.id])),
                  subtitle: Text('by ${_e.nameOf(_e.createdBy(p.id)).isEmpty ? 'someone' : _e.nameOf(_e.createdBy(p.id))}'),
                  trailing: p.inGuide
                      ? const Icon(Icons.check)
                      : FilledButton(
                          onPressed: () async {
                            final err = await _e.addToGuide(p);
                            if (err != null) return _say(err);
                            set(() => routes[routes.indexOf(p)] = p.copyWith(inGuide: true));
                          },
                          child: const Text('Add', maxLines: 1, softWrap: false),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addProblem(Place b) async {
    if (!_e.signedIn) return _say('Sign in on the Friends tab to add routes.');
    final p = await showNewProblemSheet(context, b, _e.newId(), number: nextProblemNumber(_tree, b.id), tree: _tree);
    if (p == null || !mounted) return;
    final err = await _e.save(p);
    if (!mounted) return;
    if (err != null) return _say(err);
    await WidgetsBinding.instance.endOfFrame; // the places update after this frame
    if (mounted) setState(() {});
  }

  Future<void> _rename(Place b) async {
    final c = TextEditingController(text: b.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename boulder'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == b.name || !mounted) return;
    final err = await _e.save(b.copyWith(name: name));
    if (!mounted) return;
    if (err != null) return _say(err);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() {});
  }

  Future<void> _importGuide(Place b, String guide) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add the $guide guide to ${b.name}?'),
        content: const Text('Its sections and routes go on this boulder for everyone. Running it again only adds what is missing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _say('Adding the $guide guide… (uploads its photos)');
    final err = await _e.importGuide(guide, b);
    if (!mounted) return;
    _say(err ?? 'Added the $guide guide.');
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() {});
  }

  Future<void> _act(Place b, _BoulderAction a) async {
    switch (a) {
      case _BoulderAction.map:
        Navigator.pop(context);
        widget.onShowOnMap?.call(b);
      case _BoulderAction.mapy:
        final at = b.geometry?.centre;
        if (at != null) await launchUrl(MapTiles.mapyLink(at), mode: LaunchMode.externalApplication);
      case _BoulderAction.rename:
        await _rename(b);
      case _BoulderAction.shape:
        Navigator.pop(context);
        widget.onEditShape?.call(b);
      case _BoulderAction.guide:
        final guides = _e.guides;
        final g = guides.length == 1
            ? guides.single
            : await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: Text('Add a guide to ${b.name}'),
                  children: [for (final g in guides) SimpleDialogOption(onPressed: () => Navigator.pop(context, g), child: Text(g))],
                ),
              );
        if (g != null && mounted) await _importGuide(b, g);
      case _BoulderAction.delete:
        Navigator.pop(context);
        widget.onDelete?.call(b);
    }
  }

  List<Place> _routes(PlaceTree tree, String id, bool rope, Map<String, String> numbers) {
    final q = _search.text.trim().toLowerCase();
    return sortRoutes(
      [
        for (final p in tree.childrenOf(id))
          if (p.kind == PlaceKind.problem && p.isRope == rope && routeShown(p))
            if ((q.isEmpty || displayName(p, numbers[p.id]).toLowerCase().contains(q) || p.grade.toLowerCase() == q) && _filter.matches(p, _summaries[p.id])) p,
      ],
      _sort,
      summaries: _summaries,
      numbers: numbers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final b = tree[widget.boulderId];
    if (b == null) return const Scaffold(body: Center(child: Text('This boulder was deleted.')));
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sections = _e.toposOf(b.id);
    final numbers = problemNumbers(tree, b.id);
    final boulders = _routes(tree, b.id, false, numbers), rope = _routes(tree, b.id, true, numbers);
    final all = [
      for (final p in tree.childrenOf(b.id))
        if (p.kind == PlaceKind.problem && isCommunity(p)) p,
    ];
    final community = all.where((p) => p.proven).length, fresh = all.length - community;
    // proven community routes that didn't join the guide by themselves (#520)
    final waiting = mayVerify(_e, b.id) ? all.where((p) => p.proven).toList() : const <Place>[];
    final path = tree.pathTo(b.id);
    final mine = canEdit(_e, b.id);
    final photoH = sections.isEmpty ? 0.0 : _photoHeight(context, sections.first, share: 0.34);

    Widget list(List<Place> rows, String empty) => rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(empty, style: text.bodyMedium),
          )
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: rows.length + (community + fresh > 0 ? 1 : 0),
            separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, i) => i == rows.length
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(alignment: Alignment.centerLeft, child: CommunityChip(count: community, fresh: fresh)),
                  )
                : _RouteRow(
              problem: rows[i],
              number: numbers[rows[i].id] ?? '',
              summary: _summaries[rows[i].id],
              open: _open == rows[i].id,
              onOpen: () => _openRoute(b, rows[i]),
              onExpand: () => setState(() => _open = _open == rows[i].id ? null : rows[i].id),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(b.name, style: text.titleMedium, overflow: TextOverflow.ellipsis),
            Text(
              [
                if (path.length > 1) path[path.length - 2].name,
                '${boulders.length + rope.length} routes',
                '${sections.length} ${sections.length == 1 ? 'section' : 'sections'}',
              ].join(' · '),
              style: text.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_e.signedIn) ...[
            StarButton(editor: _e, kind: StarOn.place, id: b.id),
            FavouriteButton(editor: _e, kind: StarOn.place, id: b.id),
          ],
          OfflineButton(editor: _e, placeId: b.id, compact: true),
          PopupMenuButton<_BoulderAction>(
            tooltip: 'More',
            onSelected: (a) => _act(b, a),
            itemBuilder: (_) => [
              if (widget.onShowOnMap != null) const PopupMenuItem(value: _BoulderAction.map, child: Text('Show on map')),
              if (b.geometry != null) const PopupMenuItem(value: _BoulderAction.mapy, child: Text('Open in Mapy.com')),
              if (mine) const PopupMenuItem(value: _BoulderAction.rename, child: Text('Rename')),
              if (mine && widget.onEditShape != null) const PopupMenuItem(value: _BoulderAction.shape, child: Text('Edit shape on the map')),
              if (_e.isAdmin && _e.guides.isNotEmpty)
                PopupMenuItem(value: _BoulderAction.guide, child: Text(_e.guides.length == 1 ? 'Add the ${_e.guides.first} guide' : 'Add a guide')),
              if (mine && widget.onDelete != null) const PopupMenuItem(value: _BoulderAction.delete, child: Text('Delete boulder')),
            ],
          ),
        ],
      ),
      floatingActionButton: _e.signedIn
          ? FloatingActionButton.small(tooltip: 'Add route', onPressed: () => _addProblem(b), child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          if (sections.isNotEmpty)
            SizedBox(
              height: photoH,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: sections.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final t = sections[i];
                      return GestureDetector(
                        onTap: () => _openSection(b, t),
                        child: ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: t.aspect,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image(
                                    image: _e.photoOf(t),
                                    fit: BoxFit.fill,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: Colors.black26,
                                      child: Center(child: Text('Photo not loaded')),
                                    ),
                                  ),
                                  CustomPaint(painter: TopoPainter(guideView(t, tree, all: showCommunity.value), numbers: numbers)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${sections[math.min(_page, sections.length - 1)].name.isEmpty ? 'Section ${_page + 1}' : sections[math.min(_page, sections.length - 1)].name} · tap to open',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                            for (var i = 0; i < sections.length; i++)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.white : Colors.white38),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                for (var i = 0; i < sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(sections[i].name.isEmpty ? 'Section ${i + 1}' : sections[i].name),
                      onPressed: () => _openSection(b, sections[i]),
                    ),
                  ),
                if (_e.signedIn) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('New section'),
                      onPressed: () => _addSection(b, true),
                    ),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('From gallery'),
                    onPressed: () => _addSection(b, false),
                  ),
                ],
              ],
            ),
          ),
          if (waiting.isNotEmpty)
            Material(
              color: communityColor.withValues(alpha: 0.15),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.how_to_vote_outlined),
                title: Text('${waiting.length} proven community ${waiting.length == 1 ? 'route' : 'routes'} could join the guide'),
                subtitle: const Text('Topped and starred by 3 people. Tap to look and add.'),
                onTap: () => _candidates(waiting),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Search routes: name, number or grade',
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_search.clear)),
                    ),
                  ),
                ),
                PopupMenuButton<RouteSort>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort),
                  initialValue: _sort,
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: (_) => [for (final s in RouteSort.values) PopupMenuItem(value: s, child: Text(s.label))],
                ),
                IconButton(
                  tooltip: 'Filters',
                  onPressed: _filters,
                  icon: Badge(isLabelVisible: !_filter.isEmpty, label: Text('${_filter.active}'), child: const Icon(Icons.tune)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: TabBar(
              controller: _tabs,
              labelPadding: EdgeInsets.zero,
              tabs: [
                Tab(height: 36, text: 'Boulders ${boulders.length}'),
                Tab(height: 36, text: 'Rope ${rope.length}'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                list(boulders, _search.text.isEmpty && _filter.isEmpty ? 'No boulder problems yet. Add one with +.' : 'No boulder problems match.'),
                list(rope, _search.text.isEmpty && _filter.isEmpty ? 'No rope routes here.' : 'No rope routes match.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
