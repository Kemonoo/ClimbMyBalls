part of '../climbing_cloud.dart';

/// Signed out: sign in or make an account. Signed in: who you are, and
/// signing out. [cloud] is null when the build has no keys.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.cloud, this.places});
  final CloudAccount? cloud;

  /// The places an edit right can cover (areas, sectors, boulders, walls),
  /// read when needed; null shows no edit rights to give.
  final List<ScopePlace> Function()? places;

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
    if (c.email != null) return _SignedIn(cloud: c, places: widget.places);
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

