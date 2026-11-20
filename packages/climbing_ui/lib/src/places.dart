part of '../climbing_ui.dart';

/// The gym or crag of a session, from the saved places (indoor ones first,
/// each with its icon). New places come from the + next to it.
class _PlacePicker extends StatelessWidget {
  const _PlacePicker({required this.value, required this.onPicked});
  final String value;
  final ValueChanged<ClimbPlace> onPicked;

  @override
  Widget build(BuildContext context) {
    final look = host.theme(context);
    final places = [...host.store.places]..sort((a, b) => a.outdoor == b.outdoor ? 0 : (a.outdoor ? 1 : -1));
    final known = places.any((p) => p.name == value);
    return DropdownMenu<String>(
      key: ValueKey(value),
      initialSelection: known ? value : null,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Gym or crag'),
      hintText: places.isEmpty ? 'Add one with +' : 'Pick one',
      requestFocusOnTap: false,
      leadingIcon: known ? Icon(places.firstWhere((p) => p.name == value).outdoor ? Icons.landscape_outlined : Icons.home_work_outlined) : null,
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
      textStyle: look.text(15),
      dropdownMenuEntries: [
        for (final p in places)
          DropdownMenuEntry(
            value: p.name,
            label: p.name,
            leadingIcon: Icon(p.outdoor ? Icons.landscape_outlined : Icons.home_work_outlined),
          ),
      ],
      onSelected: (v) {
        final p = v == null ? null : climbPlaceIn(host.store, v);
        if (p != null) onPicked(p);
      },
    );
  }
}

/// Google Maps for [p]: its saved link, else a search for its name and address.
Uri placeMapsUri(ClimbPlace p) {
  final link = Uri.tryParse(p.maps.trim());
  if (link != null && link.hasScheme) return link;
  final q = [p.name, if (p.address.isNotEmpty) p.address].join(', ');
  return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q});
}

/// A gym or crag's details: name, indoor or outdoor, address, a Maps link and
/// a note. [creating] makes a new place (optionally starting from a saved one,
/// e.g. the same spot outdoors) and never touches other places or sessions.
/// Editing [name] can rename it, and its sessions move along. Returns the
/// saved place.
Future<ClimbPlace?> showPlaceSheet(BuildContext context, {String name = '', bool creating = false, bool? outdoor}) {
  final had = creating ? null : climbPlaceIn(host.store, name);
  var p = had ?? ClimbPlace(name: creating ? '' : name, outdoor: outdoor ?? false);
  final nameC = TextEditingController(text: p.name), addressC = TextEditingController(text: p.address);
  final mapsC = TextEditingController(text: p.maps), noteC = TextEditingController(text: p.note);
  final sessions = had == null ? 0 : host.store.sessions.where((s) => s.place.trim().toLowerCase() == had.name.trim().toLowerCase()).length;
  String? problem;
  return showModalBottomSheet<ClimbPlace>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
      final look = host.theme(sheet);
      InputDecoration deco(String label, [String? hint]) =>
          InputDecoration(labelText: label, hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)));
      ClimbPlace current() => p.copyWith(name: nameC.text.trim(), address: addressC.text.trim(), maps: mapsC.text.trim(), note: noteC.text.trim());
      final renaming = had != null && nameC.text.trim().isNotEmpty && nameC.text.trim() != had.name;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(had == null ? 'New gym or crag' : had.name, style: look.text(20, bold: true)),
              const SizedBox(height: 4),
              Text('Only the name is needed. Add the rest whenever you like.', style: look.text(12, color: look.muted)),
              if (had == null && host.store.places.isNotEmpty) ...[
                const SizedBox(height: 16),
                // The same place with a twist, e.g. the boulders outside the gym.
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Start from a saved place (optional)'),
                  requestFocusOnTap: false,
                  inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                  dropdownMenuEntries: [for (final x in host.store.places) DropdownMenuEntry(value: x.name, label: x.name)],
                  onSelected: (v) {
                    final x = v == null ? null : climbPlaceIn(host.store, v);
                    if (x == null) return;
                    set(() {
                      p = x.copyWith(outdoor: !x.outdoor);
                      nameC.text = '${x.name} (${x.outdoor ? 'indoor' : 'outdoor'})';
                      addressC.text = x.address;
                      mapsC.text = x.maps;
                      noteC.text = '';
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: nameC,
                autofocus: had == null,
                textCapitalization: TextCapitalization.words,
                decoration: deco('Name').copyWith(errorText: problem),
                onChanged: (_) => set(() => problem = null),
              ),
              if (renaming)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Renames it: its ${_plural(sessions, 'session')} move to the new name.', style: look.text(12, color: look.accentDeep)),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final (v, l) in const [(false, 'Indoor'), (true, 'Outdoor')])
                  ChoiceChip(label: Text(l), selected: p.outdoor == v, onSelected: (_) => set(() => p = p.copyWith(outdoor: v))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: addressC, textCapitalization: TextCapitalization.words, decoration: deco('Address or area', 'e.g. Rača, Bratislava')),
              const SizedBox(height: 12),
              TextField(
                controller: mapsC,
                keyboardType: TextInputType.url,
                decoration: deco('Google Maps link', 'Share → Copy link in Maps, then paste'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(placeMapsUri(current()), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.map_outlined),
                    label: Text(mapsC.text.trim().isEmpty ? 'Find on Maps' : 'Open in Maps'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final c = await Clipboard.getData(Clipboard.kTextPlain);
                      final t = c?.text?.trim() ?? '';
                      if (t.startsWith('http')) set(() => mapsC.text = t);
                    },
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Paste link'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: noteC, textCapitalization: TextCapitalization.sentences, maxLines: 2, decoration: deco('Note', 'Opening hours, parking, the good wall')),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    final next = current();
                    if (next.name.isEmpty) return set(() => problem = 'Give it a name');
                    final taken = climbPlaceIn(host.store, next.name);
                    if (taken != null && taken.name.toLowerCase() != had?.name.toLowerCase()) {
                      return set(() => problem = '${taken.name} already exists. Pick it from the list, or use another name.');
                    }
                    host.store.savePlace(next, was: had?.name);
                    Navigator.pop(sheet, next);
                  },
                  style: FilledButton.styleFrom(backgroundColor: look.accent, shape: const StadiumBorder()),
                  child: Text(had == null ? 'Add' : 'Save', style: look.text(15, bold: true, color: look.onAccent)),
                ),
              ),
            ]),
          ),
        ),
      );
    }),
  );
}

/// Every saved gym and crag, to open and fill in.
Future<void> showPlacesSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheet) => ListenableBuilder(
    listenable: host.listenable,
    builder: (sheet, _) {
      final look = host.theme(sheet);
      final places = host.store.places;
      int count(ClimbPlace p) => host.store.sessions.where((s) => s.place.trim().toLowerCase() == p.name.trim().toLowerCase()).length;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Gyms and crags', style: look.text(20, bold: true))),
            for (final p in places)
              ListTile(
                leading: Icon(p.outdoor ? Icons.landscape_outlined : Icons.home_work_outlined),
                title: Text(p.name, style: look.text(15, bold: true)),
                subtitle: Text(
                  [_plural(count(p), 'session'), if (p.address.isNotEmpty) p.address, if (p.maps.isNotEmpty) 'on the map'].join(' · '),
                  style: look.text(12, color: look.muted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showPlaceSheet(sheet, name: p.name),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => showPlaceSheet(sheet, creating: true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a gym or crag'),
            ),
          ],
        ),
      );
    },
  ),
);
