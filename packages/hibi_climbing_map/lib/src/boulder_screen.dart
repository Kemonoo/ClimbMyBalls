part of '../climbing_map.dart';

/// A boulder's own page: its sections' photos on top (swipe through them,
/// tap one to open it), then every route on the boulder, boulders and rope
/// routes in two tabs, with a search. Actions sit in the top bar's menu to
/// leave room for the routes.
class BoulderScreen extends StatefulWidget {
  const BoulderScreen({
    super.key,
    required this.tree,
    required this.boulderId,
    required this.editor,
    this.onShowOnMap,
    this.onEditShape,
    this.onDelete,
  });

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

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _pages.dispose();
    super.dispose();
  }

  PlaceTree get _tree => widget.tree();
  PlaceEditor get _e => widget.editor;

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _openSection(Place b, Topo t) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopoScreen(tree: _tree, boulder: b, topo: t, editor: _e)));
    if (mounted) setState(() {});
  }

  Future<void> _openRoute(Place b, Place p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteScreen(tree: _tree, boulder: b, problem: p, editor: _e)));
    if (mounted) setState(() {});
  }

  Future<void> _addSection(Place b, bool camera) async {
    if (!_e.signedIn) return _say('Sign in on the Friends tab to add sections.');
    final photo = await _e.pickPhoto(camera: camera);
    if (photo == null || !mounted) return;
    final t = Topo(id: newTopoId(), placeId: b.id, photoPath: '', width: photo.width, height: photo.height, createdBy: _e.me);
    await Navigator.of(context).push<Topo>(
      MaterialPageRoute(builder: (_) => TopoEditorScreen(tree: _tree, boulder: b, topo: t, editor: _e, newPhoto: photo)),
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
    _say('Adding the $guide guide… (uploads 4 photos)');
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
        for (final g in _e.guides) {
          await _importGuide(b, g);
        }
      case _BoulderAction.delete:
        Navigator.pop(context);
        widget.onDelete?.call(b);
    }
  }

  List<Place> _routes(PlaceTree tree, String id, bool rope, Map<String, String> numbers) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final p in tree.childrenOf(id))
        if (p.kind == PlaceKind.problem && p.isRope == rope)
          if (q.isEmpty || displayName(p, numbers[p.id]).toLowerCase().contains(q) || p.grade.toLowerCase() == q) p,
    ]..sort((a, b) {
      final c = gradeOrder(a.grade, a.gradeSystem).compareTo(gradeOrder(b.grade, b.gradeSystem));
      return c != 0 ? c : a.name.compareTo(b.name);
    });
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
    final path = tree.pathTo(b.id);
    final mine = canEdit(_e, b.id);
    final photoH = sections.isEmpty ? 0.0 : _photoHeight(context, sections.first, share: 0.34);

    Widget list(List<Place> rows, String empty) => rows.isEmpty
        ? Padding(padding: const EdgeInsets.all(16), child: Text(empty, style: text.bodyMedium))
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: rows.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, i) => _RouteRow(
              problem: rows[i],
              number: numbers[rows[i].id] ?? '',
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
              [if (path.length > 1) path[path.length - 2].name, '${boulders.length + rope.length} routes', '${sections.length} ${sections.length == 1 ? 'section' : 'sections'}'].join(' · '),
              style: text.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_BoulderAction>(
            tooltip: 'More',
            onSelected: (a) => _act(b, a),
            itemBuilder: (_) => [
              if (widget.onShowOnMap != null) const PopupMenuItem(value: _BoulderAction.map, child: Text('Show on map')),
              if (b.geometry != null) const PopupMenuItem(value: _BoulderAction.mapy, child: Text('Open in Mapy.com')),
              if (mine) const PopupMenuItem(value: _BoulderAction.rename, child: Text('Rename')),
              if (mine && widget.onEditShape != null) const PopupMenuItem(value: _BoulderAction.shape, child: Text('Edit shape on the map')),
              if (_e.isAdmin && _e.guides.isNotEmpty) PopupMenuItem(value: _BoulderAction.guide, child: Text('Add the ${_e.guides.first} guide')),
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
                                    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26, child: Center(child: Text('Photo not loaded'))),
                                  ),
                                  CustomPaint(painter: TopoPainter(t, numbers: numbers)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search routes: name, number or grade',
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: TabBar(
              controller: _tabs,
              labelPadding: EdgeInsets.zero,
              tabs: [Tab(height: 36, text: 'Boulders ${boulders.length}'), Tab(height: 36, text: 'Rope ${rope.length}')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                list(boulders, _search.text.isEmpty ? 'No boulder problems yet. Add one with +.' : 'No boulder problems match.'),
                list(rope, _search.text.isEmpty ? 'No rope routes here.' : 'No rope routes match.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
