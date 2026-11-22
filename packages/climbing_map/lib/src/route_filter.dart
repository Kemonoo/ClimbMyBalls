part of '../climbing_map.dart';

/// What the boulder page knows about a route beyond the route itself: what
/// people think of it and what you did on it.
///
/// [grade] is the community grade ([averageGrade]); '' until someone votes.
typedef RouteSummary = ({double stars, int ratings, Set<String> tags, bool topped, bool project, String grade});

/// Everyone's opinions of some routes and your ascents, as one summary each.
Map<String, RouteSummary> routeSummaries(Iterable<String> ids, List<(String, Opinion)> opinions, Set<String> topped, String? me, {Map<String, Place> routes = const {}}) {
  final by = <String, List<Opinion>>{};
  for (final (id, o) in opinions) {
    (by[id] ??= []).add(o);
  }
  return {
    for (final id in ids)
      id: () {
        final os = by[id] ?? const <Opinion>[];
        final rated = [
          for (final o in os)
            if (o.stars > 0) o.stars,
        ];
        return (
          stars: rated.isEmpty ? 0.0 : rated.reduce((a, b) => a + b) / rated.length,
          ratings: rated.length,
          tags: {for (final o in os) ...o.tags},
          topped: topped.contains(id),
          project: os.any((o) => o.userId == me && o.project),
          grade: switch (routes[id]) {
            final p? => averageGrade(p.grade, p.isRope ? GradeSystem.uiaa : GradeSystem.font, [for (final o in os) o.grade]) ?? '',
            null => '',
          },
        );
      }(),
  };
}

enum RouteShow { all, notTopped, topped, projects }

/// The boulder page's filters. Grade bounds are [gradeSteps] indexes; null
/// means no bound.
class RouteFilter {
  const RouteFilter({this.show = RouteShow.all, this.fontMin, this.fontMax, this.uiaaMin, this.uiaaMax, this.minStars = 0, this.tags = const {}});

  final RouteShow show;
  final int? fontMin, fontMax, uiaaMin, uiaaMax;
  final int minStars;
  final Set<String> tags;

  bool get isEmpty => active == 0;

  /// How many filters are on, for the button's badge.
  int get active =>
      (show == RouteShow.all ? 0 : 1) +
      (fontMin != null || fontMax != null ? 1 : 0) +
      (uiaaMin != null || uiaaMax != null ? 1 : 0) +
      (minStars > 0 ? 1 : 0) +
      tags.length;

  bool matches(Place p, RouteSummary? s) {
    final topped = s?.topped ?? false;
    switch (show) {
      case RouteShow.all:
        break;
      case RouteShow.notTopped:
        if (topped) return false;
      case RouteShow.topped:
        if (!topped) return false;
      case RouteShow.projects:
        if (!(s?.project ?? false)) return false;
    }
    final scale = p.isRope ? GradeSystem.uiaa : GradeSystem.font;
    final lo = p.isRope ? uiaaMin : fontMin, hi = p.isRope ? uiaaMax : fontMax;
    if (lo != null || hi != null) {
      final g = gradeStep(p.grade, scale);
      if (g == null || (lo != null && g < lo) || (hi != null && g > hi)) return false;
    }
    if (minStars > 0 && (s == null || s.ratings == 0 || s.stars < minStars)) return false;
    if (tags.isNotEmpty && !(s?.tags.containsAll(tags) ?? false)) return false;
    return true;
  }

  RouteFilter copyWith({
    RouteShow? show,
    int? Function()? fontMin,
    int? Function()? fontMax,
    int? Function()? uiaaMin,
    int? Function()? uiaaMax,
    int? minStars,
    Set<String>? tags,
  }) => RouteFilter(
    show: show ?? this.show,
    fontMin: fontMin != null ? fontMin() : this.fontMin,
    fontMax: fontMax != null ? fontMax() : this.fontMax,
    uiaaMin: uiaaMin != null ? uiaaMin() : this.uiaaMin,
    uiaaMax: uiaaMax != null ? uiaaMax() : this.uiaaMax,
    minStars: minStars ?? this.minStars,
    tags: tags ?? this.tags,
  );
}

/// The filters sheet; returns the new filter, or null when dismissed.
Future<RouteFilter?> showRouteFilterSheet(BuildContext context, RouteFilter start, {required bool rope}) => showModalBottomSheet<RouteFilter>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var f = start;
    return StatefulBuilder(
      builder: (context, set) {
        final text = Theme.of(context).textTheme;
        final scale = rope ? GradeSystem.uiaa : GradeSystem.font;
        final steps = gradeSteps(scale);
        final lo = (rope ? f.uiaaMin : f.fontMin) ?? 0, hi = (rope ? f.uiaaMax : f.fontMax) ?? steps.length - 1;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Filters', style: text.titleLarge)),
                    TextButton(onPressed: () => set(() => f = const RouteFilter()), child: const Text('Reset')),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownMenu<RouteShow>(
                  initialSelection: f.show,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Show'),
                  requestFocusOnTap: false,
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: RouteShow.all, label: 'All routes'),
                    DropdownMenuEntry(value: RouteShow.notTopped, label: 'Not topped yet'),
                    DropdownMenuEntry(value: RouteShow.topped, label: 'Topped by me'),
                    DropdownMenuEntry(value: RouteShow.projects, label: 'My projects'),
                  ],
                  onSelected: (v) => set(() => f = f.copyWith(show: v)),
                ),
                const SizedBox(height: 16),
                Text('${rope ? 'Rope' : 'Boulder'} grade: ${steps[lo]} to ${steps[hi]}', style: text.titleSmall),
                RangeSlider(
                  values: RangeValues(lo.toDouble(), hi.toDouble()),
                  min: 0,
                  max: (steps.length - 1).toDouble(),
                  divisions: steps.length - 1,
                  labels: RangeLabels(steps[lo], steps[hi]),
                  onChanged: (v) => set(() {
                    final a = v.start.round(), b = v.end.round();
                    final mn = a == 0 ? null : a, mx = b == steps.length - 1 ? null : b;
                    f = rope ? f.copyWith(uiaaMin: () => mn, uiaaMax: () => mx) : f.copyWith(fontMin: () => mn, fontMax: () => mx);
                  }),
                ),
                const SizedBox(height: 8),
                Text(f.minStars == 0 ? 'Stars: any' : 'Stars: ${f.minStars} and up', style: text.titleSmall),
                Slider(
                  value: f.minStars.toDouble(),
                  max: 5,
                  divisions: 5,
                  label: f.minStars == 0 ? 'Any' : '${f.minStars}★',
                  onChanged: (v) => set(() => f = f.copyWith(minStars: v.round())),
                ),
                for (final group in const ['Style', 'Wall', 'Holds']) ...[
                  const SizedBox(height: 8),
                  Text(group, style: text.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in routeTags.where((t) => t.group == group))
                        FilterChip(
                          label: Text(t.label, maxLines: 1, softWrap: false),
                          selected: f.tags.contains(t.id),
                          onSelected: (on) => set(() => f = f.copyWith(tags: {...f.tags.where((x) => x != t.id), if (on) t.id})),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Show routes')),
              ],
            ),
          ),
        );
      },
    );
  },
);
