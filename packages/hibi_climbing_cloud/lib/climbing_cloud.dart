// Climb's shared database (docs/climb/plan.md step 7, ADR 0021): accounts and
// shared places through Supabase. The schema and its rules are in
// apps/climb/supabase/schema.sql.
//
// The app holds only the project URL and the publishable key, both public by
// design; the database's row-level rules decide what each signed-in person
// may read and change. No service key ever ships.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/places/topo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:supabase_flutter/supabase_flutter.dart' show User;

part 'src/rows.dart';
part 'src/account.dart';

/// The project's public URL and key, from `--dart-define-from-file`.
class CloudConfig {
  const CloudConfig({required this.url, required this.publishableKey, this.googleWebClientId = ''});

  factory CloudConfig.fromEnvironment() => const CloudConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );

  /// The Google Cloud "Web application" client (public); Supabase checks
  /// Google's sign-in tokens against it.
  final String googleWebClientId;

  final String url, publishableKey;

  bool get ok => url.startsWith('https://') && publishableKey.isNotEmpty;
}

/// A new random id for a place made in the app ('c-' and 24 hex digits).
String newPlaceId([Random? random]) {
  final r = random ?? Random.secure();
  return 'c-${List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

/// Signing in and out (what the account screen needs; tests fake it).
abstract class CloudAccount {
  String? get email;
  String get name;
  Stream<Object?> get changes;
  Future<String?> signUp({required String email, required String password, required String name});
  Future<String?> signIn({required String email, required String password});
  Future<void> signOut();

  /// Whether "Continue with Google" works here (Android with a client id).
  bool get canUseGoogle;

  /// Signs in with the Google account on the phone. Null when it worked or
  /// was cancelled, else a message.
  Future<String?> signInWithGoogle();

  /// Your profile (approved or still waiting), fetched fresh.
  Future<CloudProfile?> myProfile();

  /// Every account, for admins approving new ones.
  Future<List<CloudProfile>> allProfiles();

  /// Admins only. Null when it worked, else a message.
  Future<String?> setApproved(String id, bool yes);
}

/// An account as friends see it, and whether it may use the shared data.
class CloudProfile {
  const CloudProfile({required this.id, required this.name, this.approved = false, this.isAdmin = false});
  final String id, name;
  final bool approved, isAdmin;

  factory CloudProfile.fromRow(Map<String, dynamic> r) => CloudProfile(
    id: r['id'] as String,
    name: r['name'] as String? ?? '',
    approved: r['approved'] as bool? ?? false,
    isAdmin: r['is_admin'] as bool? ?? false,
  );
}

/// Signing in and out, and the shared places.
class ClimbCloud implements CloudAccount {
  ClimbCloud(this.db, {this.googleWebClientId = ''});

  final SupabaseClient db;
  final String googleWebClientId;

  /// Connects, or returns null when the build has no keys (the app then
  /// works on its own, with nothing shared).
  static Future<ClimbCloud?> start(CloudConfig config) async {
    if (!config.ok) return null;
    await Supabase.initialize(url: config.url, publishableKey: config.publishableKey);
    return ClimbCloud(Supabase.instance.client, googleWebClientId: config.googleWebClientId);
  }

  User? get user => db.auth.currentUser;
  @override
  String? get email => user?.email;
  @override
  Stream<Object?> get changes => db.auth.onAuthStateChange;

  /// The name friends see.
  @override
  String get name => (user?.userMetadata?['name'] as String?) ?? user?.email?.split('@').first ?? '';

  /// Null when it worked, else a message to show.
  @override
  Future<String?> signUp({required String email, required String password, required String name}) =>
      _guard(() => db.auth.signUp(email: email.trim(), password: password, data: {'name': name.trim()}));

  @override
  Future<String?> signIn({required String email, required String password}) =>
      _guard(() => db.auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<void> signOut() async {
    me = null;
    await db.auth.signOut();
    if (canUseGoogle && !kIsWeb) await GoogleSignIn.instance.signOut().catchError((_) {});
  }

  @override
  bool get canUseGoogle => googleWebClientId.isNotEmpty && (kIsWeb || defaultTargetPlatform == TargetPlatform.android);

  var _googleReady = false;
  String _rawNonce = '';

  /// Google's account picker gives an ID token for the web client; Supabase
  /// checks it and the nonce (Google gets its SHA-256, Supabase the raw one).
  @override
  Future<String?> signInWithGoogle() async {
    if (kIsWeb) {
      // in a browser: Google's page, then back to this page signed in
      try {
        await db.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Uri.base.removeFragment().replace(query: '').toString().replaceAll('?', ''));
        return null;
      } on AuthException catch (e) {
        return friendlyAuthError(e.message);
      }
    }
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        _rawNonce = newPlaceId().substring(2) + newPlaceId().substring(2);
        await g.initialize(serverClientId: googleWebClientId, nonce: sha256.convert(utf8.encode(_rawNonce)).toString());
        _googleReady = true;
      }
      final account = await g.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'Google gave no sign-in token. Try again.';
      await db.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, nonce: _rawNonce);
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      return 'Google sign-in failed: ${e.description ?? e.code.name}';
    } on AuthException catch (e) {
      return friendlyAuthError(e.message);
    } catch (e) {
      return 'Google sign-in failed. ($e)';
    }
  }

  /// Your profile from the last [myProfile]; null until fetched or when
  /// signed out.
  CloudProfile? me;

  /// Signed in and approved: allowed to read and add shared data.
  bool get approved => user != null && (me?.approved ?? false);

  @override
  Future<CloudProfile?> myProfile() async {
    final u = user;
    if (u == null) return me = null;
    final r = await db.from('profiles').select().eq('id', u.id).maybeSingle();
    return me = r == null ? null : CloudProfile.fromRow(r);
  }

  @override
  Future<List<CloudProfile>> allProfiles() async => [for (final r in await db.from('profiles').select().order('created_at')) CloudProfile.fromRow(r)];

  @override
  Future<String?> setApproved(String id, bool yes) async {
    try {
      await db.rpc('set_approved', params: {'uid': id, 'yes': yes});
      return null;
    } catch (e) {
      return 'Could not change it. ($e)';
    }
  }

  /// Places added or changed after [since] (all of them when null),
  /// including deleted ones so the app can drop them.
  Future<List<CloudPlace>> placesSince(DateTime? since) async {
    final q = db.from('places').select();
    final rows = since == null ? await q.order('updated_at') : await q.gt('updated_at', since.toUtc().toIso8601String()).order('updated_at');
    return [for (final r in rows) CloudPlace.fromRow(r)];
  }

  /// Adds [p], or saves changes to a place you created.
  Future<void> savePlace(Place p) => db.from('places').upsert(placeToRow(p));

  /// Marks a place you created as deleted.
  Future<void> deletePlace(String id) => db.from('places').update({'deleted': true}).eq('id', id);

  /// Topos added or changed after [since], including deleted ones.
  Future<List<CloudTopo>> toposSince(DateTime? since) async {
    final q = db.from('topos').select();
    final rows = since == null ? await q.order('updated_at') : await q.gt('updated_at', since.toUtc().toIso8601String()).order('updated_at');
    return [for (final r in rows) CloudTopo.fromRow(r)];
  }

  /// Uploads a topo photo (JPEG) into your own folder and returns its path.
  /// Never replaces a file (that needs a read rule the bucket doesn't have);
  /// every topo has a new id.
  Future<String> uploadPhoto(String topoId, Uint8List jpeg) async {
    final path = '${user!.id}/$topoId.jpg';
    await db.storage.from('topos').uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return path;
  }

  /// The photo's public address (the bucket is public; rock photos aren't private).
  String photoUrl(String path) => db.storage.from('topos').getPublicUrl(path);

  /// Adds [t], or saves changes to a topo you created (admins: any).
  Future<void> saveTopo(Topo t) => db.from('topos').upsert(t.toRow());

  /// Marks a topo as deleted.
  Future<void> deleteTopo(String id) => db.from('topos').update({'deleted': true}).eq('id', id);

  /// Everyone's ascents of [problemId], newest first.
  Future<List<CloudTick>> ticksOf(String problemId) async => [
    for (final r in await db.from('ticks').select().eq('problem_id', problemId).eq('deleted', false).order('day', ascending: false)) CloudTick.fromRow(r),
  ];

    /// All your own ascents, oldest first: they become your sessions on the
  /// Climbs tab.
  Future<List<CloudTick>> myTicks() async => [
    for (final r in await db.from('ticks').select().eq('user_id', user!.id).eq('deleted', false).order('created_at')) CloudTick.fromRow(r),
  ];

  /// Logs your ascent of [problemId] on [day] ('flash', 'sent' or 'tried').
  Future<void> addTick(String problemId, String outcome, DateTime day) => db.from('ticks').insert({
    'problem_id': problemId,
    'outcome': outcome,
    'day': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
  });

    /// Moves one of your ascents to another day.
  Future<void> setTickDay(String id, DateTime day) => db.from('ticks').update({'day': _date(day)}).eq('id', id);

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Removes one of your ascents.
  Future<void> removeTick(String id) => db.from('ticks').update({'deleted': true}).eq('id', id);

  Future<String?> _guard(Future<Object?> Function() f) async {
    try {
      await f();
      return null;
    } on AuthException catch (e) {
      return friendlyAuthError(e.message);
    } catch (e) {
      return 'Could not reach the server. Check your connection. ($e)';
    }
  }
}

/// Supabase's auth messages, said plainly.
String friendlyAuthError(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login credentials')) return 'Wrong email or password.';
  if (m.contains('already registered') || m.contains('already been registered')) return 'There is already an account with this email. Sign in instead.';
  if (m.contains('password should be at least') || m.contains('weak')) return 'Pick a longer password (at least 8 characters).';
  if (m.contains('valid email') || m.contains('invalid format')) return 'That email address doesn\'t look right.';
  if (m.contains('rate limit')) return 'Too many tries. Wait a minute and try again.';
  if (m.contains('database error saving new user')) return 'Climb is full or sign-up is closed. Ask the owner.';
  return message;
}
