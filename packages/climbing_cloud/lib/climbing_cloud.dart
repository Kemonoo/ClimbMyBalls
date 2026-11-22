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
import 'package:climbing/places/place.dart';
import 'package:climbing/places/topo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient, User;

part 'src/rows.dart';
part 'src/account.dart';
part 'src/rights.dart';
part 'src/people.dart';

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

  /// Approvers only. Null when it worked, else a message.
  Future<String?> setApproved(String id, bool yes);

  /// Everyone's rights (empty before 006_roles.sql has run).
  Future<List<Grant>> allGrants();

  /// Gives [userId] a right; [placeId] only for [RightKind.edit]. Null when
  /// it worked, else a message.
  Future<String?> grant(String userId, RightKind kind, {String? placeId});

  /// Takes a right away. Null when it worked, else a message.
  Future<String?> revoke(String grantId);
}

/// An account as friends see it, and whether it may use the shared data.
class CloudProfile {
  const CloudProfile({required this.id, required this.name, this.approved = false, this.isOwner = false});
  final String id, name;

  /// [isOwner]: the account that made Climb; it holds every right.
  final bool approved, isOwner;

  factory CloudProfile.fromRow(Map<String, dynamic> r) => CloudProfile(
    id: r['id'] as String,
    name: r['name'] as String? ?? '',
    approved: r['approved'] as bool? ?? false,
    // before 006_roles.sql the owner was the one admin
    isOwner: r['is_owner'] as bool? ?? r['is_admin'] as bool? ?? false,
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

  /// Everyone's rights from the last [allGrants].
  List<Grant> grants = const [];

  @override
  Future<List<Grant>> allGrants() async {
    try {
      return grants = [for (final r in await db.from('grants').select().order('created_at')) ?Grant.fromRow(r)];
    } on PostgrestException {
      return grants = const []; // 006_roles.sql not run yet
    }
  }

  @override
  Future<String?> grant(String userId, RightKind kind, {String? placeId}) =>
      _call('grant_right', {'uid': userId, 'k': kind.name, 'pid': placeId});

  @override
  Future<String?> revoke(String grantId) => _call('revoke_right', {'grant_id': grantId});

  Future<String?> _call(String fn, Map<String, Object?> params) async {
    try {
      await db.rpc(fn, params: params);
      await allGrants();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
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

  /// Makes your private route visible to everyone; [verify] also checks it
  /// (place editors only).
  Future<void> publishPlace(String id, {bool verify = false}) => db.from('places').update({'draft': false, if (verify) 'verified': true}).eq('id', id);

  /// Sets or clears a route's check mark (place editors only).
  Future<void> verifyPlace(String id, bool verified) => db.from('places').update({'verified': verified}).eq('id', id);

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
    await db.storage.from('topos').uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true)); // a resend after a lost answer overwrites
    return path;
  }

  /// The photo's public address (the bucket is public; rock photos aren't private).
  String photoUrl(String path) => db.storage.from('topos').getPublicUrl(path);

  /// Adds [t], or saves changes to a topo you created (admins: any).
  Future<void> saveTopo(Topo t) => db.from('topos').upsert(t.toRow());

  /// Adds letters to someone else's photo (011_shared_letters.sql lets
  /// anyone add, not change).
  Future<void> saveTopoMarks(String id, List<Object?> marks) => db.from('topos').update({'marks': marks}).eq('id', id);

  /// Marks a topo as deleted.
  Future<void> deleteTopo(String id) => db.from('topos').update({'deleted': true}).eq('id', id);

  /// Route lines added, changed or deleted after [since] (010_guides.sql).
  Future<List<CloudLine>> linesSince(DateTime? since) async {
    final q = db.from('route_lines').select();
    final rows = since == null ? await q.order('updated_at') : await q.gt('updated_at', since.toUtc().toIso8601String()).order('updated_at');
    return [for (final r in rows) CloudLine.fromRow(r)];
  }

  /// Adds or changes a line (yours, or any as a place editor).
  Future<void> saveLine(CloudLine l) => db.from('route_lines').upsert(l.toRow());

  Future<void> deleteLine(String id) => db.from('route_lines').update({'deleted': true}).eq('id', id);

  /// Every guide's name and credit.
  Future<List<CloudGuide>> guides() async => [
    for (final r in await db.from('guides').select().eq('deleted', false)) CloudGuide.fromRow(r),
  ];

  Future<void> saveGuide(CloudGuide g) => db.from('guides').upsert(g.toRow());

  /// Puts a route, photo or line into the main guide or takes it out
  /// (place editors; the database checks).
  Future<void> setInGuide(String table, String id, bool inGuide) => db.from(table).update({'in_guide': inGuide}).eq('id', id);

  /// Puts a route into the main guide with its lines on the guide's photos
  /// (place editors).
  Future<void> addRouteToGuide(String id, List<String> guidePhotos) async {
    await db.from('places').update({'in_guide': true}).eq('id', id);
    if (guidePhotos.isNotEmpty) await db.from('route_lines').update({'in_guide': true}).eq('problem_id', id).inFilter('topo_id', guidePhotos);
  }

  /// Your stars, as kind:id.
  Future<Set<String>> myStars() async => {
    for (final r in await db.from('stars').select('kind,item_id').eq('user_id', user!.id)) '${r['kind']}:${r['item_id']}',
  };

  /// How many stars each of [ids] has.
  Future<Map<String, int>> starCounts(StarKind kind, List<String> ids) async {
    if (ids.isEmpty) return const {};
    final out = <String, int>{};
    for (final r in await db.from('stars').select('item_id').eq('kind', kind.name).inFilter('item_id', ids)) {
      final id = r['item_id'] as String;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  /// Stars or unstars something. A route needs your top first.
  Future<void> setStar(StarKind kind, String id, bool on) => on
      ? db.from('stars').upsert({'user_id': user!.id, 'kind': kind.name, 'item_id': id})
      : db.from('stars').delete().eq('user_id', user!.id).eq('kind', kind.name).eq('item_id', id);

  /// How many different people topped and flashed each route.
  Future<Map<String, ({int tops, int flashes})>> ascentCounts(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final tops = <String, Set<String>>{}, flashes = <String, Set<String>>{};
    for (final r in await db.from('ticks').select('problem_id,user_id,outcome').inFilter('problem_id', ids).eq('deleted', false)) {
      final p = r['problem_id'] as String, u = r['user_id'] as String, o = r['outcome'];
      if (o == 'flash' || o == 'sent') (tops[p] ??= {}).add(u);
      if (o == 'flash') (flashes[p] ??= {}).add(u);
    }
    return {for (final id in ids) id: (tops: tops[id]?.length ?? 0, flashes: flashes[id]?.length ?? 0)};
  }

  /// Your favourites, as kind:id.
  Future<Set<String>> myFavourites() async => {
    for (final r in await db.from('favourites').select('kind,item_id').eq('user_id', user!.id)) '${r['kind']}:${r['item_id']}',
  };

  Future<void> setFavourite(StarKind kind, String id, bool on) => on
      ? db.from('favourites').upsert({'user_id': user!.id, 'kind': kind.name, 'item_id': id})
      : db.from('favourites').delete().eq('user_id', user!.id).eq('kind', kind.name).eq('item_id', id);

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
  Future<void> addTick(String problemId, String outcome, DateTime day, {String? id}) => db.from('ticks').insert({
    'id': ?id,
    'problem_id': problemId,
    'outcome': outcome,
    'day': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
  });

    /// Moves one of your ascents to another day.
  Future<void> setTickDay(String id, DateTime day) => db.from('ticks').update({'day': _date(day)}).eq('id', id);

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Removes one of your ascents.
  Future<void> removeTick(String id) => db.from('ticks').update({'deleted': true}).eq('id', id);

  /// Everyone's grade votes and stars on a route (apps/climb/supabase/007).
  Future<List<CloudOpinion>> opinionsOf(String problemId) async => [
    for (final r in await db.from('opinions').select().eq('problem_id', problemId)) CloudOpinion.fromRow(r),
  ];

  /// Your grade vote ('' to take it back), stars (0 for none), tags and
  /// project bookmark on a route.
  Future<void> setOpinion(String problemId, {required String grade, required int stars, required List<String> tags, required bool project}) =>
      db.from('opinions').upsert({'problem_id': problemId, 'user_id': user!.id, 'grade': grade, 'stars': stars, 'tags': tags, 'project': project});

  /// Everyone's opinions of several routes at once.
  Future<List<CloudOpinion>> opinionsOn(List<String> problemIds) async => problemIds.isEmpty
      ? const []
      : [for (final r in await db.from('opinions').select().inFilter('problem_id', problemIds)) CloudOpinion.fromRow(r)];

  /// A route's comments, oldest first.
  Future<List<CloudComment>> commentsOf(String problemId) async => [
    for (final r in await db.from('comments').select().eq('problem_id', problemId).eq('deleted', false).order('created_at')) CloudComment.fromRow(r),
  ];

  Future<void> addComment(String problemId, String body, {String? id}) => db.from('comments').insert({'id': ?id, 'problem_id': problemId, 'body': body});

  /// Hides a comment (yours, or anyone's for an admin).
  Future<void> removeComment(String id) => db.from('comments').update({'deleted': true}).eq('id', id);

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
