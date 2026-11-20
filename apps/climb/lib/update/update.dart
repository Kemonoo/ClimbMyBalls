// Updates: on start, Climb asks the public ClimbMyBalls repository for its
// newest release and offers to install it (Android). No token: the repository
// and its releases are public. tool/release.sh publishes them.
import 'package:flutter/material.dart';

export 'update_io.dart' if (dart.library.js_interop) 'update_web.dart';

/// This build's version. tool/release.sh checks it matches pubspec.yaml.
const kClimbVersion = '0.2.0';

const kReleasesRepo = 'Kemonoo/ClimbMyBalls';

class Release {
  const Release(this.version, this.notes, this.apkUrl);
  final String version, notes, apkUrl;
}

/// True when [a] is a later version than [b] ('0.10.0' > '0.9.1').
bool isNewer(String a, String b) {
  List<int> p(String v) => [for (final x in v.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.')) int.tryParse(x) ?? 0];
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// GitHub's "latest release" answer, when it's newer than [current] and has an APK.
Release? releaseFrom(Map<String, dynamic> j, {String current = kClimbVersion}) {
  final v = '${j['tag_name'] ?? ''}'.replaceFirst(RegExp(r'^v'), '');
  if (v.isEmpty || !isNewer(v, current)) return null;
  for (final a in (j['assets'] as List? ?? const [])) {
    if ('${a['name']}'.endsWith('.apk')) return Release(v, '${j['body'] ?? ''}'.trim(), '${a['browser_download_url']}');
  }
  return null;
}

/// "Climb X is out": the notes, then Update (downloads with a progress bar
/// and opens Android's installer) or Later.
Future<void> offerUpdate(BuildContext context, Release r, Future<String?> Function(Release, void Function(double)) install) =>
    showDialog<void>(context: context, builder: (_) => _UpdateDialog(r, install));

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(this.r, this.install);
  final Release r;
  final Future<String?> Function(Release, void Function(double)) install;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _problem;

  Future<void> _go() async {
    setState(() {
      _progress = 0;
      _problem = null;
    });
    final err = await widget.install(widget.r, (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _progress = null;
        _problem = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Climb ${widget.r.version} is out'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You have $kClimbVersion.'),
          if (widget.r.notes.isNotEmpty) ...[const SizedBox(height: 8), Text(widget.r.notes)],
          if (_progress != null) ...[const SizedBox(height: 16), LinearProgressIndicator(value: _progress == 0 ? null : _progress)],
          if (_problem != null) ...[const SizedBox(height: 12), Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _progress != null ? null : () => Navigator.pop(context), child: const Text('Later')),
      FilledButton(onPressed: _progress != null ? null : _go, child: const Text('Update')),
    ],
  );
}
