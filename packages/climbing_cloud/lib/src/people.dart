part of '../climbing_cloud.dart';

/// A place an edit right can cover: its id, how it reads in a menu
/// ('Lúčka · Boulder'), and its parent.
typedef ScopePlace = ({String id, String label, String? parentId});

/// Signed in: who you are, whether you're approved, your rights, and for
/// anyone who can pass rights on, everyone else with a menu on their row.
class _SignedIn extends StatefulWidget {
  const _SignedIn({required this.cloud, this.places});
  final CloudAccount cloud;
  final List<ScopePlace> Function()? places;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  CloudProfile? _me;
  List<CloudProfile> _all = const [];
  Rights _rights = Rights.none;
  Map<String, ScopePlace> _places = const {};
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await widget.cloud.myProfile();
      final ok = me?.approved == true;
      final all = ok ? await widget.cloud.allProfiles() : const <CloudProfile>[];
      final grants = ok ? await widget.cloud.allGrants() : const <Grant>[];
      final places = {for (final p in widget.places?.call() ?? const <ScopePlace>[]) p.id: p};
      if (!mounted) return;
      setState(() {
        _me = me;
        _all = all;
        _places = places;
        _rights = Rights(
          owners: {
            for (final p in all)
              if (p.isOwner) p.id,
            if (me != null && me.isOwner) me.id,
          },
          approved: {
            for (final p in all)
              if (p.approved) p.id,
            if (ok) me!.id,
          },
          grants: grants,
          parentOf: (id) => places[id]?.parentId,
        );
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. ($e)';
        _loading = false;
      });
    }
  }

  String _label(Grant g) => switch (g.kind) {
    RightKind.admin => 'Admin',
    RightKind.approve => 'Lets people in',
    RightKind.edit => 'Edits ${_places[g.placeId]?.label ?? 'a place'}',
  };

  Future<void> _report(Future<String?> f) async {
    final err = await f;
    if (!mounted) return;
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    await _load();
  }

  Future<void> _give(CloudProfile p) async {
    final me = _me!.id;
    final r = _rights;
    final scopes = [
      for (final s in _places.values)
        if (r.canGrant(me, p.id, RightKind.edit, s.id)) s,
    ]..sort((a, b) => a.label.compareTo(b.label));
    final kinds = [
      if (r.canGrant(me, p.id, RightKind.admin)) RightKind.admin,
      if (r.canGrant(me, p.id, RightKind.approve)) RightKind.approve,
      if (scopes.isNotEmpty) RightKind.edit,
    ];
    if (kinds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No places to give yet: open the Map tab first.')));
      return;
    }
    final picked = await showModalBottomSheet<(RightKind, String?)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _GiveSheet(name: p.name, kinds: kinds, scopes: scopes),
    );
    if (picked == null) return;
    await _report(widget.cloud.grant(p.id, picked.$1, placeId: picked.$2));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.cloud;
    final me = _me;
    final r = _rights;
    final waiting = [
      for (final p in _all)
        if (!p.approved) p,
    ];
    final mine = me == null ? const <Grant>[] : r.of(me.id);
    final manages = me != null && (r.canApprove(me.id) || r.canGrantAny(me.id));
    return RefreshIndicator(
      onRefresh: _load,
      child: _Padded(
        children: [
          Text('Signed in as ${me?.name ?? c.name}', style: text.titleLarge),
          Text(c.email ?? '', style: text.bodyMedium),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (me == null || !me.approved)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Waiting to be let in', style: text.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Climb is for a small group of friends. Ask the owner to approve your account, then pull down here to check.'),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _load, child: const Text('Check again')),
                  ],
                ),
              ),
            )
          else ...[
            if (me.isOwner)
              Text('You own Climb: every right is yours.', style: text.bodyMedium)
            else if (mine.isNotEmpty)
              Text('Your rights: ${mine.map(_label).join(' · ')}', style: text.bodyMedium),
            if (manages) ...[
              const SizedBox(height: 16),
              Text(
                r.canApprove(me.id) ? (waiting.isEmpty ? 'Nobody is waiting to be let in.' : '${waiting.length} waiting to be let in') : 'People',
                style: text.titleMedium,
              ),
              for (final p in _all)
                if (p.id != me.id) _person(p, me.id),
            ],
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: () => c.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ],
      ),
    );
  }

  Widget _person(CloudProfile p, String me) {
    final r = _rights;
    final held = r.of(p.id);
    final status = p.isOwner ? 'Owner' : (p.approved ? 'Let in' : 'Waiting');
    final actions = <PopupMenuEntry<VoidCallback>>[
      if (!p.approved && r.canSetApproved(me, p.id, true))
        PopupMenuItem(value: () => _report(widget.cloud.setApproved(p.id, true)), child: const Text('Let in')),
      if (p.approved && r.canSetApproved(me, p.id, false))
        PopupMenuItem(value: () => _report(widget.cloud.setApproved(p.id, false)), child: const Text('Block')),
      if (p.approved && !p.isOwner && r.canGrantAny(me)) PopupMenuItem(value: () => _give(p), child: const Text('Give a right…')),
      for (final g in held)
        if (r.canRevoke(me, g)) PopupMenuItem(value: () => _report(widget.cloud.revoke(g.id)), child: Text('Take away: ${_label(g)}')),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(p.name.isEmpty ? 'No name' : p.name),
      subtitle: Text([status, ...held.map(_label)].join(' · ')),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<VoidCallback>(
              tooltip: 'Rights for ${p.name}',
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => actions,
              onSelected: (f) => f(),
            ),
    );
  }
}

/// Which right to give, and for an edit right, where.
class _GiveSheet extends StatefulWidget {
  const _GiveSheet({required this.name, required this.kinds, required this.scopes});
  final String name;
  final List<RightKind> kinds;
  final List<ScopePlace> scopes;

  @override
  State<_GiveSheet> createState() => _GiveSheetState();
}

class _GiveSheetState extends State<_GiveSheet> {
  late var _kind = widget.kinds.contains(RightKind.edit) ? RightKind.edit : widget.kinds.first;
  String? _place;

  static String _kindLabel(RightKind k) => switch (k) {
    RightKind.edit => 'Edit one place and what is in it',
    RightKind.approve => 'Let new accounts in',
    RightKind.admin => 'Admin: everything but the owner',
  };

  @override
  Widget build(BuildContext context) {
    final needsPlace = _kind == RightKind.edit;
    final ready = !needsPlace || _place != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Give ${widget.name.isEmpty ? 'them' : widget.name} a right', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          // menus, not side-by-side buttons: the names never wrap
          DropdownMenu<RightKind>(
            initialSelection: _kind,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Right'),
            requestFocusOnTap: false,
            dropdownMenuEntries: [for (final k in widget.kinds) DropdownMenuEntry(value: k, label: _kindLabel(k))],
            onSelected: (k) => setState(() => _kind = k ?? _kind),
          ),
          if (needsPlace) ...[
            const SizedBox(height: 12),
            DropdownMenu<String>(
              initialSelection: _place,
              expandedInsets: EdgeInsets.zero,
              menuHeight: 320,
              label: const Text('Where'),
              helperText: 'An area or gym, a sector or wall, or one boulder',
              enableFilter: true,
              dropdownMenuEntries: [for (final s in widget.scopes) DropdownMenuEntry(value: s.id, label: s.label)],
              onSelected: (v) => setState(() => _place = v),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: ready ? () => Navigator.pop(context, (_kind, needsPlace ? _place : null)) : null, child: const Text('Give')),
          if (!ready) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Pick where first.', textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
