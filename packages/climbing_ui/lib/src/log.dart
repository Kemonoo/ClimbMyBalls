part of '../climbing_ui.dart';

/// A route on the log page: one boulder, with how many goes it took and
/// whether one of them topped it. Becomes one [Climb] when the session is saved.
class _Route {
  _Route({
    required this.grade,
    required this.angle,
    this.name = '',
    this.tries = 1,
    this.counted = true,
    this.topped = false,
    this.repeat = false,
    this.hold = '',
    this.problemId,
    this.gymGrade = '',
  });

  factory _Route.of(Climb c) => _Route(
        grade: c.grade,
        angle: c.angle,
        name: c.name,
        tries: c.tries ?? (c.outcome.isSend ? 2 : 1),
        counted: c.tries != null,
        topped: c.outcome.isSend,
        repeat: c.repeat,
        hold: c.hold,
        problemId: c.problemId,
        gymGrade: c.gymGrade,
      );

  String grade; // '' = ungraded ("?")
  WallAngle angle;
  String name;

  /// Goes on it, counting the one that topped it. At least 1.
  int tries;

  /// False when the goes weren't counted (a pasted ✅ send, an older log):
  /// [tries] is then only a stand-in, and isn't saved.
  bool counted;
  bool topped;
  bool repeat;
  String hold;

  /// Kept from the climb being edited, so saving doesn't drop the link.
  final String? problemId;
  final String gymGrade;

  ClimbOutcome get outcome => !topped
      ? ClimbOutcome.tried
      : tries == 1 && counted
          ? ClimbOutcome.flash
          : ClimbOutcome.sent;

  /// Another go that didn't top it.
  void addTry() {
    tries++;
    counted = true;
  }

  /// The next go topped it; tapped again, it didn't after all.
  void toggleTopped() {
    if (topped) {
      topped = false;
      if (counted && tries > 1) tries--;
    } else {
      if (counted) tries++;
      topped = true;
    }
  }

  Climb toClimb() => Climb(
        grade: grade,
        outcome: outcome,
        name: name.trim(),
        repeat: repeat,
        angle: angle,
        hold: hold,
        attempts: counted ? tries : null,
        problemId: problemId,
        gymGrade: gymGrade,
      );
}

/// "Sent · 4 tries · repeat", the line under a route.
String _routeMeta(_Route r) => [
      r.outcome.label,
      if (r.outcome != ClimbOutcome.flash) r.counted ? _plural(r.tries, 'try', 'tries') : 'tries not counted',
      if (r.repeat) 'repeat',
    ].join(' · ');

/// Log a session route by route: a grade (and a name if you like), then how
/// the first go went. Later goes on the same route go on its counter.
class ClimbLogPage extends StatefulWidget {
  const ClimbLogPage({super.key, this.existing});
  final ClimbSession? existing;

  @override
  State<ClimbLogPage> createState() => _ClimbLogPageState();
}

class _ClimbLogPageState extends State<ClimbLogPage> {
  late DateTime start;
  late final TextEditingController place;
  final name = TextEditingController();
  late bool outdoor;
  late ClimbStyle style;
  late final List<_Route> routes;
  WallAngle angle = WallAngle.vertical;
  String? grade; // '' = ungraded ("?")
  bool repeat = false;
  bool allBands = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // Starting a new one: the place and wall you used last time.
    final last = host.store.sessions.isEmpty ? null : host.store.sessions.last;
    start = e?.start ?? host.now();
    place = TextEditingController(text: e?.place ?? last?.place ?? '');
    outdoor = e?.outdoor ?? last?.outdoor ?? false;
    style = e?.style ?? last?.style ?? ClimbStyle.boulder;
    routes = [for (final c in e?.climbs ?? const <Climb>[]) _Route.of(c)];
    if (routes.isNotEmpty) angle = routes.last.angle;
  }

  @override
  void dispose() {
    place.dispose();
    name.dispose();
    super.dispose();
  }

  /// A new route from the first go: flashed, sent (goes not counted), or tried.
  void _add(ClimbOutcome o) {
    if (grade == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      routes.add(_Route(
        grade: grade!,
        angle: angle,
        name: name.text.trim(),
        topped: o.isSend,
        counted: o != ClimbOutcome.sent,
        tries: o == ClimbOutcome.sent ? 2 : 1,
        repeat: repeat,
      ));
      grade = null;
      repeat = false;
      name.clear();
    });
  }

  void _save() {
    final e = widget.existing;
    final climbs = [for (final r in routes) r.toClimb()];
    final s = e == null
        ? ClimbSession(id: host.store.newId(), start: start, place: place.text.trim(), outdoor: outdoor, climbs: climbs, style: style)
        // Moving the day moves the end with it, so the length stays the same.
        : e.copyWith(start: start, end: () => e.end?.add(start.difference(e.start)), place: place.text.trim(), outdoor: outdoor, climbs: climbs, style: style);
    e == null ? host.store.add(s) : host.store.update(s);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${_plural(climbs.length, 'climb')}.')));
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: host.now().subtract(const Duration(days: 365 * 3)),
      lastDate: host.now(),
    );
    if (d == null) return;
    setState(() => start = DateTime(d.year, d.month, d.day, start.hour, start.minute));
  }

  /// Name, goes, topped, repeat, or remove one route.
  Future<void> _edit(_Route r) async {
    final look = host.theme(context);
    void change(VoidCallback f) => setState(f);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          void both(VoidCallback f) {
            change(f);
            setSheet(() {});
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _GradeBadge(look: look, route: r),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_routeMeta(r), style: look.text(15, color: look.muted))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: r.name,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (v) => change(() => r.name = v),
                      decoration: InputDecoration(
                        labelText: 'Name (optional)',
                        hintText: 'e.g. the yellow one on the cave',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tries', style: look.text(15, bold: true)),
                              Text('Every go, counting the one that topped it.', style: look.text(12, color: look.muted)),
                            ],
                          ),
                        ),
                        IconButton.outlined(
                          tooltip: 'One try fewer',
                          onPressed: r.counted && r.tries > 1 ? () => both(() => r.tries--) : null,
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(r.counted ? '${r.tries}' : '–', textAlign: TextAlign.center, style: look.text(20, bold: true)),
                        ),
                        IconButton.outlined(
                          tooltip: 'One try more',
                          onPressed: () => both(r.addTry),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Topped', style: look.text(15, bold: true)),
                      subtitle: Text(r.counted && r.tries == 1 ? 'On the first try, so a flash' : 'Sent it', style: look.text(12, color: look.muted)),
                      value: r.topped,
                      onChanged: (v) => both(() => r.topped = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Repeat', style: look.text(15, bold: true)),
                      subtitle: Text('Climbed before: half the points', style: look.text(12, color: look.muted)),
                      value: r.repeat,
                      onChanged: (v) => both(() => r.repeat = v),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          change(() => routes.remove(r));
                          Navigator.pop(sheet);
                        },
                        style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: look.line, width: 1.5)),
                        icon: Icon(Icons.delete_outline_rounded, color: look.ink),
                        label: Text('Remove this climb', style: look.text(15, bold: true)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = host.theme(context);
    final bands = allBands ? const ['3', '4', '5', '6', '7', '8'] : const ['4', '5', '6', '7'];
    final counted = [for (final r in routes) if (r.counted) r.tries];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Log climbs' : 'Edit session', style: look.text(20, bold: true)),
        actions: [
          TextButton(
            onPressed: routes.isEmpty ? null : _save,
            child: Text('Save', style: look.text(15, bold: true, color: routes.isEmpty ? look.muted : look.accentDeep)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ClimbStyle.values)
                ChoiceChip(label: Text(s.label), selected: style == s, onSelected: (_) => setState(() => style = s)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (v, l) in const [(false, 'Indoor'), (true, 'Outdoor')])
                ChoiceChip(label: Text(l), selected: outdoor == v, onSelected: (_) => setState(() => outdoor = v)),
            ],
          ),
          const SizedBox(height: 16),
          // Pick a saved place, or + for a new one. Nothing here renames a place.
          Row(
            children: [
              Expanded(
                child: _PlacePicker(
                  value: place.text,
                  onPicked: (p) => setState(() {
                    place.text = p.name;
                    outdoor = p.outdoor;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'New gym or crag',
                onPressed: () async {
                  final p = await showPlaceSheet(context, creating: true, outdoor: outdoor);
                  if (p != null) {
                    setState(() {
                      place.text = p.name;
                      outdoor = p.outdoor;
                    });
                  }
                },
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _pickDay,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: look.line, width: 1.5),
                  ),
                  child: Text(host.dayLabel(host.dayKey(start)), style: look.text(15, bold: true)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Wall', style: look.text(15, bold: true)),
          Text('Kept for the next climbs until you change it.', style: look.text(12, color: look.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in WallAngle.values)
                ChoiceChip(label: Text(a.label), selected: angle == a, onSelected: (_) => setState(() => angle = a)),
            ],
          ),
          const SizedBox(height: 24),
          Text('New climb', style: look.text(15, bold: true)),
          const SizedBox(height: 8),
          for (final b in bands)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (final g in kGradeLadder.where((g) => g.startsWith(b))) ...[
                    Expanded(child: _GradeChip(look: look, grade: g, selected: grade == g, onTap: () => setState(() => grade = grade == g ? null : g))),
                    if (!g.endsWith('C+')) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: _GradeChip(look: look, grade: '', selected: grade == '', onTap: () => setState(() => grade = grade == '' ? null : '')),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => allBands = !allBands),
                child: Text(allBands ? 'Fewer grades' : 'Show 3s and 8s'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'e.g. the yellow one on the cave',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('This session', style: look.text(15, bold: true))),
              if (routes.isNotEmpty)
                Text(
                  [_plural(routes.length, 'climb'), if (counted.isNotEmpty) _plural(counted.fold<int>(0, (a, t) => a + t), 'try', 'tries')].join(' · '),
                  style: look.text(12, color: look.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (routes.isEmpty)
            Text(
              'Pick a grade, then how your first go went. Later goes on the same climb go on its counter: + for another try, ✓ when you top it.',
              style: look.text(15, color: look.muted, height: 1.4),
            )
          else
            for (final r in routes.reversed)
              _RouteRow(
                key: ObjectKey(r),
                look: look,
                route: r,
                onTry: () {
                  HapticFeedback.selectionClick();
                  setState(r.addTry);
                },
                onTopped: () {
                  HapticFeedback.lightImpact();
                  setState(r.toggleTopped);
                },
                onEdit: () => _edit(r),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      grade == null ? 'Pick a grade first' : 'How did the first go on ${grade!.isEmpty ? 'the "?" climb' : grade} go?',
                      style: look.text(12, bold: true, color: look.muted),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Repeat'),
                    tooltip: 'Climbed before: half the points',
                    selected: repeat,
                    onSelected: (v) => setState(() => repeat = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final o in ClimbOutcome.values) ...[
                    if (o != ClimbOutcome.flash) const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: grade == null ? null : () => _add(o),
                          style: FilledButton.styleFrom(
                            backgroundColor: o == ClimbOutcome.tried ? look.ink : look.accent,
                            foregroundColor: o == ClimbOutcome.tried ? look.surface : look.onAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: Icon(_outcomeIcon(o), size: 20),
                          label: Text(o.label, style: look.text(15, bold: true, color: grade == null ? look.muted : null)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grade in its colour, filled for a flash, outlined otherwise.
class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.look, required this.route});
  final ClimbTheme look;
  final _Route route;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(route.grade);
    final flash = route.outcome == ClimbOutcome.flash;
    return Container(
      width: 48,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1.5),
        color: flash ? c : route.topped ? c.withValues(alpha: 0.15) : null,
      ),
      child: Text(route.grade.isEmpty ? '?' : route.grade, style: look.text(14, bold: true, color: flash ? Colors.white : look.ink)),
    );
  }
}

/// One climb in the session: tap to edit, + for another try, ✓ when topped.
class _RouteRow extends StatelessWidget {
  const _RouteRow({super.key, required this.look, required this.route, required this.onTry, required this.onTopped, required this.onEdit});
  final ClimbTheme look;
  final _Route route;
  final VoidCallback onTry, onTopped, onEdit;

  @override
  Widget build(BuildContext context) {
    final r = route;
    return Semantics(
      container: true,
      label: climbSpoken(r.toClimb()),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ExcludeSemantics(child: _GradeBadge(look: look, route: r)),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r.name.trim().isNotEmpty)
                          Text(r.name.trim(), style: look.text(15, bold: true), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(_routeMeta(r), style: look.text(r.name.trim().isEmpty ? 15 : 12, color: r.name.trim().isEmpty ? look.ink : look.muted)),
                      ],
                    ),
                  ),
                ),
                if (!r.topped)
                  IconButton(
                    tooltip: 'Another try',
                    onPressed: onTry,
                    icon: Icon(Icons.add_rounded, color: look.ink),
                  ),
                IconButton(
                  tooltip: r.topped ? 'Not topped after all' : 'Topped it',
                  onPressed: onTopped,
                  isSelected: r.topped,
                  style: IconButton.styleFrom(
                    backgroundColor: r.topped ? look.accent : null,
                    side: r.topped ? null : BorderSide(color: look.line, width: 1.5),
                  ),
                  icon: Icon(r.topped ? _outcomeIcon(r.outcome) : Icons.check_rounded, color: r.topped ? look.onAccent : look.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.look, required this.grade, required this.selected, required this.onTap});
  final ClimbTheme look;
  final String grade; // '' = "?"
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(grade);
    final label = grade.isEmpty ? '?' : grade;
    return Semantics(
      button: true,
      selected: selected,
      label: grade.isEmpty ? 'Ungraded' : 'Grade $grade',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? c : look.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? c : look.line, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: look.text(14, bold: true, color: selected ? Colors.white : look.ink)),
                  ),
                  if (!selected) Container(width: 16, height: 3, margin: const EdgeInsets.only(top: 3), color: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- paste from Strava ----------
