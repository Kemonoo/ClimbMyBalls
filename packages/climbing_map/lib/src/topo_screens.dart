part of '../climbing_map.dart';

/// A photo picked for a topo, already shrunk for upload.
class TopoPhoto {
  const TopoPhoto(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

/// The number shown for each problem on a boulder: its own `number` ('7',
/// '24b'), else its place in the list after the numbered ones.
Map<String, String> problemNumbers(PlaceTree tree, String boulderId) {
  final problems = [
    for (final p in tree.childrenOf(boulderId))
      if (p.kind == PlaceKind.problem) p,
  ];
  final out = <String, String>{};
  var next = 1;
  for (final p in problems) {
    if (p.number.isEmpty) continue;
    out[p.id] = p.number;
    final n = int.tryParse(RegExp(r'^\d+').stringMatch(p.number) ?? '');
    if (n != null && n >= next) next = n + 1;
  }
  for (final p in problems) {
    out.putIfAbsent(p.id, () => '${next++}');
  }
  return out;
}

int nextProblemNumber(PlaceTree tree, String boulderId) {
  var top = 0;
  for (final n in problemNumbers(tree, boulderId).values) {
    top = math.max(top, int.tryParse(RegExp(r'^\d+').stringMatch(n) ?? '') ?? 0);
  }
  return top + 1;
}

/// A problem's name with its number in front, as the guide writes it
/// ('11 pozdrav mesiacu'), without doubling a number already in the name.
String displayName(Place p, [String? number]) {
  final n = number ?? p.number;
  if (n.isEmpty || p.name.startsWith('$n ') || p.name == n) return p.name;
  return '$n ${p.name}';
}

String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

int _numberOrder(String n) => (int.tryParse(RegExp(r'^\d+').stringMatch(n) ?? '') ?? 99999) * 100 + (n.length > 0 ? n.codeUnitAt(n.length - 1) % 100 : 0);

enum _Sort { grade, number, name }

/// How tall the pinned photo is: its full height on the screen's width, but
/// at most [share] of the screen.
double _photoHeight(BuildContext context, Topo t, {double share = 0.42}) {
  final size = MediaQuery.sizeOf(context);
  return math.min(size.width / t.aspect, size.height * share);
}

/// A section: its photo pinned on top, the routes on it below, boulders and
/// rope routes in two tabs. Tap a line or a row's arrow to light it up and
/// read how it goes; tap a letter to see only the routes through it; tap a
/// row to open the route.
class TopoScreen extends StatefulWidget {
  const TopoScreen({super.key, required this.tree, required this.boulder, required this.topo, required this.editor});
  final PlaceTree tree;
  final Place boulder;
  final Topo topo;
  final PlaceEditor editor;

  @override
  State<TopoScreen> createState() => _TopoScreenState();
}

class _TopoScreenState extends State<TopoScreen> with SingleTickerProviderStateMixin {
  late Topo _topo = widget.topo;
  late PlaceTree _tree = widget.tree;
  String? _open; // expanded problem
  String? _mark; // tapped letter
  var _sort = _Sort.grade;
  var _original = false;
  late final _tabs = TabController(length: 2, vsync: this);
  final _rowKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Topo> get _sections {
    final all = widget.editor.toposOf(widget.boulder.id);
    return all.any((t) => t.id == _topo.id) ? all : [_topo, ...all];
  }

  String _sectionTitle(Topo t, int i) => t.name.isNotEmpty ? t.name : 'Section ${i + 1}';

  void _tapPhoto(TopoPoint p) {
    if (_original) return;
    final m = _topo.markAt(p, within: 0.035);
    if (m != null) {
      final label = _topo.marks[m].label;
      setState(() {
        _mark = _mark == label ? null : label;
        _open = null;
      });
      return;
    }
    final i = _topo.lineAt(p);
    if (i == null) {
      setState(() => _open = null);
      return;
    }
    final id = _topo.lines[i].problemId;
    final rope = _tree[id]?.isRope ?? false;
    setState(() {
      _open = id;
      _mark = null;
    });
    _tabs.animateTo(rope ? 1 : 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _rowKeys[id]?.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.1);
    });
  }

  Future<void> _openRoute(Place p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteScreen(tree: _tree, boulder: widget.boulder, problem: p, editor: widget.editor, topo: _topo),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _edit() async {
    final t = await Navigator.of(context).push<Topo>(
      MaterialPageRoute(
        builder: (_) => TopoEditorScreen(tree: _tree, boulder: widget.boulder, topo: _topo, editor: widget.editor),
      ),
    );
    if (t != null && mounted) setState(() => _topo = t);
  }

  List<(int, Place)> _routes(bool rope) {
    final through = _mark == null ? null : _topo.linesThrough(_mark!);
    final numbers = problemNumbers(_tree, widget.boulder.id);
    final rows = <(int, Place)>[];
    final seen = <String>{};
    for (var i = 0; i < _topo.lines.length; i++) {
      final p = _tree[_topo.lines[i].problemId];
      if (p == null || p.isRope != rope || !seen.add(p.id)) continue;
      if (through != null && !through.contains(i)) continue;
      rows.add((i, p));
    }
    int byGrade((int, Place) a, (int, Place) b) {
      final c = gradeOrder(a.$2.grade, a.$2.gradeSystem).compareTo(gradeOrder(b.$2.grade, b.$2.gradeSystem));
      return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
    }

    rows.sort(switch (_sort) {
      _Sort.grade => byGrade,
      _Sort.number => (a, b) => _numberOrder(numbers[a.$2.id] ?? '').compareTo(_numberOrder(numbers[b.$2.id] ?? '')),
      _Sort.name => (a, b) => a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase()),
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final numbers = problemNumbers(_tree, widget.boulder.id);
    final sections = _sections;
    final index = math.max(0, sections.indexWhere((t) => t.id == _topo.id));
    final boulders = _routes(false), rope = _routes(true);
    final openLine = _open == null ? null : _topo.lines.indexWhere((l) => l.problemId == _open);
    final lit = _mark != null ? _topo.linesThrough(_mark!) : {if (openLine != null && openLine >= 0) openLine};
    final shown = _original ? _topo.copyWith(lines: const [], marks: const []) : _topo;

    Widget list(List<(int, Place)> rows, String empty) => rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(empty, style: text.bodyMedium),
          )
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, k) {
              final (_, p) = rows[k];
              return _RouteRow(
                key: _rowKeys.putIfAbsent(p.id, GlobalKey.new),
                problem: p,
                number: numbers[p.id] ?? '',
                open: _open == p.id,
                onOpen: () => _openRoute(p),
                onExpand: () => setState(() {
                  _open = _open == p.id ? null : p.id;
                  _mark = null;
                }),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: PopupMenuButton<int>(
          tooltip: 'Sections',
          onSelected: (i) => setState(() {
            _topo = sections[i];
            _open = _mark = null;
            _original = false;
          }),
          itemBuilder: (_) => [
            for (var i = 0; i < sections.length; i++) CheckedPopupMenuItem(value: i, checked: i == index, child: Text(_sectionTitle(sections[i], i))),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_sectionTitle(_topo, index), style: text.titleMedium, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        widget.boulder.name,
                        if (sections.length > 1) '${index + 1} of ${sections.length}',
                        if (bearingLabel(_topo.bearing).isNotEmpty) 'faces ${bearingLabel(_topo.bearing)}',
                      ].join(' · '),
                      style: text.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (sections.length > 1) const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (_topo.originalPath.isNotEmpty)
            IconButton(
              tooltip: _original ? 'Our drawing' : "The guide's original",
              isSelected: _original,
              icon: const Icon(Icons.auto_stories_outlined),
              selectedIcon: const Icon(Icons.auto_stories),
              onPressed: () => setState(() => _original = !_original),
            ),
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.grade, child: Text('By grade')),
              PopupMenuItem(value: _Sort.number, child: Text('By number')),
              PopupMenuItem(value: _Sort.name, child: Text('By name')),
            ],
          ),
          if (canEditTopo(widget.editor, _topo)) IconButton(tooltip: 'Edit section', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: _photoHeight(context, _topo),
            child: ColoredBox(
              color: Colors.black,
              child: TopoCanvas(
                key: ValueKey('${_topo.id}$_original'),
                topo: shown,
                photo: widget.editor.photoOf(_topo, original: _original),
                lit: lit,
                litMark: _mark,
                numbers: numbers,
                onTap: _tapPhoto,
              ),
            ),
          ),
          if (_mark != null)
            Material(
              color: cs.secondaryContainer,
              child: InkWell(
                onTap: () => setState(() => _mark = null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text('Routes through $_mark: ${boulders.length + rope.length}', style: text.labelLarge)),
                      const Icon(Icons.close, size: 18),
                    ],
                  ),
                ),
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
                list(boulders, _mark != null ? 'No boulder problems through $_mark.' : 'No boulder problems on this section yet.'),
                list(rope, _mark != null ? 'No rope routes through $_mark.' : 'No rope routes on this section.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One route in a list: grade on the left, name in the middle, the start on
/// the right, and an arrow that opens how it goes.
class _RouteRow extends StatelessWidget {
  const _RouteRow({super.key, required this.problem, required this.number, required this.open, required this.onOpen, required this.onExpand, this.summary});
  final Place problem;

  /// Your tick and project flag, when known.
  final RouteSummary? summary;
  final String number;
  final bool open;
  final VoidCallback onOpen, onExpand;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = problem;
    final start = startLabel(p);
    return Material(
      color: open ? cs.secondaryContainer.withValues(alpha: 0.5) : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${p.grade}${p.gradeUncertain ? '?' : ''}',
                      textAlign: TextAlign.center,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Text(displayName(p, number), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge),
                  ),
                  if (start.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(start, style: text.labelMedium?.copyWith(color: cs.primary)),
                    ),
                  if (summary?.project ?? false)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: 'Your project',
                        child: Icon(Icons.flag, size: 18, color: Color(0xFFFF7EB6)),
                      ),
                    ),
                  if (summary?.topped ?? false)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: 'Topped',
                        child: Icon(Icons.check_circle, size: 18, color: Color(0xFF4CFF6A)),
                      ),
                    ),
                  IconButton(
                    tooltip: open ? 'Hide' : 'How it goes',
                    visualDensity: VisualDensity.compact,
                    onPressed: onExpand,
                    icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 12, 10),
              child: Text(p.note.isEmpty ? 'No description yet.' : p.note, style: text.bodyMedium),
            ),
        ],
      ),
    );
  }
}

/// One route: the photo with just its line (green start, arrow for a
/// top-out, circle for a finish at a hold), how it goes, ascents and
/// details.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.tree, required this.boulder, required this.problem, required this.editor, this.topo});
  final PlaceTree tree;
  final Place boulder;
  final Place problem;
  final PlaceEditor editor;
  final Topo? topo;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

const _votePink = Color(0xFFFF1A8C);
const _softGreen = Color(0xFF5CC46A);
const _hardRed = Color(0xFFE57388);
const _tickGreen = Color(0xFF4CFF6A);

String _outcomeWord(String o) => switch (o) {
  'flash' => 'Flash',
  'sent' => 'Top',
  _ => 'Try',
};

/// A route's page, like a gym app's: its line on the photo, then three tabs
/// (the route: grade votes, "how did it feel", stars, details; comments; who
/// topped it) and a bar at the bottom to log Flash, Top, Try or Repeat.
class _RouteScreenState extends State<RouteScreen> {
  late Place _p = widget.problem;
  late Topo? _topo = widget.topo != null && widget.topo!.lines.any((l) => l.problemId == widget.problem.id && l.points.isNotEmpty)
      ? widget.topo
      : _onTopos.where((t) => t.lines.any((l) => l.problemId == widget.problem.id && l.points.isNotEmpty)).firstOrNull ?? _onTopos.firstOrNull;
  List<Ascent>? _ascents;
  List<Opinion> _opinions = const [];
  List<RouteComment> _comments = const [];
  String? _error;
  var _busy = false;
  var _showRatings = false;
  final _comment = TextEditingController();

  List<Topo> get _onTopos => [
    for (final t in widget.editor.toposOf(widget.boulder.id))
      if (t.lines.any((l) => l.problemId == widget.problem.id)) t,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.editor.signedIn) return;
    try {
      final r = await Future.wait([widget.editor.ascentsOf(_p.id), widget.editor.opinionsOf(_p.id), widget.editor.commentsOf(_p.id)]);
      if (!mounted) return;
      setState(() {
        _ascents = r[0] as List<Ascent>;
        _opinions = r[1] as List<Opinion>;
        _comments = r[2] as List<RouteComment>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load this route. ($e)');
    }
  }

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Opinion? get _mine => _opinions.where((o) => o.userId == widget.editor.me).firstOrNull;

  /// Your ascents of this route, newest first.
  List<Ascent> get _myAscents => [
    for (final a in _ascents ?? const <Ascent>[])
      if (a.userId == widget.editor.me) a,
  ];

  Future<void> _log(String outcome) async {
    setState(() => _busy = true);
    final err = await widget.editor.logAscent(_p.id, outcome);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return _say(err);
    await _load();
  }

  /// Takes back your newest ascent.
  Future<void> _undo() async {
    final last = _myAscents.firstOrNull;
    if (last == null) return;
    final err = await widget.editor.removeAscent(last.id);
    if (err != null) return _say(err);
    await _load();
  }

  Future<void> _opinion({String? grade, int? stars, List<String>? tags, bool? project}) async {
    final m = _mine;
    final g = grade ?? m?.grade ?? '', s = stars ?? m?.stars ?? 0;
    final tg = tags ?? m?.tags ?? const <String>[], pr = project ?? m?.project ?? false;
    final me = widget.editor.me ?? '';
    // show it at once; the server catches up
    setState(
      () => _opinions = [
        for (final o in _opinions)
          if (o.userId != me) o,
        (userId: me, who: widget.editor.nameOf(me), grade: g, stars: s, tags: tg, project: pr),
      ],
    );
    final err = await widget.editor.setOpinion(_p.id, grade: g, stars: s, tags: tg, project: pr);
    if (err != null) {
      _say(err);
      await _load();
    }
  }

  Future<void> _post() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    final err = await widget.editor.addComment(_p.id, body);
    if (err != null) return _say(err);
    _comment.clear();
    await _load();
  }

  Future<void> _edit() async {
    final p = await showNewProblemSheet(context, widget.boulder, _p.id, existing: _p, tree: widget.tree);
    if (p == null || !mounted) return;
    final err = await widget.editor.save(p);
    if (!mounted) return;
    if (err != null) return _say(err);
    setState(() => _p = p);
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_p.name}?'),
        content: const Text('It disappears for everyone, with its lines on the photos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    for (final t in _onTopos) {
      await widget.editor.saveTopo(
        t.copyWith(
          lines: [
            for (final l in t.lines)
              if (l.problemId != _p.id) l,
          ],
        ),
      );
    }
    final err = await widget.editor.delete(_p);
    if (!mounted) return;
    if (err != null) return _say(err);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final t = _topo;
    final line = t == null ? -1 : t.lines.indexWhere((l) => l.problemId == p.id);
    final numbers = problemNumbers(widget.tree, widget.boulder.id);
    final sends = (_ascents ?? const <Ascent>[]).where((a) => a.outcome != 'tried').toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _votePink,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: FittedBox(
                    child: Text(
                      p.grade,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(displayName(p, numbers[p.id]), overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            if (canEdit(widget.editor, p.id)) ...[
              IconButton(tooltip: 'Edit route', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Delete route', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
            ],
          ],
        ),
        body: Column(
          children: [
            if (t != null)
              SizedBox(
                height: _photoHeight(context, t, share: 0.32),
                child: ColoredBox(
                  color: Colors.black,
                  child: TopoCanvas(topo: t, photo: widget.editor.photoOf(t), only: line >= 0 ? line : null, numbers: numbers),
                ),
              ),
            TabBar(
              tabs: [
                const Tab(child: Text('Route', maxLines: 1, softWrap: false)),
                Tab(child: Text(_comments.isEmpty ? 'Comments' : 'Comments ${_comments.length}', maxLines: 1, softWrap: false)),
                Tab(child: Text(sends.isEmpty ? 'Topped by' : 'Topped by ${sends.length}', maxLines: 1, softWrap: false)),
              ],
            ),
            Expanded(child: TabBarView(children: [_routeTab(context, t, line), _commentsTab(context), _toppedTab(context)])),
            _logBar(context),
          ],
        ),
      ),
    );
  }

  Widget _routeTab(BuildContext context, Topo? t, int line) {
    final text = Theme.of(context).textTheme;
    final p = _p;
    final scale = p.isRope ? GradeSystem.uiaa : GradeSystem.font;
    final mine = _mine;
    final chart = gradeVotes(p.grade, scale, [
      for (final o in _opinions)
        if (o.grade.isNotEmpty) o.grade,
    ]);
    final rated = [
      for (final o in _opinions)
        if (o.stars > 0) o,
    ];
    final avg = rated.isEmpty ? 0.0 : rated.map((o) => o.stars).reduce((a, b) => a + b) / rated.length;
    final tags = {
      for (final (t, n) in tagCounts([for (final o in _opinions) o.tags])) t.id: n,
    };
    final topped = _myAscents.any((a) => a.outcome != 'tried');
    final start = startLabel(p);
    final end = line >= 0 ? t!.lines[line].end : null;
    final added = widget.editor.createdAt(p.id);
    final by = widget.editor.nameOf(widget.editor.createdBy(p.id));
    final onTopos = _onTopos;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (chart != null) ...[
          Text('Grade votes', style: text.titleSmall),
          const SizedBox(height: 8),
          _VoteChart(chart: chart, mine: mine == null ? null : gradeStep(mine.grade, scale), scale: scale),
          const SizedBox(height: 18),
          Center(
            child: Text('How did it feel?', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          _FeelPicker(
            grade: p.grade,
            vote: mine?.grade ?? '',
            scale: scale,
            enabled: widget.editor.signedIn && topped,
            onVote: (g) => _opinion(grade: g),
          ),
          if (widget.editor.signedIn && !topped)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(child: Text('Log a Flash or a Top to vote.', style: text.bodySmall)),
            ),
          const Divider(height: 32),
        ],
        Text('What do you think of this route?', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                onPressed: widget.editor.signedIn ? () => _opinion(stars: mine?.stars == i ? 0 : i) : null,
                icon: Icon(i <= (mine?.stars ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, size: 34, color: Colors.amber),
              ),
          ],
        ),
        Card(
          margin: const EdgeInsets.only(top: 4),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(rated.isEmpty ? 'No ratings yet' : '★ ${avg.toStringAsFixed(1)} · ${rated.length} ${rated.length == 1 ? 'rating' : 'ratings'}'),
                trailing: rated.isEmpty ? null : Icon(_showRatings ? Icons.expand_less : Icons.expand_more),
                onTap: rated.isEmpty ? null : () => setState(() => _showRatings = !_showRatings),
              ),
              if (_showRatings)
                for (final o in rated)
                  ListTile(
                    dense: true,
                    title: Text(o.who.isEmpty ? 'Someone' : o.who),
                    trailing: Text('★' * o.stars, style: const TextStyle(color: Colors.amber)),
                  ),
            ],
          ),
        ),
        const Divider(height: 32),
        Text("What's it like?", style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('Tap what fits. The numbers are how many people said so.', style: text.bodySmall),
        for (final group in const ['Style', 'Wall', 'Holds']) ...[
          const SizedBox(height: 10),
          Text(group, style: text.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in routeTags.where((t) => t.group == group))
                FilterChip(
                  label: Text('${tag.label}${tags[tag.id] == null ? '' : ' ${tags[tag.id]}'}', maxLines: 1, softWrap: false),
                  selected: mine?.tags.contains(tag.id) ?? false,
                  onSelected: widget.editor.signedIn
                      ? (on) => _opinion(
                          tags: [
                            for (final x in mine?.tags ?? const <String>[])
                              if (x != tag.id) x,
                            if (on) tag.id,
                          ],
                        )
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (widget.editor.signedIn)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.flag_outlined),
            title: const Text('Project'),
            subtitle: const Text('A goal of yours. The boulder page can show only your projects.'),
            value: mine?.project ?? false,
            onChanged: (on) => _opinion(project: on),
          ),
        const Divider(height: 32),
        Text('Details', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          [
            '${p.isRope ? 'Rope · UIAA' : 'Boulder · Font'} · ${p.grade}${p.gradeUncertain ? ' ?' : ''}',
            if (start.isNotEmpty) 'Start: $start',
            if (end != null) end == TopoEnd.topOut ? 'Tops out' : 'Ends at a hold',
          ].join('\n'),
          style: text.bodyMedium,
        ),
        if (p.note.isNotEmpty) ...[const SizedBox(height: 8), Text(p.note, style: text.bodyLarge)],
        if (onTopos.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final o in onTopos)
                ChoiceChip(label: Text(o.name.isEmpty ? 'Section' : o.name), selected: o.id == t?.id, onSelected: (_) => setState(() => _topo = o)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          [
            'On ${widget.boulder.name}',
            if (added != null) 'Added ${_dmy(added.toLocal())}${by.isNotEmpty ? ' by $by' : ''}',
            if (p.source != 'manual') 'From ${p.source}',
          ].join('\n'),
          style: text.bodySmall,
        ),
      ],
    );
  }

  Widget _commentsTab(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = widget.editor.me;
    return Column(
      children: [
        Expanded(
          child: _comments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.editor.signedIn ? 'No comments yet. Beta, conditions, a broken hold?' : 'Sign in on the Friends tab to read and write comments.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final c in _comments)
                      ListTile(
                        title: Text('${c.who.isEmpty ? 'Someone' : c.who} · ${_dmy(c.at)}', style: text.labelMedium),
                        subtitle: Text(c.body, style: text.bodyLarge),
                        trailing: c.userId == me || widget.editor.isAdmin
                            ? IconButton(
                                tooltip: 'Remove comment',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () async {
                                  final err = await widget.editor.removeComment(c.id);
                                  if (err != null) return _say(err);
                                  await _load();
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        if (widget.editor.signedIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _comment,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Write a comment', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                IconButton(tooltip: 'Post comment', onPressed: _post, icon: const Icon(Icons.send)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _toppedTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = widget.editor.me;
    final ascents = _ascents ?? const <Ascent>[];
    if (!widget.editor.signedIn) return const Center(child: Text('Sign in on the Friends tab to see who topped it.'));
    if (ascents.isEmpty) return const Center(child: Text('Nobody has logged it yet.'));
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final a in ascents)
          ListTile(
            leading: Icon(switch (a.outcome) {
              'flash' => Icons.bolt,
              'sent' => Icons.check_circle_outline,
              _ => Icons.radio_button_unchecked,
            }, color: a.outcome == 'tried' ? cs.outline : _softGreen),
            title: Text(a.who.isEmpty ? 'Someone' : a.who),
            subtitle: Text('${_outcomeWord(a.outcome)} · ${_dmy(a.day)}${a.userId == mine ? ' · tap to change the date' : ''}'),
            onTap: a.userId != mine
                ? null
                : () async {
                    final day = await showDatePicker(
                      context: context,
                      initialDate: a.day,
                      firstDate: DateTime(2000),
                      lastDate: a.day.isAfter(DateTime.now()) ? a.day : DateTime.now(),
                      helpText: 'Day of the ascent',
                    );
                    if (day == null || !context.mounted) return;
                    final err = await widget.editor.setAscentDay(a.id, day);
                    if (err != null) return _say(err);
                    await _load();
                  },
            trailing: a.userId == mine
                ? IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () async {
                      final err = await widget.editor.removeAscent(a.id);
                      if (err != null) return _say(err);
                      await _load();
                    },
                  )
                : null,
          ),
      ],
    );
  }

  /// Flash, Top, Try, Repeat, with your ascents of this route above them.
  Widget _logBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!widget.editor.signedIn) {
      return Material(
        color: cs.surfaceContainerHigh,
        child: const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Sign in on the Friends tab to log, vote and comment.', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final mine = _myAscents.reversed.toList(); // oldest first, like a row of ticks
    final topped = mine.any((a) => a.outcome != 'tried');
    Widget button(String label, IconData icon, String outcome, {bool lit = false}) => Expanded(
      child: InkWell(
        onTap: _busy ? null : () => _log(outcome),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: lit ? const Color(0xFF1F5A2A) : cs.surfaceContainerHighest,
                child: Icon(icon, color: lit ? _tickGreen : cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );
    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final a in mine)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Tooltip(
                                  message: '${_outcomeWord(a.outcome)} · ${_dmy(a.day)}',
                                  child: CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.black,
                                    child: Icon(
                                      switch (a.outcome) {
                                        'flash' => Icons.bolt,
                                        'sent' => Icons.check,
                                        _ => Icons.circle,
                                      },
                                      size: a.outcome == 'tried' ? 6 : 15,
                                      color: a.outcome == 'tried' ? Colors.white : _tickGreen,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(tooltip: 'Undo your last log', onPressed: _undo, icon: const Icon(Icons.undo)),
                  ],
                ),
              ),
            Row(
              children: [
                button('Flash', Icons.bolt, 'flash', lit: mine.any((a) => a.outcome == 'flash')),
                button('Top', Icons.check, 'sent', lit: topped),
                button('Try', Icons.circle, 'tried'),
                if (topped) button('Repeat', Icons.add, 'sent'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The grades people voted, as bars around the route's own grade; your vote
/// is the grey top of its bar.
class _VoteChart extends StatelessWidget {
  const _VoteChart({required this.chart, required this.mine, required this.scale});
  final ({List<String> steps, List<int> counts, int at}) chart;
  final int? mine;
  final GradeSystem scale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lo = gradeStep(chart.steps.first, scale) ?? 0;
    final top = chart.counts.fold(1, (a, b) => a > b ? a : b);
    const h = 80.0;
    return SizedBox(
      height: h + 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < chart.steps.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (chart.counts[i] > 0) Text('${chart.counts[i]}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      height: chart.counts[i] == 0 ? 0 : h * chart.counts[i] / top,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (mine == lo + i)
                              SizedBox(
                                height: h / top,
                                child: const ColoredBox(color: Color(0xFF7A7A7A)),
                              ),
                            if (chart.counts[i] > (mine == lo + i ? 1 : 0)) const Expanded(child: ColoredBox(color: _votePink)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(height: 2, color: cs.outlineVariant),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(
                      chart.steps[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: i == chart.at ? FontWeight.w900 : FontWeight.w400,
                        color: i == chart.at ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Softer · how it felt · Harder: each tap moves your vote one grade.
class _FeelPicker extends StatelessWidget {
  const _FeelPicker({required this.grade, required this.vote, required this.scale, required this.enabled, required this.onVote});
  final String grade, vote;
  final GradeSystem scale;
  final bool enabled;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final steps = gradeSteps(scale);
    final at = gradeStep(grade, scale);
    final v = gradeStep(vote, scale);
    if (at == null) return const SizedBox.shrink();
    final diff = v == null ? null : v - at;
    final (word, color) = switch (diff) {
      null => ('Vote', Theme.of(context).colorScheme.outline),
      0 => ('Fair', Colors.white),
      < 0 => (diff < -1 ? 'Much softer' : 'Soft', _softGreen),
      _ => (diff > 1 ? 'Much harder' : 'Hard', _hardRed),
    };
    void move(int by) => onVote(steps[((v ?? at) + by).clamp(0, steps.length - 1)]);

    Widget side(String label, IconData icon, Color c, int by) => Column(
      children: [
        IconButton.outlined(
          tooltip: label,
          iconSize: 30,
          style: IconButton.styleFrom(
            side: BorderSide(color: c, width: 2.5),
            foregroundColor: c,
            fixedSize: const Size(56, 56),
          ),
          onPressed: enabled ? () => move(by) : null,
          icon: Icon(icon),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, softWrap: false),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          side('Softer', Icons.remove, _softGreen, -1),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              // tap: vote fair; tap again: take the vote back
              onTap: enabled ? () => onVote(v == null ? steps[at] : '') : null,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: color, width: 2.5),
                  color: color.withValues(alpha: 0.12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      word,
                      maxLines: 1,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    FittedBox(
                      child: Text(
                        v == null ? 'Tap for fair, or use − and +' : 'Feels like ${steps[v]}',
                        maxLines: 1,
                        style: TextStyle(color: color, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          side('Harder', Icons.add, _hardRed, 1),
        ],
      ),
    );
  }
}

enum _Tool { holds, routes, bend }

/// Drawing on a section: its name, the holds (named circles: A, B, C… or
/// any name), and routes built by tapping holds in order. Routes share the
/// stretches between holds; a stretch can be bent by dragging it. Returns
/// the saved topo.
class TopoEditorScreen extends StatefulWidget {
  const TopoEditorScreen({super.key, required this.tree, required this.boulder, required this.topo, required this.editor, this.newPhoto});
  final PlaceTree tree;
  final Place boulder;
  final Topo topo;
  final PlaceEditor editor;

  /// The photo, when the topo is new and not uploaded yet.
  final TopoPhoto? newPhoto;

  @override
  State<TopoEditorScreen> createState() => _TopoEditorScreenState();
}

class _TopoEditorScreenState extends State<TopoEditorScreen> {
  late Topo _topo = widget.topo;
  late PlaceTree _tree = widget.tree;
  late final _name = TextEditingController(text: widget.topo.name);
  late var _tool = widget.topo.marks.any((m) => m.hold) ? _Tool.routes : _Tool.holds;
  var _saving = false;

  // the route being built: its problem and the holds tapped so far
  String? _problem;
  var _seq = <String>[];
  var _end = TopoEnd.topOut;
  var _yellow = false;

  // dragging: a hold being moved, or a stretch being bent at _bendT along it
  String? _dragHold;
  int? _bendEdge;
  var _bendT = 0.5;

  // where the finger is over the editor body, for the magnifier
  Offset? _finger;
  final _body = GlobalKey();

  void _fingerAt(Offset global) {
    final box = _body.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final at = box.globalToLocal(global);
    if (_dragHold != null || _bendEdge != null || _finger != null) setState(() => _finger = at);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ImageProvider get _photo => widget.newPhoto != null ? MemoryImage(widget.newPhoto!.bytes) : widget.editor.photoOf(_topo);

  List<Place> get _problems => [
    for (final p in _tree.childrenOf(widget.boulder.id))
      if (p.kind == PlaceKind.problem) p,
  ];

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// The topo with the route being built, to show while building it.
  Topo get _shown => _problem == null || _seq.isEmpty
      ? _topo
      : _topo.withRoute(_problem!, _seq, end: _end, color: _yellow ? '#f2c94c' : '#ffffff', sitStart: _tree[_problem!]?.sitStart ?? false);

  Future<void> _pickProblem() async {
    final drawn = {for (final l in _topo.lines) l.problemId};
    final numbers = problemNumbers(_tree, widget.boulder.id);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(leading: const Icon(Icons.add), title: const Text('New problem'), onTap: () => Navigator.pop(context, '')),
          for (final p in _problems)
            ListTile(
              title: Text(displayName(p, numbers[p.id])),
              subtitle: Text(drawn.contains(p.id) ? '${problemGradeLabel(p)} · drawn here, tap to redraw' : problemGradeLabel(p)),
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    var id = picked;
    if (id.isEmpty) {
      final p = await showNewProblemSheet(context, widget.boulder, widget.editor.newId(), number: nextProblemNumber(_tree, widget.boulder.id), tree: _tree);
      if (p == null || !mounted) return;
      final err = await widget.editor.save(p);
      if (!mounted) return;
      if (err != null) return _say(err);
      setState(() => _tree = PlaceTree([..._tree.all, p]));
      id = p.id;
    }
    final old = _topo.lines.where((l) => l.problemId == id).firstOrNull;
    setState(() {
      _problem = id;
      _seq = old != null && old.alone ? List.of(old.via) : [];
      _end = old?.end ?? TopoEnd.topOut;
      _yellow = (old?.color ?? '#ffffff') != '#ffffff';
    });
  }

  String? _holdAt(TopoPoint p) {
    final i = _topo.markAt(p, within: 0.05);
    return i == null ? null : _topo.marks[i].label;
  }

  void _tap(TopoPoint p) {
    switch (_tool) {
      case _Tool.holds:
        final h = _holdAt(p);
        if (h != null) {
          _holdSheet(h);
        } else {
          setState(() => _topo = _topo.copyWith(marks: [..._topo.marks, TopoMark(_topo.nextLabel(), p, hold: true)]));
        }
      case _Tool.routes:
        if (_problem == null) return _say('Tap "Draw a route" first.');
        final h = _holdAt(p);
        if (h == null) return _say('Tap a hold. Add holds with the Holds tool.');
        if (_seq.isNotEmpty && _seq.last == h) return;
        setState(() => _seq = [..._seq, h]);
      case _Tool.bend:
        final i = _edgeAt(p);
        if (i != null && _topo.overlay.edges[i].bend != null) setState(() => _topo = _topo.withBend(i, null));
    }
  }

  /// The built stretch nearest [p], and how far along it [p] is (0..1).
  (int, double)? _edgeNear(TopoPoint p) {
    final a = _topo.aspect;
    (int, double)? best;
    var bestD = 0.05;
    final edges = _topo.overlay.edges;
    for (var i = 0; i < edges.length; i++) {
      final pts = edges[i].points;
      if (edges[i].from.isEmpty || pts.length < 2) continue;
      var total = 0.0;
      final lens = <double>[];
      for (var k = 1; k < pts.length; k++) {
        final l = math.sqrt(math.pow((pts[k].x - pts[k - 1].x) * a, 2) + math.pow(pts[k].y - pts[k - 1].y, 2));
        lens.add(l);
        total += l;
      }
      var run = 0.0;
      for (var k = 1; k < pts.length; k++) {
        final ax = pts[k - 1].x * a, ay = pts[k - 1].y, bx = pts[k].x * a, by = pts[k].y;
        final dx = bx - ax, dy = by - ay;
        final len2 = dx * dx + dy * dy;
        final t = len2 == 0 ? 0.0 : (((p.x * a - ax) * dx + (p.y - ay) * dy) / len2).clamp(0.0, 1.0);
        final d = math.sqrt(math.pow(p.x * a - (ax + t * dx), 2) + math.pow(p.y - (ay + t * dy), 2)) / a;
        if (d < bestD) {
          bestD = d;
          best = (i, total == 0 ? 0.5 : (run + t * lens[k - 1]) / total);
        }
        run += lens[k - 1];
      }
    }
    return best;
  }

  int? _edgeAt(TopoPoint p) => _edgeNear(p)?.$1;

  void _dragStart(TopoPoint p) {
    if (_tool == _Tool.holds) {
      // a drag on bare photo puts a new hold down and slides it under the
      // magnifier; let go where it belongs
      _dragHold = _holdAt(p);
      if (_dragHold == null) {
        final label = _topo.nextLabel();
        setState(() => _topo = _topo.copyWith(marks: [..._topo.marks, TopoMark(label, p, hold: true)]));
        _dragHold = label;
      }
    } else if (_tool == _Tool.bend) {
      final e = _edgeNear(p);
      _bendEdge = e?.$1;
      _bendT = e?.$2 ?? 0.5;
    }
  }

  void _dragUpdate(TopoPoint p) {
    if (_dragHold != null) {
      setState(() => _topo = _topo.withHoldAt(_dragHold!, p));
    } else if (_bendEdge != null) {
      final e = _topo.overlay.edges[_bendEdge!];
      final a = _topo.markNamed(e.from)?.at, b = _topo.markNamed(e.to)?.at;
      if (a == null || b == null) return;
      setState(() => _topo = _topo.withBend(_bendEdge!, bendThrough(a, b, p, _bendT)));
    }
  }

  void _dragEnd() => setState(() {
    _dragHold = _bendEdge = null;
    _finger = null;
  });

  /// A round lens above the finger showing the photo under it 2.5× bigger,
  /// with a cross on the exact spot; below the finger near the top.
  Widget _magnifier(Offset finger) {
    const size = 120.0, gap = 100.0;
    final above = finger.dy > size / 2 + gap;
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

  Future<void> _holdSheet(String label) async {
    final through = _topo.lines.where((l) => l.alone && l.via.contains(label)).length;
    final r = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _HoldSheet(label: label, routes: through),
    );
    if (!mounted || r == null) return;
    final (action, to) = r;
    if (action == 'delete') return setState(() => _topo = _topo.withoutHold(label));
    final t = _topo.withHoldRenamed(label, to);
    if (t == null) return _say(to.trim().isEmpty ? 'Give it a name.' : 'There is already a hold called ${to.trim()}.');
    setState(() => _topo = t);
  }

  void _finishRoute() {
    if (_seq.length < 2) return _say('Tap at least a start hold and an end hold.');
    setState(() {
      _topo = _shown;
      _problem = null;
      _seq = [];
    });
  }

  void _removeRoute() => setState(() {
    _topo = _topo.withoutRoute(_problem!);
    _problem = null;
    _seq = [];
  });

  Future<void> _save() async {
    if (_problem != null && _seq.length >= 2) _finishRoute();
    setState(() => _saving = true);
    final t = _topo.copyWith(name: _name.text.trim());
    final err = await widget.editor.saveTopo(t, photo: widget.newPhoto);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) return _say(err);
    Navigator.pop(context, t);
  }

  Future<void> _deleteSection() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this section?'),
        content: const Text('The photo and its lines disappear for everyone. The routes stay on the boulder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final err = await widget.editor.deleteTopo(_topo);
    if (!mounted) return;
    if (err != null) return _say(err);
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    final numbers = problemNumbers(_tree, widget.boulder.id);
    final shown = _shown;
    final drawing = _problem == null ? null : _tree[_problem!];
    final draftLine = _problem == null ? null : shown.lines.where((l) => l.problemId == _problem).firstOrNull;
    final hasLine = _problem != null && _topo.lines.any((l) => l.problemId == _problem);
    final holds = _topo.marks.where((m) => m.hold).length;
    final hint = switch (_tool) {
      _Tool.holds =>
        'Tap the photo to put ${_topo.nextLabel()} there, or press and slide to place it under the magnifier. Drag a hold to move it, tap it to rename or delete it.',
      _Tool.routes when _problem == null =>
        holds < 2
            ? 'Put at least two holds down with the Holds tool first.'
            : 'Draw a route, then tap its holds in order: start, the holds in between, the end.',
      _Tool.routes => '${drawing == null ? '' : displayName(drawing, numbers[drawing.id])}: ${_seq.isEmpty ? 'tap the start hold' : _seq.join(' → ')}',
      _Tool.bend => 'Drag a line between two holds to bend it; it curves toward your finger. Tap a bent line to straighten it.',
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Text('Section · ${widget.boulder.name}', overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.newPhoto == null) IconButton(tooltip: 'Delete section', onPressed: _deleteSection, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
      body: Stack(
        key: _body,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Section name', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int?>(
                      value: _topo.bearing == null ? null : ((_topo.bearing! / 45).round() % 8) * 45,
                      hint: const Text('Faces'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Faces ?')),
                        for (var b = 0; b < 360; b += 45) DropdownMenuItem<int?>(value: b, child: Text('Faces ${bearingLabel(b)}')),
                      ],
                      onChanged: (b) => setState(() => _topo = _topo.copyWith(bearing: () => b)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_Tool>(
                    segments: const [
                      ButtonSegment(value: _Tool.holds, label: Text('Holds', maxLines: 1, softWrap: false), icon: Icon(Icons.radio_button_unchecked)),
                      ButtonSegment(value: _Tool.routes, label: Text('Routes', maxLines: 1, softWrap: false), icon: Icon(Icons.timeline)),
                      ButtonSegment(value: _Tool.bend, label: Text('Bend', maxLines: 1, softWrap: false), icon: Icon(Icons.gesture)),
                    ],
                    selected: {_tool},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _tool = s.first),
                  ),
                ),
              ),
              Container(
                height: 44, // fixed, so the photo doesn't jump when the hint changes
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(hint, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: Listener(
                  onPointerMove: (e) => _fingerAt(e.position),
                  child: ColoredBox(
                    color: Colors.black,
                    child: TopoCanvas(
                      topo: shown,
                      photo: _photo,
                      draft: draftLine,
                      numbers: numbers,
                      onTap: _tap,
                      onDragStart: _tool == _Tool.routes ? null : _dragStart,
                      onDragUpdate: _tool == _Tool.routes ? null : _dragUpdate,
                      onDragEnd: _tool == _Tool.routes ? null : _dragEnd,
                    ),
                  ),
                ),
              ),
              if (_tool == _Tool.routes)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _problem == null
                      ? FilledButton.icon(onPressed: holds < 2 ? null : _pickProblem, icon: const Icon(Icons.add), label: const Text('Draw a route'))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: _seq.isEmpty ? null : () => setState(() => _seq = _seq.sublist(0, _seq.length - 1)),
                              child: const Text('Undo'),
                            ),
                            FilterChip(
                              label: Text(_end == TopoEnd.topOut ? 'Ends: top out ↑' : 'Ends: at a hold ○', maxLines: 1, softWrap: false),
                              selected: _end == TopoEnd.hold,
                              onSelected: (v) => setState(() => _end = v ? TopoEnd.hold : TopoEnd.topOut),
                            ),
                            FilterChip(
                              label: const Text('Yellow', maxLines: 1, softWrap: false),
                              selected: _yellow,
                              onSelected: (v) => setState(() => _yellow = v),
                            ),
                            if (hasLine) TextButton(onPressed: _removeRoute, child: const Text('Remove line')),
                            TextButton(onPressed: () => setState(() => _problem = null), child: const Text('Cancel')),
                            FilledButton(onPressed: _finishRoute, child: const Text('Done')),
                          ],
                        ),
                ),
            ],
          ),
          if (_finger != null && (_dragHold != null || _bendEdge != null)) _magnifier(_finger!),
        ],
      ),
    );
  }
}

/// Renaming or deleting a hold: pops ('rename', name) or ('delete', '').
class _HoldSheet extends StatefulWidget {
  const _HoldSheet({required this.label, required this.routes});
  final String label;
  final int routes;

  @override
  State<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends State<_HoldSheet> {
  late final _name = TextEditingController(text: widget.label);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hold ${widget.label}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', helperText: 'A letter or any name: "Jug", "G2".', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.pop(context, ('rename', _name.text)), child: const Text('Save name')),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(context, ('delete', '')),
          child: Text(widget.routes == 0 ? 'Delete hold' : 'Delete hold and its ${widget.routes} ${widget.routes == 1 ? 'route line' : 'route lines'}'),
        ),
      ],
    ),
  );
}

/// A new random topo id (a UUID, as the database expects).
String newTopoId([math.Random? random]) {
  final r = random ?? math.Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
