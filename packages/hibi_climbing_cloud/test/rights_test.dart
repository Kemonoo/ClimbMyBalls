// The hierarchy of rights (apps/climb/supabase/006_roles.sql). The database
// enforces the same rules; these pin the app's copy of them.
import 'package:flutter_test/flutter_test.dart';
import 'package:hibi_climbing_cloud/climbing_cloud.dart';

// area > sector > boulder > problem; another area beside it.
const _parents = {'sector': 'area', 'boulder': 'sector', 'problem': 'boulder', 'boulder2': 'sector'};

Rights _rights(List<Grant> grants, {Set<String>? approved}) => Rights(
  owners: {'owner'},
  approved: approved ?? {'owner', 'admin', 'admin2', 'appr', 'appr2', 'ed', 'ed2', 'low', 'nobody'},
  grants: grants,
  parentOf: (id) => _parents[id],
);

Grant _g(String user, RightKind k, [String? place]) => Grant(id: '$user-${k.name}-$place', userId: user, kind: k, placeId: place);

void main() {
  final grants = [
    _g('admin', RightKind.admin),
    _g('admin2', RightKind.admin),
    _g('appr', RightKind.approve),
    _g('appr2', RightKind.approve),
    _g('ed', RightKind.edit, 'area'),
    _g('ed2', RightKind.edit, 'area'),
    _g('low', RightKind.edit, 'boulder'),
  ];
  final r = _rights(grants);

  test('the owner holds everything and nobody can touch it', () {
    expect(r.isAdmin('owner'), isTrue);
    expect(r.canEdit('owner', 'problem'), isTrue);
    expect(r.canApprove('owner'), isTrue);
    for (final k in RightKind.values) {
      expect(r.canGrant('admin', 'owner', k, k == RightKind.edit ? 'area' : null), isFalse);
    }
    expect(r.canSetApproved('admin', 'owner', false), isFalse);
    expect(r.outranks('admin', 'owner', RightKind.admin), isFalse);
  });

  test('an edit right covers its place and everything under it, nothing beside or above', () {
    expect(r.canEdit('low', 'boulder'), isTrue);
    expect(r.canEdit('low', 'problem'), isTrue);
    expect(r.canEdit('low', 'boulder2'), isFalse);
    expect(r.canEdit('low', 'sector'), isFalse);
    expect(r.canEdit('ed', 'problem'), isTrue);
    expect(r.canEdit('appr', 'problem'), isFalse);
    expect(r.canEdit('nobody', 'problem'), isFalse);
  });

  test('a blocked account\'s rights sleep', () {
    final blocked = _rights(grants, approved: {'owner'});
    expect(blocked.canEdit('ed', 'problem'), isFalse);
    expect(blocked.isAdmin('admin'), isFalse);
  });

  test('you can give the same right or a lesser one, never more', () {
    expect(r.canGrant('owner', 'nobody', RightKind.admin), isTrue);
    expect(r.canGrant('admin', 'nobody', RightKind.admin), isTrue);
    expect(r.canGrant('admin', 'nobody', RightKind.edit, 'area'), isTrue);
    expect(r.canGrant('appr', 'nobody', RightKind.approve), isTrue);
    expect(r.canGrant('appr', 'nobody', RightKind.admin), isFalse);
    expect(r.canGrant('appr', 'nobody', RightKind.edit, 'boulder'), isFalse);
    expect(r.canGrant('ed', 'nobody', RightKind.edit, 'area'), isTrue);
    expect(r.canGrant('ed', 'nobody', RightKind.edit, 'boulder'), isTrue);
    expect(r.canGrant('low', 'nobody', RightKind.edit, 'boulder'), isTrue);
    expect(r.canGrant('low', 'nobody', RightKind.edit, 'sector'), isFalse);
    expect(r.canGrant('ed', 'nobody', RightKind.approve), isFalse);
    expect(r.canGrant('nobody', 'ed', RightKind.edit, 'boulder'), isFalse);
  });

  test('no rights to yourself, to someone not let in, or edit without a place', () {
    expect(r.canGrant('admin', 'admin', RightKind.approve), isFalse);
    expect(_rights(grants, approved: {'owner', 'admin'}).canGrant('admin', 'nobody', RightKind.approve), isFalse);
    expect(r.canGrant('admin', 'nobody', RightKind.edit), isFalse);
    expect(r.canGrant('admin', 'nobody', RightKind.approve, 'area'), isFalse);
  });

  Grant held(String user, RightKind k) => grants.firstWhere((g) => g.userId == user && g.kind == k);

  test('taking away: only from people below you; the owner from anyone', () {
    expect(r.canRevoke('owner', held('admin', RightKind.admin)), isTrue);
    expect(r.canRevoke('admin', held('admin2', RightKind.admin)), isFalse, reason: 'same level');
    expect(r.canRevoke('admin', held('appr', RightKind.approve)), isTrue);
    expect(r.canRevoke('admin', held('low', RightKind.edit)), isTrue);
    expect(r.canRevoke('appr', held('appr2', RightKind.approve)), isFalse, reason: 'same level');
    expect(r.canRevoke('appr', held('admin', RightKind.admin)), isFalse);
    expect(r.canRevoke('ed', held('low', RightKind.edit)), isTrue, reason: 'inside their area, lower down');
    expect(r.canRevoke('ed', held('ed2', RightKind.edit)), isFalse, reason: 'same place');
    expect(r.canRevoke('low', held('ed', RightKind.edit)), isFalse, reason: 'above them');
    expect(r.canRevoke('ed', held('appr', RightKind.approve)), isFalse);
  });

  test('an editor can\'t take edit from someone whose own edit reaches as high', () {
    final both = _rights([...grants, _g('low', RightKind.edit, 'area')]);
    expect(both.canRevoke('ed', held('low', RightKind.edit)), isFalse);
    expect(_rights([...grants, _g('low', RightKind.admin)]).canRevoke('ed', held('low', RightKind.edit)), isFalse);
  });

  test('you can always give up your own right', () {
    expect(r.canRevoke('admin', held('admin', RightKind.admin)), isTrue);
    expect(r.canRevoke('low', held('low', RightKind.edit)), isTrue);
  });

  test('approving: approvers let in anyone, but block only people with no rights', () {
    expect(r.canSetApproved('appr', 'nobody', true), isTrue);
    expect(r.canSetApproved('appr', 'nobody', false), isTrue);
    expect(r.canSetApproved('appr', 'low', false), isFalse);
    expect(r.canSetApproved('admin', 'low', false), isTrue);
    expect(r.canSetApproved('admin', 'admin2', false), isFalse);
    expect(r.canSetApproved('owner', 'admin', false), isTrue);
    expect(r.canSetApproved('ed', 'nobody', true), isFalse);
    expect(r.canSetApproved('appr', 'appr', false), isFalse);
  });

  test('a grant row from the database', () {
    final g = Grant.fromRow({'id': 'g1', 'user_id': 'u2', 'kind': 'edit', 'place_id': 'c-1', 'granted_by': 'u1'})!;
    expect((g.kind, g.placeId, g.grantedBy), (RightKind.edit, 'c-1', 'u1'));
    expect(Grant.fromRow({'id': 'g2', 'user_id': 'u2', 'kind': 'superuser'}), isNull);
  });
}
