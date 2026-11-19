part of '../climbing_ui.dart';

class _SessionList extends StatefulWidget {
  const _SessionList({required this.look, required this.sessions});
  final ClimbTheme look;
  final List<ClimbSession> sessions; // newest first

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  int shown = 10;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in widget.sessions.take(shown)) _SessionRow(look: look, session: s),
        if (widget.sessions.length > shown)
          TextButton(onPressed: () => setState(() => shown += 10), child: const Text('Show older sessions')),
      ],
    );
  }
}

/// 'Yesterday', or 'Fri 02/10/26' further back.
String _sessionDay(ClimbSession s) {
  final day = host.dayKey(s.start);
  return day == host.dayKey(host.now()) || day == host.dayBefore(host.dayKey(host.now())) ? host.dayLabel(day) : '${_weekdays[s.start.weekday - 1]} ${_ddmmyy(s.start)}';
}

String _sessionMeta(ClimbSession s) {
  final unsent = s.climbs.length - s.sends;
  return [
    _plural(s.sends, 'send'),
    if (s.flashes > 0) '${s.flashes} flashed',
    if (unsent > 0) '$unsent tried',
    if (s.tries != null && s.climbs.any((c) => c.attempts != null)) _plural(s.tries!, 'try', 'tries'),
    if (s.minutes != null && s.minutes! > 0) _fmtMinutes(s.minutes!),
  ].join(' · ');
}

/// TopLogger's three session numbers: top 10 average, flash %, repeat %.
class _SessionStats extends StatelessWidget {
  const _SessionStats({required this.look, required this.session});
  final ClimbTheme look;
  final ClimbSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    Widget stat(String label, Widget value, [int flex = 1]) => Expanded(
      flex: flex,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: look.text(15, color: look.muted)),
        const SizedBox(height: 2),
        value,
      ]),
    );
    final big = look.text(24, bold: true);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      stat('Top 10 average', s.topLevel == null ? Text('–', style: big) : _GradeWithPercent(look: look, level: s.topLevel!, size: 24), 2),
      stat('Flash', Text('${(s.flashShare * 100).round()}%', style: big)),
      stat('Repeats', Text('${(s.repeatShare * 100).round()}%', style: big)),
    ]);
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.look, required this.session});
  final ClimbTheme look;
  final ClimbSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: look.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showClimbSessionSheet(context, s.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_sessionDay(s), style: look.text(15, color: look.muted)),
                const SizedBox(height: 4),
                Text(s.style.title(s.outdoor), style: look.text(22, bold: true)),
                if (s.place.isNotEmpty) Text('At ${s.place}', style: look.text(17, color: look.muted)),
                const SizedBox(height: 12),
                _SessionStats(look: look, session: s),
                const SizedBox(height: 12),
                Semantics(label: _sessionMeta(s), child: ExcludeSemantics(child: ClimbStrip(climbs: s.climbs))),
                const SizedBox(height: 6),
                Text(_sessionMeta(s), style: look.text(12, color: look.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Health Connect climb with no grades: offer to paste them.
class _BareWorkoutRow extends StatelessWidget {
  const _BareWorkoutRow({required this.look, required this.workout});
  final ClimbTheme look;
  final ClimbWorkout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final found = parseStravaClimbText(w.notes).climbs.length;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showPasteSheet(context, workout: w),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Icon(Icons.terrain_rounded, color: look.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  found > 0
                      ? '${host.dayLabel(host.dayKey(w.start))}: ${_fmtMinutes(w.seconds ~/ 60)} climbing from ${host.sourceLabel(w.source)}. ${_plural(found, 'climb')} found, tap to add'
                      : '${host.dayLabel(host.dayKey(w.start))}: ${_fmtMinutes(w.seconds ~/ 60)} climbing from ${host.sourceLabel(w.source)}, no grades yet. Paste them',
                  style: look.text(15, color: look.accentDeep, height: 1.35),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: look.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- one session ----------

IconData _outcomeIcon(ClimbOutcome o) => switch (o) {
  ClimbOutcome.flash => Icons.bolt_rounded,
  ClimbOutcome.sent => Icons.check_rounded,
  ClimbOutcome.tried => Icons.close_rounded,
};

/// A climb in words, for screen readers: "6A+, sent, 4 tries, repeat, Pinch roof".
String climbSpoken(Climb c) => [
      c.isGraded ? c.grade : 'Ungraded',
      c.outcome.label.toLowerCase(),
      if ((c.tries ?? 1) > 1) '${c.tries} tries',
      if (c.repeat) 'repeat',
      if (c.name.isNotEmpty) c.name,
    ].join(', ');

/// "6A+" with how it went as icons, for chips. Semantics read it out in words.
class ClimbLabel extends StatelessWidget {
  const ClimbLabel({super.key, required this.climb, required this.look, this.withName = false});
  final Climb climb;
  final ClimbTheme look;
  final bool withName;

  @override
  Widget build(BuildContext context) {
    final c = climb;
    return Semantics(
      label: withName ? climbSpoken(c) : climbSpoken(c.copyWith(name: '')),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (holdColor(c.hold) case final h?) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: h, shape: BoxShape.circle, border: Border.all(color: look.ink.withValues(alpha: 0.35))),
              ),
              const SizedBox(width: 6),
            ],
            Text(c.isGraded ? c.grade : '?', style: look.text(14, bold: true)),
            const SizedBox(width: 4),
            Icon(_outcomeIcon(c.outcome), size: 16, color: look.ink),
            if ((c.tries ?? 1) > 1) Text('×${c.tries}', style: look.text(12, color: look.muted)),
            if (c.repeat) Icon(Icons.replay_rounded, size: 14, color: look.muted),
            if (withName && c.name.isNotEmpty) Text(' ${c.name}', style: look.text(14)),
          ],
        ),
      ),
    );
  }
}

Future<void> showClimbSessionSheet(BuildContext context, String id) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ListenableBuilder(
    listenable: host.listenable,
    builder: (context, _) {
      final look = host.theme(context);
      final s = host.store.sessions.where((x) => x.id == id).firstOrNull;
      if (s == null) return const SizedBox(height: 48);
      final linked = s.sourceId == null ? null : host.workoutById(s.sourceId);
      // Best first, like TopLogger's list; tries and "?" climbs at the end.
      final sorted = [...s.climbs]..sort((a, b) => b.points != a.points ? b.points.compareTo(a.points) : (b.index ?? -1).compareTo(a.index ?? -1));
      final sends = [for (final c in sorted) if (c.outcome.isSend) c];
      final tried = [for (final c in sorted) if (!c.outcome.isSend) c];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_sessionDay(s), style: look.text(15, color: look.muted)),
              Text(s.style.title(s.outdoor), style: look.text(22, bold: true)),
              if (s.place.isNotEmpty)
                InkWell(
                  onTap: () => showPlaceSheet(context, name: s.place),
                  child: Text('At ${s.place}', style: look.text(17, color: look.muted).copyWith(decoration: TextDecoration.underline)),
                ),
              const SizedBox(height: 4),
              Text(_sessionMeta(s), style: look.text(15, color: look.muted)),
              const SizedBox(height: 16),
              _SessionStats(look: look, session: s),
              const SizedBox(height: 24),
              Text('Boulders', style: look.text(24, bold: true)),
              _PointsTable(look: look, rows: [for (final c in sends) (c, c.name, '')]),
              if (tried.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Tried', style: look.text(15, bold: true, color: look.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in tried)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: look.line, width: 1.5)),
                        child: ClimbLabel(climb: c, look: look, withName: true),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (linked != null)
                Text(
                  'Linked to your ${_fmtMinutes(linked.seconds ~/ 60)} session from ${host.sourceLabel(linked.source)}, '
                  '${fmtClock(linked.start)}–${fmtClock(linked.end)}.',
                  style: look.text(12, color: look.muted, height: 1.4),
                )
              else
                TextButton.icon(
                  onPressed: () => _pickLink(context, look, s),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Link to a Health Connect workout'),
                ),
              if (s.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.note, style: look.text(15))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          host.log('climb_session_delete');
                          Navigator.pop(context);
                          final gone = host.store.remove(s.id);
                          if (gone == null) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Session removed.'),
                              action: SnackBarAction(label: 'Undo', onPressed: () => host.store.add(gone)),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: look.line, width: 1.5)),
                        icon: Icon(Icons.delete_outline_rounded, color: look.ink),
                        label: Text('Remove', style: look.text(15, bold: true)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          openClimbLog(context, existing: s);
                        },
                        style: FilledButton.styleFrom(backgroundColor: look.accent, shape: const StadiumBorder()),
                        icon: Icon(Icons.edit_rounded, color: look.onAccent),
                        label: Text('Edit', style: look.text(15, bold: true, color: look.onAccent)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  ),
);

String _workoutLabel(ClimbWorkout w) => [
  host.dayLabel(host.dayKey(w.start)),
  '${fmtClock(w.start)}–${fmtClock(w.end)}',
  _fmtMinutes(w.seconds ~/ 60),
  host.sourceLabel(w.source),
].join(' · ');

Future<void> _pickLink(BuildContext context, ClimbTheme look, ClimbSession s) async {
  final options = linkCandidatesOf(host.workouts, host.store.sessions, now: host.now(), days: 30);
  final w = await showModalBottomSheet<ClimbWorkout>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        children: [
          Text('Which workout was this?', style: look.text(20, bold: true)),
          const SizedBox(height: 4),
          Text('Linking means the visit counts once on the body map, with the workout\'s time.', style: look.text(12, color: look.muted, height: 1.4)),
          const SizedBox(height: 8),
          if (options.isEmpty) Text('No climbs or workouts in the last 30 days.', style: look.text(15, color: look.muted)),
          for (final o in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: Icon(o.type == 'climb' ? Icons.terrain_rounded : Icons.sports_rounded),
              title: Text(o.title.isNotEmpty ? o.title : (o.type == 'climb' ? 'Climb' : 'Workout'), style: look.text(15, bold: true)),
              subtitle: Text(_workoutLabel(o), style: look.text(12, color: look.muted)),
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
    ),
  );
  if (w == null) return;
  host.store.update(s.copyWith(start: w.start, end: () => w.end, sourceId: () => w.id));
}

// ---------- logging ----------

Future<void> openClimbLog(BuildContext context, {ClimbSession? existing}) {
  host.log('climb_log_opened', {'edit': existing != null});
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClimbLogPage(existing: existing)));
}
