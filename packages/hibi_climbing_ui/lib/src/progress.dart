part of '../climbing_ui.dart';

/// Move → Climb: your level, then TopLogger-style statistics (pyramid, top 10,
/// grade history) for a period, then every session.
class ClimbSection extends StatefulWidget {
  const ClimbSection({super.key});

  @override
  State<ClimbSection> createState() => _ClimbSectionState();
}

class _ClimbSectionState extends State<ClimbSection> {
  _Period period = _Period.twoMonths;

  /// '' for every place, '@in' indoor, '@out' outdoor, else a place's name.
  String where = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: host.listenable, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final look = host.theme(context);
    final now = host.now();
    final all = host.store.sessions;
    final level = levelFrom(all, now: now);
    bool at(ClimbSession s) => switch (where) {
          '' => true,
          '@in' => ClimbWhere.indoor.has(s),
          '@out' => ClimbWhere.outdoor.has(s),
          _ => s.place.trim().toLowerCase() == where.toLowerCase(),
        };
    final sessions = [for (final s in all) if (at(s)) s];
    final linked = {for (final s in sessions) if (s.sourceId != null) s.sourceId!};
    // Health Connect climbs that have no grades yet: worth a nudge to paste them.
    final bare = [
      for (final w in host.workouts)
        if (w.type == 'climb' && !linked.contains(w.id) && now.difference(w.start).inDays < 30) w,
    ]..sort((a, b) => b.start.compareTo(a.start));
    final first = sessions.isEmpty ? now : sessions.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
    // Grades, the top 10 and the history count bouldering; rope sessions are listed below.
    final boulder = [for (final s in sessions) if (s.style == ClimbStyle.boulder) s];
    final since = switch (period) {
      _Period.twoMonths => now.subtract(const Duration(days: 60)),
      _Period.year => DateTime(now.year),
      _Period.all => first,
    };
    final inPeriod = [for (final s in boulder) if (!s.start.isBefore(since) && !s.start.isAfter(now)) s];
    final climbs = [for (final s in inPeriod) ...s.climbs];
    final from = inPeriod.isEmpty ? since : inPeriod.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        if (all.isEmpty) ...[
          Text('No climbs yet', style: look.text(20, bold: true)),
          const SizedBox(height: 4),
          Text(
            'Log your climbs by hand, or paste the text TopLogger writes to your Strava activity. '
            'Your level, grades and sessions show up here.',
            style: look.text(15, color: look.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _Actions(look: look),
        ] else ...[
          _LevelHeader(look: look, level: level),
          const SizedBox(height: 16),
          _Actions(look: look),
        ],
        for (final w in bare.take(3)) _BareWorkoutRow(look: look, workout: w),
        if (all.isNotEmpty) ...[
          const SizedBox(height: 24),
          _ClimbCalendar(look: look, sessions: sessions),
          const SizedBox(height: 24),
          _WhereChips(look: look, where: where, onPick: (w) => setState(() => where = w)),
          const SizedBox(height: 8),
          _PeriodChips(look: look, period: period, onPick: (p) => setState(() => period = p)),
          const SizedBox(height: 24),
          Text('Grade pyramid', style: look.text(24, bold: true)),
          Text('${_ddmmyy(from)} → ${_ddmmyy(now)}', style: look.text(15, color: look.muted)),
          const SizedBox(height: 16),
          if (gradePyramid(climbs).isEmpty)
            Text('Nothing sent in this period.', style: look.text(15, color: look.muted))
          else
            _Pyramid(look: look, counts: gradePyramid(climbs)),
          const SizedBox(height: 32),
          Text('Top 10', style: look.text(24, bold: true)),
          Text(
            period == _Period.twoMonths ? 'Average of top 10 ascents last 2 months' : 'Average of top 10 ascents, ${period.label.toLowerCase()}',
            style: look.text(15, color: look.muted),
          ),
          const SizedBox(height: 12),
          _TopTen(
            look: look,
            sends: levelSends(boulder, now: now, since: since, top: 1 << 20),
            now: now,
            expiring: period == _Period.twoMonths,
          ),
          const SizedBox(height: 32),
          _GradeHistory(look: look, sessions: boulder, now: now, since: period == _Period.all ? first : since),
          const SizedBox(height: 32),
          Text('Sessions', style: look.text(24, bold: true)),
          const SizedBox(height: 8),
          if (sessions.isEmpty) Text('No sessions here yet.', style: look.text(15, color: look.muted)),
          _SessionList(look: look, sessions: sessions.reversed.toList()),
        ],
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.look});
  final ClimbTheme look;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final log = SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: () => openClimbLog(context),
          style: FilledButton.styleFrom(backgroundColor: look.accent, foregroundColor: look.onAccent, shape: const StadiumBorder()),
          icon: const Icon(Icons.add_rounded),
          label: Text('Log climbs', style: look.text(15, bold: true, color: look.onAccent)),
        ),
      );
      final paste = SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () => showPasteSheet(context),
          style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: look.line, width: 1.5)),
          icon: Icon(Icons.content_paste_rounded, color: look.ink),
          label: Text('Paste Strava', style: look.text(15, bold: true)),
        ),
      );
      // Side by side when both labels fit on one line, else stacked.
      if (box.maxWidth < 330) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [log, const SizedBox(height: 8), paste]);
      }
      return Row(children: [Expanded(child: log), const SizedBox(width: 12), Expanded(child: paste)]);
    },
  );
}

/// TopLogger's gym pills: every place, indoor, outdoor, or one gym or crag,
/// and a pencil to edit the saved places.
class _WhereChips extends StatelessWidget {
  const _WhereChips({required this.look, required this.where, required this.onPick});
  final ClimbTheme look;
  final String where;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final places = host.store.places;
    Widget pill(String id, String label, {IconData? icon}) {
      final on = id == where;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onPick(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: on ? _pink.withValues(alpha: 0.14) : null,
                border: Border.all(color: on ? _pink : look.muted, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: on ? _pink : look.ink), const SizedBox(width: 6)],
                Text(label, style: look.text(15, bold: on, color: on ? _pink : look.ink)),
              ]),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        pill('', 'All places'),
        pill('@in', 'Indoor', icon: Icons.home_work_outlined),
        pill('@out', 'Outdoor', icon: Icons.landscape_outlined),
        for (final p in places) pill(p.name, p.name),
        IconButton(tooltip: 'Gyms and crags', onPressed: () => showPlacesSheet(context), icon: const Icon(Icons.edit_location_alt_outlined)),
      ]),
    );
  }
}

/// TopLogger's gym pills, here picking the period.
class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.look, required this.period, required this.onPick});
  final ClimbTheme look;
  final _Period period;
  final ValueChanged<_Period> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final p in _Period.values)
        Semantics(
          selected: p == period,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onPick(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: p == period ? _pink.withValues(alpha: 0.14) : null,
                border: Border.all(color: p == period ? _pink : look.muted, width: 1.5),
              ),
              child: Text(p.label, style: look.text(15, bold: p == period, color: p == period ? _pink : look.ink)),
            ),
          ),
        ),
    ],
  );
}

/// The grade with TopLogger's raised "+88%".
class _GradeWithPercent extends StatelessWidget {
  const _GradeWithPercent({required this.look, required this.level, this.size = 40});
  final ClimbTheme look;
  final ClimbLevel level;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: level.next == null ? level.grade : '${level.grade}, ${(level.fraction * 100).floor()}% to ${level.next}',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(level.grade, style: look.text(size, bold: true, height: 1.1)),
          if (level.next != null)
            Padding(
              padding: EdgeInsets.only(left: 4, top: size * 0.05),
              child: Text('+${(level.fraction * 100).floor()}%', style: look.text(size * 0.45, color: look.muted)),
            ),
        ],
      ),
    ),
  );
}

class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.look, required this.level});
  final ClimbTheme look;
  final ClimbLevel? level;

  @override
  Widget build(BuildContext context) {
    final l = level;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your level', style: look.text(12, bold: true, color: look.muted)),
              if (l == null)
                Text('Nothing sent in 2 months', style: look.text(20, bold: true))
              else ...[
                _GradeWithPercent(look: look, level: l),
                if (l.next != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: l.fraction,
                      minHeight: 8,
                      backgroundColor: look.line,
                      color: _pink,
                      semanticsLabel: 'Progress to ${l.next}',
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Top 10 average of the last 2 months: ${l.points.round()} points'
                  '${l.next == null ? '' : ', ${(l.fraction * 100).floor()}% of the way to ${l.next}'}.',
                  style: look.text(12, color: look.muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        IconButton(tooltip: 'How the level works', onPressed: () => _explain(context, look), icon: const Icon(Icons.info_outline_rounded)),
      ],
    );
  }
}

void _explain(BuildContext context, ClimbTheme look) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How your level works', style: look.text(20, bold: true)),
          const SizedBox(height: 12),
          for (final line in const [
            'Points work like TopLogger\'s: 5A is 500, 6A is 600, 7A is 700, and each half grade between adds a sixth (6B 633, 6B+ 650, 6C 667).',
            'A flash adds 10 points, so a flashed 6A (610) still ranks below a worked 6A+ (617). A repeat scores half, and a climb you tried but didn\'t send scores nothing.',
            'Your level is the average points of your 10 best sends in the last 2 months, divided by 10 even when you have fewer. The +% is how far that is toward the next half grade: 648 sits 88% of the way from 6B (633) to 6B+ (650).',
            'Each send in the top 10 shows how many days until it drops out of the 2 months.',
            'A session\'s grade works the same way, with only that session\'s sends.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(line, style: look.text(15, height: 1.45)),
            ),
        ],
      ),
    ),
  ),
);

/// TopLogger's grade pyramid: a bar per grade from the hardest to the easiest
/// logged, the total at its end, and the flashed part darker with its count.
class _Pyramid extends StatefulWidget {
  const _Pyramid({required this.look, required this.counts});
  final ClimbTheme look;
  final Map<int, (int, int)> counts;

  @override
  State<_Pyramid> createState() => _PyramidState();
}

class _PyramidState extends State<_Pyramid> {
  bool all = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look, counts = widget.counts;
    final hi = counts.keys.reduce((a, b) => a > b ? a : b), lo = counts.keys.reduce((a, b) => a < b ? a : b);
    final rungs = [for (var r = hi; r >= lo; r--) r];
    final most = counts.values.map((v) => v.$1 + v.$2).reduce((a, b) => a > b ? a : b);
    final total = counts.values.fold<int>(0, (a, v) => a + v.$1 + v.$2);
    // Long ladders fold after the ten hardest rungs, like TopLogger's chevron.
    final shown = all ? rungs : rungs.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in shown)
          Semantics(
            label: '${kGradeLadder[r]}: ${_plural((counts[r]?.$1 ?? 0) + (counts[r]?.$2 ?? 0), 'send')}, ${counts[r]?.$1 ?? 0} flashed',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(width: 48, child: Text(kGradeLadder[r], style: look.text(17))),
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: LayoutBuilder(builder: (context, box) {
                          final (f, wk) = counts[r] ?? (0, 0);
                          if (f + wk == 0) return const SizedBox();
                          // The flashed bar leaves room for the total's pill after it.
                          const pill = 48.0;
                          final fw = pill + (box.maxWidth - 2 * pill) * f / most;
                          final tw = wk == 0 ? fw : (pill + (box.maxWidth - pill) * (f + wk) / most).clamp(fw + pill, box.maxWidth).toDouble();
                          return Stack(
                            children: [
                              if (wk > 0) _bar(tw, _pink, '${f + wk}', look),
                              if (f > 0) _bar(fw, _wine, '$f', look, bolt: true),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (rungs.length > 10)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: all ? 'Show fewer grades' : 'Show all grades',
              onPressed: () => setState(() => all = !all),
              icon: Icon(all ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            ),
          ),
        Divider(color: look.line, height: 24),
        Row(children: [
          const SizedBox(width: 48),
          Expanded(child: Text('Total', style: look.text(17, bold: true))),
          Text('$total', style: look.text(17, bold: true)),
        ]),
      ],
    );
  }

  Widget _bar(double w, Color c, String count, ClimbTheme look, {bool bolt = false}) => Container(
    width: w,
    height: 26,
    alignment: Alignment.centerRight,
    decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.horizontal(right: Radius.circular(13))),
    child: Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Color.lerp(c, Colors.black, 0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (bolt) const Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
        Text(count, style: look.text(14, color: Colors.white)),
      ]),
    ),
  );
}

/// One mark per climb, hardest first: solid for a flash, pale for a worked
/// send, an outline for a try, grey for "?".
class ClimbStrip extends StatelessWidget {
  const ClimbStrip({super.key, required this.climbs, this.size = 12});
  final List<Climb> climbs;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sorted = [...climbs]..sort((a, b) => (b.index ?? -1).compareTo(a.index ?? -1));
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final c in sorted)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: switch (c.outcome) {
                ClimbOutcome.flash => gradeColor(c.grade),
                ClimbOutcome.sent => gradeColor(c.grade).withValues(alpha: 0.4),
                ClimbOutcome.tried => Colors.transparent,
              },
              border: c.outcome == ClimbOutcome.tried ? Border.all(color: gradeColor(c.grade), width: 1.5) : null,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A climb's dot: its hold colour when TopLogger gave one, else its grade's.
Widget _dot(Climb c) => Container(
  width: 14,
  height: 14,
  decoration: BoxDecoration(color: holdColor(c.hold) ?? gradeColor(c.grade), shape: BoxShape.circle),
);

/// TopLogger's points table: dot, grade, name (gym), optional days left in
/// the 2 months, flash bonus and points, on alternating rows.
class _PointsTable extends StatelessWidget {
  const _PointsTable({required this.look, required this.rows, this.expires});
  final ClimbTheme look;
  final List<(Climb, String, String)> rows; // climb, name, where (shown muted)

  /// Days until each row drops out of the 2 months, or null for no column.
  final List<int>? expires;

  @override
  Widget build(BuildContext context) {
    final head = look.text(13, color: look.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(children: [
            const Spacer(),
            if (expires != null) SizedBox(width: 64, child: Text('Expires\n(days)', textAlign: TextAlign.center, style: head)),
            SizedBox(width: 52, child: Text('Bonus', textAlign: TextAlign.right, style: head)),
            SizedBox(width: 56, child: Text('Points', textAlign: TextAlign.right, style: head)),
          ]),
        ),
        for (final (i, (c, name, where)) in rows.indexed)
          Semantics(
            label: '${climbSpoken(c.copyWith(name: ''))}, $name, ${c.points.round()} points'
                '${expires == null ? '' : ', expires in ${expires![i]} days'}',
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: i.isEven ? look.ink.withValues(alpha: 0.06) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  _dot(c),
                  const SizedBox(width: 8),
                  SizedBox(width: 40, child: Text(c.isGraded ? c.grade : '?', style: look.text(16))),
                  if (c.outcome == ClimbOutcome.flash) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF4CD964))),
                  if (c.repeat) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.replay_rounded, size: 15, color: look.muted)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: name, style: look.text(15)),
                        if (where.isNotEmpty) TextSpan(text: name.isEmpty ? where : ' ($where)', style: look.text(15, color: look.muted)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (expires != null) SizedBox(width: 64, child: Text('${expires![i]}', textAlign: TextAlign.center, style: look.text(15))),
                  SizedBox(
                    width: 52,
                    child: Text(c.outcome == ClimbOutcome.flash ? '${kFlashBonus.round()}' : '0', textAlign: TextAlign.right, style: look.text(15)),
                  ),
                  SizedBox(width: 56, child: Text('${c.points.round()}', textAlign: TextAlign.right, style: look.text(15))),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// The ten sends behind the average, with the average itself, and more on demand.
class _TopTen extends StatefulWidget {
  const _TopTen({required this.look, required this.sends, required this.now, required this.expiring});
  final ClimbTheme look;
  final List<(Climb, ClimbSession)> sends; // every send in the period, best first
  final DateTime now;
  final bool expiring;

  @override
  State<_TopTen> createState() => _TopTenState();
}

class _TopTenState extends State<_TopTen> {
  int shown = 10;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final sends = widget.sends;
    if (sends.isEmpty) return Text('Nothing sent in this period.', style: look.text(15, color: look.muted));
    final rows = sends.take(shown).toList();
    final average = sends.take(10).fold<double>(0, (a, s) => a + s.$1.points) / 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PointsTable(
          look: look,
          rows: [for (final (c, s) in rows) (c, c.name.isEmpty ? '' : c.name, s.place.isNotEmpty ? s.place : _ddmmyy(s.start))],
          expires: widget.expiring
              ? [for (final (_, s) in rows) s.start.add(const Duration(days: 60)).difference(widget.now).inHours ~/ 24 + 1]
              : null,
        ),
        Divider(color: look.line, height: 16),
        Row(children: [
          if (sends.length > shown)
            Flexible(
              child: TextButton.icon(
                onPressed: () => setState(() => shown += 10),
                icon: const Icon(Icons.arrow_downward_rounded),
                label: Text('LOAD MORE', style: look.text(15, bold: true).copyWith(letterSpacing: 1), overflow: TextOverflow.ellipsis),
              ),
            ),
          const Spacer(),
          Text('Average  ${average.round()}', style: look.text(18, bold: true)),
          const SizedBox(width: 10),
        ]),
      ],
    );
  }
}

/// TopLogger's boulder grade history: the level over time as a filled line,
/// with a second line for flashes only. Each can be switched off.
class _GradeHistory extends StatefulWidget {
  const _GradeHistory({required this.look, required this.sessions, required this.now, required this.since});
  final ClimbTheme look;
  final List<ClimbSession> sessions;
  final DateTime now, since;

  @override
  State<_GradeHistory> createState() => _GradeHistoryState();
}

class _GradeHistoryState extends State<_GradeHistory> {
  bool top = true, flash = true;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final days = widget.now.difference(widget.since).inDays.clamp(14, 3650);
    // About 60 points across whatever the period is.
    final step = (days / 60).ceil().clamp(1, 30);
    final weeks = (days / 7).ceil();
    final tops = levelHistory(widget.sessions, now: widget.now, weeks: weeks, step: step);
    final flashes = levelHistory(widget.sessions, now: widget.now, weeks: weeks, step: step, flashOnly: true);
    final known = [for (final (_, l) in tops) if (l != null) l.index];
    Widget box(String label, bool on, Color c, ValueChanged<bool> set, {bool bolt = false}) => InkWell(
      onTap: () => set(!on),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: on, onChanged: (v) => set(v ?? false), activeColor: c, side: BorderSide(color: c, width: 2)),
          Text(label, style: look.text(17)),
          if (bolt) Icon(Icons.bolt_rounded, size: 18, color: look.ink),
        ]),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Boulder grade history', style: look.text(24, bold: true)),
        Wrap(spacing: 16, children: [
          box('Top', top, _pink, (v) => setState(() => top = v)),
          box('Flash', flash, _wine, (v) => setState(() => flash = v), bolt: true),
        ]),
        const SizedBox(height: 8),
        if (known.length < 2)
          Text('The line appears after two weeks of climbing.', style: look.text(12, color: look.muted, height: 1.4))
        else
          Semantics(
            label: 'Grade history from ${_ddmmyy(tops.first.$1)}: now ${gradeLabel(known.last)}.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 260,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _HistoryPainter(
                    look,
                    [for (final (t, _) in tops) t],
                    top ? [for (final (_, l) in tops) l?.index] : null,
                    flash ? [for (final (_, l) in flashes) l?.index] : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.look, this.days, this.top, this.flash);
  final ClimbTheme look;
  final List<DateTime> days;
  final List<double?>? top, flash;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...?top, ...?flash].whereType<double>();
    if (all.isEmpty) return;
    var lo = all.reduce((a, b) => a < b ? a : b).floor() - 1;
    var hi = all.reduce((a, b) => a > b ? a : b).ceil() + 1;
    lo = lo.clamp(0, kGradeLadder.length - 1);
    hi = hi.clamp(lo + 2, kGradeLadder.length - 1);
    const left = 44.0, bottom = 28.0;
    final h = size.height - bottom, w = size.width - left;
    double y(double i) => h - (i - lo) / (hi - lo) * h;
    double x(int k) => left + (days.length == 1 ? w / 2 : k / (days.length - 1) * w);

    final grid = Paint()
      ..color = look.line
      ..strokeWidth = 1;
    final step = hi - lo > 8 ? 2 : 1;
    for (var r = lo; r <= hi; r += step) {
      canvas.drawLine(Offset(left, y(r.toDouble())), Offset(size.width, y(r.toDouble())), grid);
      final tp = TextPainter(text: TextSpan(text: kGradeLadder[r], style: look.text(13, color: look.ink)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(left - tp.width - 8, y(r.toDouble()) - tp.height / 2));
    }
    canvas.drawLine(Offset(left, 0), Offset(left, h), Paint()..color = look.muted);
    canvas.drawLine(Offset(left, h), Offset(size.width, h), Paint()..color = look.muted);
    // A month label where each month starts (or the day, for short spans).
    final span = days.last.difference(days.first).inDays;
    final every = (days.length / 5).ceil();
    for (var k = 0; k < days.length; k++) {
      final d = days[k];
      final starts = span > 70 ? k > 0 && d.month != days[k - 1].month : k % every == 0;
      if (!starts) continue;
      final label = span > 70 ? _months[d.month - 1] : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      final tp = TextPainter(text: TextSpan(text: label, style: look.text(12, color: look.muted)), textDirection: TextDirection.ltr)..layout();
      final dx = (x(k) - tp.width / 2).clamp(left, size.width - tp.width).toDouble();
      canvas.drawLine(Offset(x(k), h), Offset(x(k), h + 4), Paint()..color = look.muted);
      tp.paint(canvas, Offset(dx, h + 8));
    }

    void series(List<double?> pts, Color c) {
      final line = Path(), fill = Path();
      var open = false;
      var startK = 0;
      for (var k = 0; k < pts.length; k++) {
        final p = pts[k];
        if (p == null) {
          if (open) fill.lineTo(x(k - 1), h);
          open = false;
          continue;
        }
        if (open) {
          line.lineTo(x(k), y(p));
          fill.lineTo(x(k), y(p));
        } else {
          startK = k;
          line.moveTo(x(k), y(p));
          fill
            ..moveTo(x(startK), h)
            ..lineTo(x(k), y(p));
          open = true;
        }
      }
      if (open) fill.lineTo(x(pts.length - 1), h);
      canvas.drawPath(fill, Paint()..color = c.withValues(alpha: 0.22));
      canvas.drawPath(
        line,
        Paint()
          ..color = c
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    if (top != null) series(top!, _pink);
    if (flash != null) series(flash!, _wine);
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => old.top != top || old.flash != flash || old.look != look;
}
