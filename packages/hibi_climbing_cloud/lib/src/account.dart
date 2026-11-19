part of '../climbing_cloud.dart';

/// Signed out: sign in or make an account. Signed in: who you are, and
/// signing out. [cloud] is null when the build has no keys.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.cloud});
  final CloudAccount? cloud;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  final _email = TextEditingController(), _password = TextEditingController(), _name = TextEditingController();
  var _newAccount = false, _busy = false, _hide = true;
  String? _error;
  StreamSubscription<Object?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.cloud?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final c = widget.cloud!;
    if (_email.text.trim().isEmpty || _password.text.isEmpty || (_newAccount && _name.text.trim().isEmpty)) {
      setState(() => _error = _newAccount ? 'Fill in your name, email and a password.' : 'Fill in your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = _newAccount
        ? await c.signUp(email: _email.text, password: _password.text, name: _name.text)
        : await c.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.cloud;
    if (c == null) {
      return const _Padded(children: [Text('This build has no server keys, so nothing is shared. Your climbs stay on this phone.')]);
    }
    if (c.email != null) return _SignedIn(cloud: c);
    return _Padded(children: [
      Text(_newAccount ? 'Make an account' : 'Sign in', style: text.titleLarge),
      const SizedBox(height: 4),
            const Text('To share boulders, topos and ticks with your friends.'),
      const SizedBox(height: 16),
      if (c.canUseGoogle) ...[
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  final err = await c.signInWithGoogle();
                  if (!mounted) return;
                  setState(() {
                    _busy = false;
                    _error = err;
                  });
                },
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Continue with Google'),
        ),
        const SizedBox(height: 12),
        const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or with email')), Expanded(child: Divider())]),
        const SizedBox(height: 12),
      ],
      if (_newAccount) ...[
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name friends see', border: OutlineInputBorder())),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: _hide,
        autofillHints: [_newAccount ? AutofillHints.newPassword : AutofillHints.password],
        onSubmitted: (_) => _go(),
        decoration: InputDecoration(
          labelText: 'Password',
          helperText: _newAccount ? 'At least 8 characters' : null,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(tooltip: _hide ? 'Show' : 'Hide', onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility : Icons.visibility_off)),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? 'One moment…' : (_newAccount ? 'Make account' : 'Sign in'))),
      TextButton(
        onPressed: _busy ? null : () => setState(() {
          _newAccount = !_newAccount;
          _error = null;
        }),
        child: Text(_newAccount ? 'I have an account' : 'New here? Make an account'),
      ),
    ]);
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: children);
}

/// Signed in: who you are, whether you're approved, and for admins the
/// accounts waiting to be let in.
class _SignedIn extends StatefulWidget {
  const _SignedIn({required this.cloud});
  final CloudAccount cloud;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  CloudProfile? _me;
  List<CloudProfile> _all = const [];
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
      final all = me?.isAdmin == true ? await widget.cloud.allProfiles() : const <CloudProfile>[];
      if (!mounted) return;
      setState(() {
        _me = me;
        _all = all;
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.cloud;
    final me = _me;
    final waiting = [for (final p in _all) if (!p.approved) p];
    return RefreshIndicator(
      onRefresh: _load,
      child: _Padded(children: [
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Waiting to be let in', style: text.titleMedium),
                const SizedBox(height: 4),
                const Text('Climb is for a small group of friends. Ask the owner to approve your account, then pull down here to check.'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _load, child: const Text('Check again')),
              ]),
            ),
          )
        else if (me.isAdmin) ...[
          Text(waiting.isEmpty ? 'Nobody is waiting to be let in.' : '${waiting.length} waiting to be let in', style: text.titleMedium),
          for (final p in _all)
            if (p.id != me.id)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name.isEmpty ? 'No name' : p.name),
                subtitle: Text(p.approved ? 'Let in' : 'Waiting'),
                value: p.approved,
                onChanged: (v) async {
                  final err = await c.setApproved(p.id, v);
                  if (!context.mounted) return;
                  if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  _load();
                },
              ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: () => c.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ]),
    );
  }
}
