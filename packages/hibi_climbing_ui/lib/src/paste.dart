part of '../climbing_ui.dart';

/// Paste the description TopLogger writes to Strava; link it to the Health
/// Connect workout it came from, so the visit counts once.
Future<void> showPasteSheet(BuildContext context, {ClimbWorkout? workout}) {
  host.log('climb_paste_opened', {'fromWorkout': workout != null});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PasteClimbsSheet(workout: workout),
  );
}

class PasteClimbsSheet extends StatefulWidget {
  const PasteClimbsSheet({super.key, this.workout});
  final ClimbWorkout? workout;

  @override
  State<PasteClimbsSheet> createState() => _PasteClimbsSheetState();
}

class _PasteClimbsSheetState extends State<PasteClimbsSheet> {
  final text = TextEditingController();
  late List<ClimbWorkout> options;
  ClimbWorkout? link;
  bool chose = false; // picked a visit by hand: a background sync won't change it
  bool syncing = false;
  DateTime day = host.now();
  TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
  int? minutes; // how long, when it isn't linked to a Health Connect workout
  WallAngle angle = WallAngle.vertical;
  // The TopLogger session behind a pasted link, when it could be fetched.
  String? fetchedFor;
  TopLoggerSession? tl;
  bool fetching = false;
  String? tlError;

  @override
  void initState() {
    super.initState();
    options = linkCandidatesOf(host.workouts, host.store.sessions, now: host.now());
    final w = widget.workout;
    if (w != null && !options.any((o) => o.id == w.id)) options.insert(0, w);
    link = w ?? options.firstOrNull;
    // Strava may pass the activity description (TopLogger's grades) on as notes.
    if (w != null && w.notes.isNotEmpty) text.text = w.notes;
    text.addListener(_onText);
    _onText();
    // A session from yesterday may not be synced yet: fetch the latest from Health Connect.
    syncing = true;
    host.refreshWorkouts().then((_) {
      if (!mounted) return;
      setState(() {
        syncing = false;
        final fresh = linkCandidatesOf(host.workouts, host.store.sessions, now: host.now());
        for (final o in options) {
          if (!fresh.any((f) => f.id == o.id)) fresh.add(o);
        }
        options = fresh;
        if (!chose && widget.workout == null) link = options.firstOrNull;
      });
    });
  }

  void _onText() {
    final l = findTopLoggerLink(text.text);
    if (l?.sessionId != fetchedFor) {
      fetchedFor = l?.sessionId;
      tl = null;
      tlError = null;
      if (l != null) _fetch(l);
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetch(TopLoggerLink l) async {
    setState(() => fetching = true);
    try {
      final s = await fetchTopLoggerSession(l);
      if (!mounted || fetchedFor != l.sessionId) return;
      host.log('toplogger_fetched', {'climbs': s.climbs.length});
      setState(() {
        fetching = false;
        tl = s;
        // TopLogger knows the day: use it, and the Health Connect visit from that day if there is one.
        final d = s.day;
        if (d != null && !chose && widget.workout == null) {
          day = DateTime(d.year, d.month, d.day, 12);
          link = options.where((o) => host.dayKey(o.start) == host.dayKey(day)).firstOrNull;
        }
      });
    } catch (e) {
      if (!mounted || fetchedFor != l.sessionId) return;
      host.log('toplogger_failed', {'error': '$e'});
      setState(() {
        fetching = false;
        tlError = '$e';
      });
    }
  }

  /// What will be saved: TopLogger's own data when fetched, else the pasted text.
  StravaClimbText get _result {
    final s = tl;
    if (s == null) return parseStravaClimbText(text.text);
    return StravaClimbText(place: s.gym, climbs: s.climbs, unknown: const [], ungraded: s.climbs.where((c) => !c.isGraded).length);
  }

  bool get _duplicate => tl != null && host.store.sessions.any((c) => c.topLoggerId == tl!.id);

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: start);
    if (t != null) setState(() => start = t);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) text.text = d!.text!;
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: host.now().subtract(const Duration(days: 365 * 3)),
      lastDate: host.now(),
    );
    if (d != null) setState(() => day = DateTime(d.year, d.month, d.day, 12));
  }

  void _save(StravaClimbText r) {
    final w = link;
    final s = ClimbSession(
      id: host.store.newId(),
      start: w?.start ?? DateTime(day.year, day.month, day.day, start.hour, start.minute),
      end: w?.end ?? (minutes == null ? null : DateTime(day.year, day.month, day.day, start.hour, start.minute).add(Duration(minutes: minutes!))),
      place: r.place,
      climbs: [for (final c in r.climbs) c.copyWith(angle: angle)],
      source: tl != null ? 'toplogger' : 'strava-text',
      sourceId: w?.id,
      topLoggerId: tl?.id,
      note: tl?.tries == null ? '' : '${tl!.tries} tries in all (TopLogger)',
    );
    host.store.add(s);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${_plural(s.climbs.length, 'climb')}${r.place.isEmpty ? '' : ' at ${r.place}'}.')));
  }

  @override
  Widget build(BuildContext context) {
    final look = host.theme(context);
    final r = _result;
    final dup = _duplicate;
    final ready = r.climbs.isNotEmpty && !dup && !fetching;
    final flashed = r.climbs.where((c) => c.outcome == ClimbOutcome.flash).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paste from Strava', style: look.text(24, bold: true)),
              const SizedBox(height: 4),
              Text(
                'Open the climbing activity in Strava, copy its description (the part TopLogger wrote), and paste it here.',
                style: look.text(12, color: look.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: 'Boulders: ⚡ 6ʙ⁺, 6ᴀ … ✅ 6ᴄ …',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _fromClipboard, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste from clipboard')),
              ),
              if (fetching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('Getting the session from TopLogger…', style: look.text(12, color: look.muted)),
                    ],
                  ),
                )
              else if (tl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    dup
                        ? 'Already added: this TopLogger session is in your sessions.'
                        : 'From TopLogger${tl!.day == null ? '' : ', ${host.dayLabel(host.dayKey(DateTime(tl!.day!.year, tl!.day!.month, tl!.day!.day, 12))).toLowerCase()}'}'
                              '${tl!.tries == null ? '' : ' · ${tl!.tries} tries'}: names, hold colours and repeats included.',
                    style: look.text(12, color: dup ? look.accentDeep : look.muted, height: 1.4),
                  ),
                )
              else if (tlError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text("Couldn't reach TopLogger, so the text is used instead.", style: look.text(12, color: look.muted)),
                ),
              if (text.text.trim().isNotEmpty) ...[
                if (ready) ...[
                  Text(
                    [if (r.place.isNotEmpty) r.place, _plural(r.climbs.length, 'climb'), '$flashed flashed', if (r.ungraded > 0) '${r.ungraded} without a grade'].join(' · '),
                    style: look.text(15, bold: true),
                  ),
                  const SizedBox(height: 8),
                  ClimbStrip(climbs: r.climbs),
                ] else
                  Text('No climbs found. The text should have a ⚡ or ✅ list of grades.', style: look.text(15, color: look.accentDeep, height: 1.4)),
                if (r.unknown.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text("Couldn't read: ${r.unknown.join(', ')}. Those are left out.", style: look.text(12, color: look.accentDeep, height: 1.4)),
                  ),
              ],
              const SizedBox(height: 20),
              Text('Which visit is this?', style: look.text(15, bold: true)),
              const SizedBox(height: 2),
              Text('Linking it means the visit counts once, with the workout\'s time.', style: look.text(12, color: look.muted, height: 1.4)),
              RadioGroup<String>(
                groupValue: link?.id ?? '',
                onChanged: (v) => setState(() {
                  chose = true;
                  link = options.where((o) => o.id == v).firstOrNull;
                }),
                child: Column(
                  children: [
                    for (final o in options.take(5))
                      RadioListTile<String>(
                        value: o.id,
                        contentPadding: EdgeInsets.zero,
                        title: Text(o.title.isNotEmpty ? o.title : (o.type == 'climb' ? 'Climb' : 'Workout'), style: look.text(15, bold: true)),
                        subtitle: Text(_workoutLabel(o), style: look.text(12, color: look.muted)),
                      ),
                    RadioListTile<String>(
                      value: '',
                      contentPadding: EdgeInsets.zero,
                      title: Text('Not in Health Connect', style: look.text(15, bold: true)),
                      subtitle: Text(syncing ? 'Checking Health Connect…' : 'Set the day and length below', style: look.text(12, color: look.muted)),
                    ),
                  ],
                ),
              ),
              if (link == null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _pickDay,
                          icon: const Icon(Icons.event_rounded),
                          label: Text(host.dayLabel(host.dayKey(day)), style: look.text(15, bold: true)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text(start.format(context), style: look.text(15, bold: true)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('How long', style: look.text(15, bold: true)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in const [null, 60, 90, 120, 150, 180, 240])
                      ChoiceChip(
                        label: Text(m == null ? 'Not sure' : _fmtMinutes(m)),
                        selected: minutes == m,
                        onSelected: (_) => setState(() => minutes = m),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text('Wall', style: look.text(15, bold: true)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in WallAngle.values)
                    ChoiceChip(label: Text(a.label), selected: angle == a, onSelected: (_) => setState(() => angle = a)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: ready ? () => _save(r) : null,
                  style: FilledButton.styleFrom(backgroundColor: look.accent, shape: const StadiumBorder()),
                  child: Text(
                    ready ? 'Save ${_plural(r.climbs.length, 'climb')}' : 'Paste the text first',
                    style: look.text(15, bold: true, color: ready ? look.onAccent : look.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
