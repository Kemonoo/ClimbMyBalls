part of '../climbing_ui.dart';

/// A month of climbing: each day you climbed shows that session's top 10
/// grade (a day with two sessions shows the better one), and the month's own
/// top 10 average sits above. Tap a day for its session.
class _ClimbCalendar extends StatefulWidget {
  const _ClimbCalendar({required this.look, required this.sessions});
  final ClimbTheme look;
  final List<ClimbSession> sessions;

  @override
  State<_ClimbCalendar> createState() => _ClimbCalendarState();
}

class _ClimbCalendarState extends State<_ClimbCalendar> {
  int back = 0; // months before this one

  static const _names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final now = host.now();
    final month = DateTime(now.year, now.month - back);
    final next = DateTime(month.year, month.month + 1);
    final daysIn = DateTime(month.year, month.month + 1, 0).day;
    final lead = month.weekday - 1;
    final weeks = ((lead + daysIn) / 7).ceil();
    final byDay = <int, ClimbSession>{};
    for (final s in widget.sessions) {
      if (s.start.year != month.year || s.start.month != month.month) continue;
      final had = byDay[s.start.day];
      if (had == null || (s.topGradeIndex ?? -1) > (had.topGradeIndex ?? -1)) byDay[s.start.day] = s;
    }
    final first = widget.sessions.isEmpty ? now : widget.sessions.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final canBack = DateTime(first.year, first.month).isBefore(month);
    final end = next.isAfter(now) ? now : next.subtract(const Duration(seconds: 1));
    final level = levelFrom(widget.sessions, now: end, since: month);
    final count = widget.sessions.where((s) => !s.start.isBefore(month) && s.start.isBefore(next)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Calendar', style: look.text(24, bold: true))),
          IconButton(tooltip: 'Previous month', onPressed: canBack ? () => setState(() => back++) : null, icon: const Icon(Icons.chevron_left_rounded)),
          Text('${_names[month.month - 1]}${month.year == now.year ? '' : ' ${month.year}'}', style: look.text(15, bold: true)),
          IconButton(tooltip: 'Next month', onPressed: back > 0 ? () => setState(() => back--) : null, icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        Row(children: [
          Expanded(child: Text(_plural(count, 'session'), maxLines: 1, overflow: TextOverflow.ellipsis, style: look.text(15, color: look.muted))),
          if (level != null) ...[
            Text('Month ', style: look.text(15, color: look.muted)),
            _GradeWithPercent(look: look, level: level, size: 20),
          ],
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(child: Text(l, textAlign: TextAlign.center, style: look.text(12, bold: true, color: look.muted))),
        ]),
        const SizedBox(height: 6),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: switch (w * 7 + i - lead + 1) {
                    final d when d >= 1 && d <= daysIn => _day(context, look, DateTime(month.year, month.month, d), byDay[d], now),
                    _ => const AspectRatio(aspectRatio: 1),
                  },
                ),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _day(BuildContext context, ClimbTheme look, DateTime date, ClimbSession? s, DateTime now) {
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    final grade = s?.topLevel?.grade;
    final style = s?.style ?? ClimbStyle.boulder;
    final c = s == null ? null : (style == ClimbStyle.boulder ? _pink : look.calm);
    return AspectRatio(
      aspectRatio: 1,
      child: Semantics(
        button: s != null,
        label: s == null ? '${date.day}' : '${date.day}: ${style.title(s.outdoor)}${grade == null ? '' : ', $grade'}${s.place.isEmpty ? '' : ' at ${s.place}'}',
        child: Material(
          color: c?.withValues(alpha: 0.85) ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: today ? BorderSide(color: look.ink, width: 2) : (s == null ? BorderSide(color: look.line, width: 1) : BorderSide.none),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: s == null ? null : () => showClimbSessionSheet(context, s.id),
            child: ExcludeSemantics(
              child: Stack(children: [
                Positioned(left: 5, top: 3, child: Text('${date.day}', style: look.text(10, color: s == null ? look.muted : Colors.white))),
                if (s != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(grade ?? '·', style: look.text(13, bold: true, color: Colors.white)),
                    ),
                  ),
                if (s != null && s.outdoor) const Positioned(right: 3, top: 3, child: Icon(Icons.landscape_outlined, size: 11, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
