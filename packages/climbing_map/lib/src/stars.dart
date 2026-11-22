part of '../climbing_map.dart';

// Stars and favourites (#518). A star is a like, on anything: an area, a
// boulder, a route (only once you topped it), a section photo, a guide. Its
// count is public and never summed upward. A favourite is your own bookmark
// for a trip: only you see it.

/// What a star or favourite is on, as the database names it.
abstract final class StarOn {
  static const place = 'place', topo = 'topo', guide = 'guide';
}

/// The star of one thing: filled when it's yours, with everyone's count.
class StarButton extends StatefulWidget {
  const StarButton({super.key, required this.editor, required this.kind, required this.id, this.blocked});
  final PlaceEditor editor;
  final String kind, id;

  /// Why you can't star it yet ("Top it first"), or null when you can.
  final String? blocked;

  @override
  State<StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends State<StarButton> {
  @override
  void initState() {
    super.initState();
    widget.editor.loadStars(widget.kind, [widget.id]).then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _toggle() async {
    final e = widget.editor;
    void say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    if (!e.signedIn) return say('Sign in on the Friends tab to star things.');
    if (widget.blocked != null) return say(widget.blocked!);
    final err = await e.setStar(widget.kind, widget.id, !e.starredByMe(widget.kind, widget.id));
    if (!mounted) return;
    if (err != null) return say(err);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    final mine = e.starredByMe(widget.kind, widget.id);
    final n = e.starsOf(widget.kind, widget.id);
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: mine ? Colors.amber : null),
      onPressed: _toggle,
      icon: Icon(mine ? Icons.star_rounded : Icons.star_outline_rounded, color: mine ? Colors.amber : null),
      label: Text('$n', maxLines: 1, softWrap: false),
    );
  }
}

/// Saves a place, photo or guide for later (only you see it).
class FavouriteButton extends StatefulWidget {
  const FavouriteButton({super.key, required this.editor, required this.kind, required this.id});
  final PlaceEditor editor;
  final String kind, id;

  @override
  State<FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends State<FavouriteButton> {
  @override
  Widget build(BuildContext context) {
    final e = widget.editor;
    final on = e.isFavourite(widget.kind, widget.id);
    return IconButton(
      tooltip: on ? 'Saved: tap to remove' : 'Save for later',
      isSelected: on,
      icon: const Icon(Icons.bookmark_border),
      selectedIcon: const Icon(Icons.bookmark),
      onPressed: () async {
        void say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
        if (!e.signedIn) return say('Sign in on the Friends tab to save things.');
        final err = await e.setFavourite(widget.kind, widget.id, !on);
        if (!mounted) return;
        if (err != null) return say(err);
        setState(() {});
        say(on ? 'Removed from saved.' : 'Saved. Find it under Saved on the map.');
      },
    );
  }
}

/// How a list of routes can be ordered.
enum RouteSort {
  grade('By grade'),
  number('By number'),
  name('By name'),
  stars('Most stars'),
  ascents('Most ascents'),
  flashes('Most flashes');

  const RouteSort(this.label);
  final String label;
}

/// Orders [routes] by [sort]; ties by grade, then name.
List<Place> sortRoutes(List<Place> routes, RouteSort sort, {Map<String, RouteSummary> summaries = const {}, Map<String, String> numbers = const {}}) {
  int byGrade(Place a, Place b) {
    final c = gradeOrder(a.grade, a.gradeSystem).compareTo(gradeOrder(b.grade, b.gradeSystem));
    return c != 0 ? c : a.name.compareTo(b.name);
  }

  int most(int Function(RouteSummary s) f, Place a, Place b) {
    final c = (summaries[b.id] == null ? 0 : f(summaries[b.id]!)).compareTo(summaries[a.id] == null ? 0 : f(summaries[a.id]!));
    return c != 0 ? c : byGrade(a, b);
  }

  return [...routes]..sort(switch (sort) {
    RouteSort.grade => byGrade,
    RouteSort.number => (a, b) => _numberOrder(numbers[a.id] ?? '').compareTo(_numberOrder(numbers[b.id] ?? '')),
    RouteSort.name => (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    RouteSort.stars => (a, b) => most((s) => s.stars, a, b),
    RouteSort.ascents => (a, b) => most((s) => s.tops, a, b),
    RouteSort.flashes => (a, b) => most((s) => s.flashes, a, b),
  });
}

/// Your saved places, photos and guides, to open one (the map's Saved chip).
Future<void> showSavedSheet(BuildContext context, PlaceEditor e, PlaceTree tree, void Function(Place p) open) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final items = [
      for (final (kind, id) in e.favourites)
        if (switch (kind) {
          StarOn.place => tree[id],
          StarOn.topo => tree[e.topoById(id)?.placeId ?? ''],
          _ => tree[e.guideById(id)?.placeId ?? ''],
        }
            case final p?)
          (kind, id, p),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Saved'),
              subtitle: Text(items.isEmpty ? 'Nothing yet. Tap the bookmark on an area, boulder, route or photo to keep it here.' : 'What you saved for your trips.'),
            ),
            for (final (kind, _, p) in items)
              ListTile(
                leading: Icon(kind == StarOn.topo ? Icons.photo_outlined : kind == StarOn.guide ? Icons.menu_book_outlined : placeIcon(p)),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  kind == StarOn.topo ? 'photo' : kind == StarOn.guide ? 'guide' : kindLabel(p.kind),
                  if (tree.pathTo(p.id) case final path when path.length > 1) path[path.length - 2].name,
                ].join(' · ')),
                onTap: () {
                  Navigator.pop(context);
                  open(p);
                },
              ),
          ],
        ),
      ),
    );
  },
);
