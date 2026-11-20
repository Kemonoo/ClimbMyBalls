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
  const _RouteRow({super.key, required this.problem, required this.number, required this.open, required this.onOpen, required this.onExpand});
  final Place problem;
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

class _RouteScreenState extends State<RouteScreen> {
  late Place _p = widget.problem;
  late Topo? _topo = widget.topo != null && widget.topo!.lines.any((l) => l.problemId == widget.problem.id && l.points.isNotEmpty)
      ? widget.topo
      : _onTopos.where((t) => t.lines.any((l) => l.problemId == widget.problem.id && l.points.isNotEmpty)).firstOrNull ?? _onTopos.firstOrNull;
  List<Ascent>? _ascents;
  String? _error;
  var _busy = false;

  List<Topo> get _onTopos => [
    for (final t in widget.editor.toposOf(widget.boulder.id))
      if (t.lines.any((l) => l.problemId == widget.problem.id)) t,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.editor.signedIn) return;
    try {
      final a = await widget.editor.ascentsOf(_p.id);
      if (mounted) setState(() => _ascents = a);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load ascents. ($e)');
    }
  }

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _log(String outcome) async {
    setState(() => _busy = true);
    final err = await widget.editor.logAscent(_p.id, outcome);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return _say(err);
    _say(switch (outcome) {
      'flash' => 'Flashed. Nice!',
      'sent' => 'Sent. Logged.',
      _ => 'Try logged.',
    });
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
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = _p;
    final t = _topo;
    final line = t == null ? -1 : t.lines.indexWhere((l) => l.problemId == p.id);
    final numbers = problemNumbers(widget.tree, widget.boulder.id);
    final ascents = _ascents ?? const <Ascent>[];
    final sends = ascents.where((a) => a.outcome != 'tried').toList();
    final mine = widget.editor.me;
    final added = widget.editor.createdAt(p.id);
    final by = widget.editor.nameOf(widget.editor.createdBy(p.id));
    final onTopos = _onTopos;
    final start = startLabel(p);
    final end = line >= 0 ? t!.lines[line].end : null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: Text(displayName(p, numbers[p.id]), overflow: TextOverflow.ellipsis),
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
              height: _photoHeight(context, t, share: 0.4),
              child: ColoredBox(
                color: Colors.black,
                child: TopoCanvas(topo: t, photo: widget.editor.photoOf(t), only: line >= 0 ? line : null, numbers: numbers),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p.grade}${p.gradeUncertain ? ' ?' : ''}', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          [
                            p.isRope ? 'Rope · UIAA' : 'Boulder · Font',
                            if (start.isNotEmpty) start,
                            if (end != null) end == TopoEnd.topOut ? 'tops out' : 'ends at a hold',
                          ].join(' · '),
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 16),
                Text(_ascents == null ? 'Ascents' : '${sends.length} ${sends.length == 1 ? 'ascent' : 'ascents'}', style: text.titleMedium),
                if (!widget.editor.signedIn)
                  Text('Sign in on the Friends tab to log ascents.', style: text.bodyMedium)
                else ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(onPressed: _busy ? null : () => _log('flash'), child: const Text('Flash')),
                      FilledButton(onPressed: _busy ? null : () => _log('sent'), child: const Text('Sent')),
                      OutlinedButton(onPressed: _busy ? null : () => _log('tried'), child: const Text('Tried')),
                    ],
                  ),
                  if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
                  for (final a in ascents)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (a.outcome) {
                        'flash' => Icons.bolt,
                        'sent' => Icons.check_circle_outline,
                        _ => Icons.replay,
                      }, color: a.outcome == 'tried' ? cs.outline : cs.primary),
                                            title: Text(a.who.isEmpty ? 'Someone' : a.who),
                      subtitle: Text('${a.outcome} · ${_dmy(a.day)}${a.userId == mine ? ' · tap to change the date' : ''}'),
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
                const SizedBox(height: 16),
                Text('About', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  [
                    'On ${widget.boulder.name}',
                    if (added != null) 'Added ${_dmy(added.toLocal())}${by.isNotEmpty ? ' by $by' : ''}',
                    if (p.source != 'manual') 'From ${p.source}',
                  ].join('\n'),
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tool { route, letters }

/// Drawing on a section: its name, letters on holds, and route lines (pick
/// a problem or make a new one, then tap along the route). Returns the
/// saved topo.
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
  var _tool = _Tool.route;
  TopoLine? _draft; // the line being drawn
  int? _editing; // index of an existing line being redrawn
  var _saving = false;

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
            if (!drawn.contains(p.id))
              ListTile(title: Text(displayName(p, numbers[p.id])), subtitle: Text(problemGradeLabel(p)), onTap: () => Navigator.pop(context, p.id)),
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
    final sit = _tree[id]?.sitStart ?? false;
    setState(() {
      _draft = TopoLine(problemId: id, points: const [], sitStart: sit);
      _editing = null;
    });
  }

  void _tap(TopoPoint p) {
    setState(() {
      if (_tool == _Tool.letters) {
        final i = _topo.markAt(p);
        final marks = List.of(_topo.marks);
        if (i != null) {
          marks.removeAt(i);
        } else {
          marks.add(TopoMark(_topo.nextLabel(), p));
        }
        _topo = _topo.copyWith(marks: marks);
      } else if (_draft != null) {
        _draft = _draft!.copyWith(points: [..._draft!.points, p]);
      } else {
        final i = _topo.lineAt(p);
        if (i != null) {
          _editing = i;
          _draft = _topo.lines[i];
        }
      }
    });
  }

  void _finishLine() {
    final d = _draft!;
    if (d.points.length < 2) return _say('Tap at least a start and an end.');
    final lines = List.of(_topo.lines);
    if (_editing != null) {
      lines[_editing!] = d;
    } else {
      lines.add(d);
    }
    setState(() {
      _topo = _topo.copyWith(lines: lines);
      _draft = null;
      _editing = null;
    });
  }

  void _removeLine() {
    final lines = List.of(_topo.lines);
    if (_editing != null) lines.removeAt(_editing!);
    setState(() {
      _topo = _topo.copyWith(lines: lines);
      _draft = null;
      _editing = null;
    });
  }

  Future<void> _save() async {
    if (_draft != null && _draft!.points.length >= 2) _finishLine();
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
    final d = _draft;
    final drawing = d != null ? _tree[d.problemId] : null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Text('Section · ${widget.boulder.name}'),
        actions: [
          if (widget.newPhoto == null) IconButton(tooltip: 'Delete section', onPressed: _deleteSection, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Section name', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                SegmentedButton<_Tool>(
                  segments: const [
                    ButtonSegment(value: _Tool.route, label: Text('Routes', maxLines: 1, softWrap: false), icon: Icon(Icons.timeline)),
                    ButtonSegment(value: _Tool.letters, label: Text('Letters', maxLines: 1, softWrap: false), icon: Icon(Icons.abc)),
                  ],
                  selected: {_tool},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _tool = s.first;
                    _draft = null;
                    _editing = null;
                  }),
                ),
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
          Container(
            height: 40, // fixed, so the photo doesn't jump when the hint changes
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _tool == _Tool.letters
                  ? 'Tap a hold to put the next letter (${_topo.nextLabel()}) there. Tap a letter to remove it.'
                  : d == null
                  ? 'Pick a problem, then tap along its route from the start. Tap a drawn line to change it.'
                  : 'Drawing ${drawing == null ? '' : displayName(drawing, numbers[drawing.id])}: tap from the start, hold by hold, to the end. ${d.points.length} points.',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: TopoCanvas(topo: _topo, photo: _photo, draft: d, numbers: numbers, lit: {if (_editing != null) _editing!}, onTap: _tap),
            ),
          ),
          if (_tool == _Tool.route)
            Padding(
              padding: const EdgeInsets.all(8),
              child: d == null
                  ? FilledButton.icon(onPressed: _pickProblem, icon: const Icon(Icons.add), label: const Text('Draw a route'))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: d.points.isEmpty ? null : () => setState(() => _draft = d.copyWith(points: d.points.sublist(0, d.points.length - 1))),
                          child: const Text('Undo'),
                        ),
                        FilterChip(
                          label: Text(d.end == TopoEnd.topOut ? 'Ends: top out ↑' : 'Ends: at a hold ○'),
                          selected: d.end == TopoEnd.hold,
                          onSelected: (v) => setState(() => _draft = d.copyWith(end: v ? TopoEnd.hold : TopoEnd.topOut)),
                        ),
                        FilterChip(
                          label: const Text('Yellow'),
                          selected: d.color != '#ffffff',
                          onSelected: (v) => setState(() => _draft = d.copyWith(color: v ? '#f2c94c' : '#ffffff')),
                        ),
                        if (_editing != null) TextButton(onPressed: _removeLine, child: const Text('Remove line')),
                        TextButton(onPressed: () => setState(() => _draft = _editing = null), child: const Text('Cancel')),
                        FilledButton(onPressed: _finishLine, child: const Text('Done')),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
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
