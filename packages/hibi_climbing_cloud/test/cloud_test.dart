import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing_cloud/climbing_cloud.dart';

class _FakeAccount implements CloudAccount {
  final _c = StreamController<Object?>.broadcast();
  @override
  String? email;
  @override
  String name = '';
  String? lastSignUp;

  @override
  Stream<Object?> get changes => _c.stream;

  @override
  Future<String?> signIn({required String email, required String password}) async {
    if (password != 'right-pass') return 'Wrong email or password.';
    this.email = email;
    name = 'Alex';
    _c.add(null);
    return null;
  }

  @override
  Future<String?> signUp({required String email, required String password, required String name}) async {
    lastSignUp = '$name <$email>';
    this.email = email;
    this.name = name;
    _c.add(null);
    return null;
  }

  @override
  Future<void> signOut() async {
    email = null;
    _c.add(null);
  }

    var approved = true, admin = false;
  var googleSignIns = 0;
  @override
  bool canUseGoogle = false;
  @override
  Future<String?> signInWithGoogle() async {
    googleSignIns++;
    email = 'g@example.com';
    name = 'Google Friend';
    _c.add(null);
    return null;
  }
  final others = <CloudProfile>[const CloudProfile(id: 'u2', name: 'Jano')];
  @override
  Future<CloudProfile?> myProfile() async => email == null ? null : CloudProfile(id: 'u1', name: name, approved: approved, isAdmin: admin);
  @override
  Future<List<CloudProfile>> allProfiles() async => [(await myProfile())!, ...others];
  @override
  Future<String?> setApproved(String id, bool yes) async {
    final i = others.indexWhere((p) => p.id == id);
    others[i] = CloudProfile(id: id, name: others[i].name, approved: yes);
    return null;
  }
}

void main() {
  topoCacheTests();
  test('a place survives the trip through a database row', () {
    final p = Place(
      id: 'c-1',
      parentId: 'osm-way-10',
      kind: PlaceKind.boulder,
      name: 'Lúčka',
      geometry: PolygonGeometry([LatLng(48.1, 16.9), LatLng(48.1, 16.91), LatLng(48.11, 16.91)]),
    );
    final row = {...placeToRow(p), 'created_by': 'u1', 'updated_at': '2026-11-18T20:00:00Z', 'deleted': false};
    final back = CloudPlace.fromRow(row);
    expect(back.place.toJson(), p.toJson());
    expect(back.createdBy, 'u1');
    expect(placeToRow(p).containsKey('created_by'), isFalse); // the database sets it
  });

  test('the cache merges new rows, drops deleted ones, and remembers the newest change', () {
    CloudPlace row(String id, String at, {bool deleted = false}) =>
        CloudPlace.fromRow({'id': id, 'kind': 'boulder', 'name': id, 'updated_at': at, 'deleted': deleted});
    final c = PlaceCache([row('a', '2026-11-18T10:00:00Z'), row('b', '2026-11-18T11:00:00Z')]);
    c.merge([row('a', '2026-11-18T12:00:00Z', deleted: true), row('c', '2026-11-18T09:00:00Z')]);
    expect(c.places.map((p) => p.id), unorderedEquals(['b', 'c']));
    expect(c.since, DateTime.utc(2026, 11, 18, 12));
    final again = PlaceCache.fromJson(c.toJson());
    expect(again.places.map((p) => p.id), unorderedEquals(['b', 'c']));
    expect(again.since, c.since);
  });

  test('ids are random and look alike; keys are checked; errors are plain', () {
    expect(newPlaceId(Random(1)), matches(RegExp(r'^c-[0-9a-f]{24}$')));
    expect(newPlaceId(), isNot(newPlaceId()));
    expect(const CloudConfig(url: '', publishableKey: '').ok, isFalse);
    expect(const CloudConfig(url: 'https://x.supabase.co', publishableKey: 'sb_publishable_x').ok, isTrue);
    expect(friendlyAuthError('Invalid login credentials'), 'Wrong email or password.');
    expect(friendlyAuthError('User already registered'), contains('Sign in instead'));
  });

  testWidgets('sign in, a wrong password is shown, sign out, make an account', (t) async {
    final a = _FakeAccount();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AccountPanel(cloud: a))));
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'm@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await t.pump();
    expect(find.text('Wrong email or password.'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'right-pass');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await t.pump();
    await t.pump();
    expect(find.text('Signed in as Alex'), findsOneWidget);
    await t.tap(find.text('Sign out'));
    await t.pump();
    await t.pump();
    await t.tap(find.text('New here? Make an account'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Make account'));
    await t.pump();
    expect(find.text('Fill in your name, email and a password.'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Name friends see'), 'Jano');
    await t.enterText(find.widgetWithText(TextField, 'Email'), 'j@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'longenough');
    await t.tap(find.widgetWithText(FilledButton, 'Make account'));
    await t.pump();
    await t.pump();
    expect(a.lastSignUp, 'Jano <j@example.com>');
    expect(find.text('Signed in as Jano'), findsOneWidget);
  });

    testWidgets('waiting for approval; an admin lets people in', (t) async {
    final a = _FakeAccount()
      ..email = 'j@example.com'
      ..name = 'Jano'
      ..approved = false;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AccountPanel(cloud: a))));
    await t.pumpAndSettle();
    expect(find.text('Waiting to be let in'), findsOneWidget);

    final owner = _FakeAccount()
      ..email = 'm@example.com'
      ..name = 'Alex'
      ..admin = true;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AccountPanel(key: const ValueKey('owner'), cloud: owner))));
    await t.pumpAndSettle();
    expect(find.text('1 waiting to be let in'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(owner.others.single.approved, isTrue);
    expect(find.text('Nobody is waiting to be let in.'), findsOneWidget);
  });

    testWidgets('Continue with Google shows only where it works, and signs in', (t) async {
    final a = _FakeAccount();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AccountPanel(cloud: a))));
    expect(find.text('Continue with Google'), findsNothing);
    final g = _FakeAccount()..canUseGoogle = true;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AccountPanel(key: const ValueKey('g'), cloud: g))));
    await t.tap(find.text('Continue with Google'));
    await t.pumpAndSettle();
    expect(g.googleSignIns, 1);
    expect(find.text('Signed in as Google Friend'), findsOneWidget);
  });

  testWidgets('no keys: says nothing is shared', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: AccountPanel(cloud: null))));
    expect(find.textContaining('no server keys'), findsOneWidget);
  });
}

void topoCacheTests() {
  test('the topo cache keeps each place\'s topos, newest first, and drops deleted ones', () {
    CloudTopo row(String id, String place, String at, {bool deleted = false}) =>
        CloudTopo.fromRow({'id': id, 'place_id': place, 'photo_path': 'u/$id.jpg', 'updated_at': at, 'deleted': deleted, 'lines': [], 'marks': []});
    final c = TopoCache([row('t1', 'b', '2026-11-18T10:00:00Z'), row('t2', 'b', '2026-11-18T11:00:00Z'), row('t3', 'x', '2026-11-18T09:00:00Z')]);
    expect(c.of('b').map((t) => t.id), ['t2', 't1']);
    c.merge([row('t2', 'b', '2026-11-18T12:00:00Z', deleted: true)]);
    expect(c.of('b').map((t) => t.id), ['t1']);
    final again = TopoCache.fromJson(c.toJson());
    expect(again.of('x').single.photoPath, 'u/t3.jpg');
    expect(again.since, DateTime.utc(2026, 11, 18, 12));
  });
}
