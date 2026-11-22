part of '../climbing_map.dart';

/// Saving places to the shared database (the app passes one when the build
/// has server keys). Null from [save] means it worked; else a message.
abstract class PlaceEditor {
  bool get signedIn;

  /// Your user id, to know which places you made.
  String? get me;

  /// Admins may change and delete anything.
  bool get isAdmin;

  /// A right of yours reaches this place: an edit right on it or on a place
  /// above it (apps/climb/supabase/006_roles.sql).
  bool mayEdit(String placeId);
  String? createdBy(String placeId);
  DateTime? createdAt(String placeId);

  /// A person's name by user id ('' when unknown).
  String nameOf(String? userId);
  String newId();
  Future<String?> save(Place p);
  Future<String?> delete(Place p);

  /// The sections (topos) of a boulder or wall, in order. Other angles of
  /// a section are not among them: see [anglesOf].
  List<Topo> toposOf(String placeId);

  /// The other photos of a section, from other angles (#469), oldest first.
  List<Topo> anglesOf(Topo section) => const [];

  /// The section's photo, or its second photo with [original].
  ImageProvider photoOf(Topo t, {bool original = false});

  /// A photo from the camera or the gallery, shrunk for upload; null when
  /// nothing was picked.
  Future<TopoPhoto?> pickPhoto({required bool camera});

  /// Saves [t], uploading [photo] first when the topo is new.
  Future<String?> saveTopo(Topo t, {TopoPhoto? photo});
  Future<String?> deleteTopo(Topo t);

  /// Everyone's ascents of a problem, newest first.
  Future<List<Ascent>> ascentsOf(String problemId);

  /// Logs your ascent today: 'flash', 'sent' or 'tried'.
  Future<String?> logAscent(String problemId, String outcome);
  Future<String?> removeAscent(String id);

  /// Moves one of your ascents to another day.
  Future<String?> setAscentDay(String id, DateTime day);

  /// Guides bundled with the app that an admin can add to a boulder.
  List<String> get guides;
  Future<String?> importGuide(String guide, Place boulder);

  /// Everyone's grade votes and stars on a route.
  Future<List<Opinion>> opinionsOf(String problemId) async => const [];

  /// Your grade vote ('' for none) and stars (0 for none) on a route.
  Future<String?> setOpinion(String problemId, {required String grade, required int stars, required List<String> tags, required bool project}) async => 'Not available here.';

  /// Everyone's opinions of several routes at once, for filtering a list.
  Future<List<(String, Opinion)>> opinionsOn(List<String> problemIds) async => const [];

  /// The routes you have flashed or topped.
  Future<Set<String>> toppedByMe() async => const {};

  /// A route's comments, oldest first.
  Future<List<RouteComment>> commentsOf(String problemId) async => const [];
  Future<String?> addComment(String problemId, String body) async => 'Not available here.';
  Future<String?> removeComment(String id) async => 'Not available here.';

  /// Makes your private route visible to everyone (#462). A place editor's
  /// route is verified at the same time.
  Future<String?> publish(Place p) async => 'Not available here.';

  /// Sets or clears a route's check mark (#467; place editors).
  Future<String?> setVerified(Place p, bool verified) async => 'Not available here.';

  /// Whether this build can keep places on the device for use without
  /// signal (#459).
  bool get canKeepOffline => false;

  /// Whether a place is kept on the device: saved itself or inside a saved
  /// place.
  bool isOffline(String placeId) => false;

  /// Keeps a place and everything in it (sections, photos) on the device;
  /// [progress] gets (photos done, photos in all). Null when it worked.
  Future<String?> keepOffline(String placeId, {void Function(int done, int total)? progress}) async => 'Not available here.';

  /// Stops keeping a place on the device and frees its photos.
  Future<void> forgetOffline(String placeId) async {}

  // ---- stars and favourites (#518); kind is a [StarOn] ----

  /// Fetches the star counts of [ids] (the last known ones without signal).
  Future<void> loadStars(String kind, List<String> ids) async {}
  int starsOf(String kind, String id) => 0;
  bool starredByMe(String kind, String id) => false;
  Future<String?> setStar(String kind, String id, bool on) async => 'Not available here.';
  bool isFavourite(String kind, String id) => false;
  Future<String?> setFavourite(String kind, String id, bool on) async => 'Not available here.';

  /// Your favourites, newest first, as (kind, id).
  List<(String, String)> get favourites => const [];

  /// A section photo by id, wherever it is.
  Topo? topoById(String id) => null;

  /// A guide by id, and the official guide of a place (#500).
  GuideInfo? guideById(String id) => null;
  GuideInfo? guideOf(String placeId) => null;

  /// Puts a proven community route into the main guide (#520; editors).
  Future<String?> addToGuide(Place route) async => 'Not available here.';

  /// How many people topped and flashed each route, for sorting.
  Future<Map<String, ({int tops, int flashes})>> ascentCounts(List<String> problemIds) async => const {};
}

/// A guide's name and credit (the Devín guide, 2020).
typedef GuideInfo = ({String id, String placeId, String name, String credit});

/// One logged ascent, for a route's page.
typedef Ascent = ({String id, String userId, String who, DateTime day, String outcome});

/// What one person thinks of a route: the grade it felt like ('' = no vote),
/// stars (0 = none), tags ([routeTags] ids), and whether it's their project.
typedef Opinion = ({String userId, String who, String grade, int stars, List<String> tags, bool project});

/// One comment under a route.
typedef RouteComment = ({String id, String userId, String who, String body, DateTime at});

/// You made it, a right of yours reaches it, or you're an admin.
bool canEdit(PlaceEditor? e, String placeId) =>
    e != null && e.signedIn && (e.isAdmin || e.mayEdit(placeId) || (e.me != null && e.createdBy(placeId) == e.me));

/// An admin or a place editor: may check routes as verified. Making a route
/// is not enough.
bool mayVerify(PlaceEditor? e, String placeId) => e != null && e.signedIn && (e.isAdmin || e.mayEdit(placeId));

/// The same for a section: by who made it, or by the place it hangs on.
bool canEditTopo(PlaceEditor? e, Topo t) => e != null && e.signedIn && (e.isAdmin || e.mayEdit(t.placeId) || (e.me != null && t.createdBy == e.me));

/// What a new place is, picked after its spot.
typedef PlaceDraft = ({PlaceKind kind, String name, String? parentId, bool outline});

const _newKinds = [PlaceKind.area, PlaceKind.sector, PlaceKind.boulder, PlaceKind.gymWall];

/// Kind, name and parent of a new place at [at]. Boulders can go on to an
/// outline drawn on the map.
Future<PlaceDraft?> showNewPlaceSheet(BuildContext context, PlaceTree tree, LatLng at) {
  var kind = PlaceKind.boulder;
  final name = TextEditingController();
  String? parentId;
  var parentTouched = false;
  String? error;
  return showModalBottomSheet<PlaceDraft>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        final candidates = parentCandidates(tree, at, kind == PlaceKind.gymWall ? PlaceKind.area : kind);
        if (!parentTouched || !candidates.any((c) => c.place.id == parentId)) parentId = candidates.isEmpty ? null : candidates.first.place.id;
        void done(bool outline) {
          if (name.text.trim().isEmpty) {
            set(() => error = 'Give it a name.');
            return;
          }
          Navigator.pop(context, (kind: kind, name: name.text.trim(), parentId: parentId, outline: outline));
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New place', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              // a menu, not side-by-side buttons: the names never wrap
              DropdownMenu<PlaceKind>(
                initialSelection: kind,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Kind'),
                requestFocusOnTap: false,
                leadingIcon: Icon(placeIcon(Place(id: '', kind: kind, name: ''))),
                dropdownMenuEntries: [
                  for (final k in _newKinds)
                    DropdownMenuEntry(
                      value: k,
                      label: kindLabel(k),
                      leadingIcon: Icon(placeIcon(Place(id: '', kind: k, name: ''))),
                    ),
                ],
                onSelected: (k) => set(() => kind = k ?? kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Name', border: const OutlineInputBorder(), errorText: error),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String?>(
                key: ValueKey('$kind$parentId'),
                initialSelection: parentId,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Inside'),
                requestFocusOnTap: false,
                dropdownMenuEntries: [
                  for (final c in candidates)
                    DropdownMenuEntry<String?>(
                      value: c.place.id,
                      label: '${c.place.name} · ${kindLabel(c.place.kind)}${c.metres > 0 ? ' · ${distanceLabel(c.metres)}' : ''}',
                    ),
                  const DropdownMenuEntry<String?>(value: null, label: 'Nothing (on its own)'),
                ],
                onSelected: (v) => set(() {
                  parentId = v;
                  parentTouched = true;
                }),
              ),
              const SizedBox(height: 16),
              if (kind == PlaceKind.boulder) ...[
                FilledButton.icon(onPressed: () => done(true), icon: const Icon(Icons.gesture), label: const Text('Next: draw its outline')),
                TextButton(onPressed: () => done(false), child: const Text('Save as a point, no outline')),
              ] else
                FilledButton(onPressed: () => done(false), child: const Text('Save')),
            ],
          ),
        );
      },
    ),
  );
}

/// The start as the guide writes it: '', 'SD', 'SD low', 'SD high'.
String startLabel(Place p) => p.sitStart ? ['SD', if (p.sitHeight.isNotEmpty) p.sitHeight].join(' ') : '';

enum _Start { stand, sit, sitLow, sitHigh }

/// A new problem on [boulder], or changes to [existing]: name and grade are
/// needed, the rest is optional. Returns the problem to save.
Future<Place?> showNewProblemSheet(BuildContext context, Place boulder, String id, {int? number, Place? existing, PlaceTree? tree}) {
  // names already on this boulder: two routes can't share one
  String key(String name) => name.trim().toLowerCase();
  final taken = {
    if (tree != null)
      for (final p in tree.childrenOf(boulder.id))
        if (p.kind == PlaceKind.problem && p.id != existing?.id) key(p.name),
  };
  final name = TextEditingController(text: existing?.name ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  final num = TextEditingController(text: existing?.number ?? (number == null ? '' : '$number'));
  var scale = existing?.gradeSystem.isUiaa == true ? GradeSystem.uiaa : GradeSystem.font;
  String? grade = (existing == null || existing.grade.isEmpty) ? null : existing.grade;
  var start = switch (existing) {
    final p? when p.sitStart && p.sitHeight == 'low' => _Start.sitLow,
    final p? when p.sitStart && p.sitHeight == 'high' => _Start.sitHigh,
    final p? when p.sitStart => _Start.sit,
    _ => _Start.stand,
  };
  var uncertain = existing?.gradeUncertain ?? false;
  var private = existing?.draft ?? true; // #462: new routes start private
  String? nameError, gradeError;
  return showModalBottomSheet<Place>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        final choices = gradeChoices(scale);
        if (grade != null && !choices.contains(grade)) choices.insert(0, grade!);
        void save() {
          set(() {
            nameError = name.text.trim().isEmpty
                ? 'Give it a name.'
                : taken.contains(key(name.text))
                ? 'There is already a route called ${name.text.trim()} here.'
                : null;
            gradeError = grade == null ? 'Pick a grade.' : null;
          });
          if (nameError != null || gradeError != null) return;
          final details = <String, Object?>{
            ...?existing?.details,
            'number': num.text.trim(),
            'sit': start != _Start.stand,
            'sitHeight': switch (start) {
              _Start.sitLow => 'low',
              _Start.sitHigh => 'high',
              _ => '',
            },
            'uncertain': uncertain,
            'note': note.text.trim(),
          }..removeWhere((k, v) => v == false || v == '' || v == null);
          Navigator.pop(
            context,
            Place(
              id: existing?.id ?? id,
              parentId: existing?.parentId ?? boulder.id,
              kind: PlaceKind.problem,
              name: name.text.trim(),
              gradeSystem: scale,
              grade: grade!,
              source: existing?.source ?? 'manual',
              licence: existing?.licence ?? 'ODbL',
              details: details,
              draft: existing?.draft ?? private,
              verified: existing?.verified ?? true,
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'New problem on ${boulder.name}' : 'Edit ${existing.name}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: num,
                        decoration: const InputDecoration(labelText: 'No.', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: name,
                        autofocus: existing == null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(labelText: 'Name', border: const OutlineInputBorder(), isDense: true, errorText: nameError),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<GradeSystem>(
                  segments: const [
                    ButtonSegment(value: GradeSystem.font, label: Text('Boulder', maxLines: 1, softWrap: false)),
                    ButtonSegment(value: GradeSystem.uiaa, label: Text('Rope', maxLines: 1, softWrap: false)),
                  ],
                  selected: {scale},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => set(() {
                    scale = s.first;
                    grade = null;
                  }),
                ),
                const SizedBox(height: 10),
                DropdownMenu<String>(
                  key: ValueKey(scale.id),
                  initialSelection: grade,
                  expandedInsets: EdgeInsets.zero,
                  menuHeight: 320,
                  label: const Text('Proposed grade'),
                  errorText: gradeError,
                  requestFocusOnTap: false,
                  dropdownMenuEntries: [for (final g in choices) DropdownMenuEntry(value: g, label: g)],
                  onSelected: (g) => set(() => grade = g),
                ),
                const SizedBox(height: 10),
                DropdownMenu<_Start>(
                  initialSelection: start,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Start'),
                  requestFocusOnTap: false,
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: _Start.stand, label: 'Stand'),
                    DropdownMenuEntry(value: _Start.sit, label: 'Sit (SD)'),
                    DropdownMenuEntry(value: _Start.sitLow, label: 'Sit, low (SD low)'),
                    DropdownMenuEntry(value: _Start.sitHigh, label: 'Sit, high (SD high)'),
                  ],
                  onSelected: (v) => set(() => start = v ?? start),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: uncertain,
                  onChanged: (v) => set(() => uncertain = v!),
                  title: const Text('Not sure of the grade (?)'),
                ),
                TextField(
                  controller: note,
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'How it goes (optional)',
                    hintText: 'Start at B, up the arete to Y',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (existing == null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: private,
                    onChanged: (v) => set(() => private = v!),
                    title: const Text('Private until I publish it'),
                    subtitle: const Text('Only you see it; publish it from its page when it is ready.'),
                  ),
                const SizedBox(height: 12),
                FilledButton(onPressed: save, child: Text(existing == null ? 'Save problem' : 'Save changes')),
              ],
            ),
          ),
        );
      },
    ),
  );
}
