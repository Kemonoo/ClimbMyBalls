import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update.dart';

const _ch = MethodChannel('climb/update');

/// Only the Android app updates itself.
bool get updatesWork => Platform.isAndroid;

/// The newest release if it's later than this build, else null (also when
/// offline: the check is quiet).
Future<Release?> checkForUpdate() async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final q = await c.getUrl(Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/latest'));
    q.headers
      ..set('Accept', 'application/vnd.github+json')
      ..set('User-Agent', 'climb-app');
    final res = await q.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    return releaseFrom(jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
}

/// Downloads [r] and opens Android's installer. Null when the installer
/// took over, else what went wrong.
Future<String?> installUpdate(Release r, void Function(double) progress) async {
  if (!(await _ch.invokeMethod<bool>('canInstallApps') ?? false)) {
    await _ch.invokeMethod('openInstallAppsSettings');
    return 'Allow Climb to install apps (the switch that just opened), then tap Update again.';
  }
  final c = HttpClient();
  try {
    final res = await (await c.getUrl(Uri.parse(r.apkUrl))).close();
    if (res.statusCode != 200) return 'GitHub answered ${res.statusCode}.';
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates')..createSync(recursive: true);
    final f = File('${dir.path}/climb.apk');
    final sink = f.openWrite();
    final total = res.contentLength;
    var got = 0;
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress(got / total);
    }
    await sink.close();
    return await _ch.invokeMethod<bool>('installApk', {'path': f.path}) ?? false ? null : "Android didn't open the installer.";
  } catch (e) {
    return 'The download failed. Check the internet and try again. ($e)';
  } finally {
    c.close();
  }
}
