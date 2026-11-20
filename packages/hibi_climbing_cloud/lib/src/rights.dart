part of '../climbing_cloud.dart';

/// A right someone can hold (apps/climb/supabase/006_roles.sql).
enum RightKind {
  /// Change places and topos inside one place and everything under it.
  edit,

  /// Let new accounts in.
  approve,

  /// Every right except touching the owner.
  admin;

  static RightKind? parse(String s) => values.where((k) => k.name == s).firstOrNull;
}

/// One right held by [userId]; [placeId] only for [RightKind.edit].
class Grant {
  const Grant({required this.id, required this.userId, required this.kind, this.placeId, this.grantedBy});
  final String id, userId;
  final RightKind kind;
  final String? placeId, grantedBy;

  static Grant? fromRow(Map<String, dynamic> r) {
    final k = RightKind.parse(r['kind'] as String? ?? '');
    if (k == null) return null;
    return Grant(id: r['id'] as String, userId: r['user_id'] as String, kind: k, placeId: r['place_id'] as String?, grantedBy: r['granted_by'] as String?);
  }
}

/// Who may do what: the same rules as the database's, so the app shows only
/// the choices that will work. The database still decides.
class Rights {
  Rights({this.owners = const {}, this.approved = const {}, List<Grant> grants = const [], String? Function(String placeId)? parentOf})
    : grants = List.unmodifiable(grants),
      _parentOf = parentOf ?? ((_) => null);

  /// The owner's id (a set so an unknown owner is just empty).
  final Set<String> owners;

  /// Accounts let in; a blocked account's rights sleep.
  final Set<String> approved;
  final List<Grant> grants;
  final String? Function(String) _parentOf;

  static final none = Rights();

  /// [placeId] and every place above it.
  List<String> chain(String placeId) {
    final out = <String>[placeId];
    String? p = placeId;
    while (out.length < 20 && (p = _parentOf(p!)) != null) {
      out.add(p!);
    }
    return out;
  }

  bool isOwner(String? u) => u != null && owners.contains(u);
  bool _holds(String? u, RightKind k) => u != null && approved.contains(u) && grants.any((g) => g.userId == u && g.kind == k);
  bool isAdmin(String? u) => isOwner(u) || _holds(u, RightKind.admin);
  bool canApprove(String? u) => isAdmin(u) || _holds(u, RightKind.approve);

  bool _reach(String? u, String placeId) {
    if (u == null || !approved.contains(u)) return false;
    final up = chain(placeId).toSet();
    return grants.any((g) => g.userId == u && g.kind == RightKind.edit && up.contains(g.placeId));
  }

  /// Through a right, not through having made it.
  bool canEdit(String? u, String placeId) => isAdmin(u) || _reach(u, placeId);

  /// Could [u] hand out this right at all?
  bool covers(String? u, RightKind k, [String? placeId]) =>
      isAdmin(u) || (k == RightKind.approve && _holds(u, RightKind.approve)) || (k == RightKind.edit && placeId != null && _reach(u, placeId));

  /// Anyone holding a right they could pass on.
  bool canGrantAny(String? u) => isAdmin(u) || _holds(u, RightKind.approve) || grants.any((g) => g.userId == u && g.kind == RightKind.edit && approved.contains(u));

  /// Whether [by] may give [to] this right.
  bool canGrant(String? by, String to, RightKind k, [String? placeId]) =>
      by != null && by != to && !isOwner(to) && approved.contains(to) && (k == RightKind.edit) == (placeId != null) && covers(by, k, placeId);

  /// Whether [target] sits below [by] for this right.
  bool outranks(String? by, String target, RightKind k, [String? placeId]) {
    if (by == null || isOwner(target)) return false;
    if (isOwner(by)) return true;
    if (_holds(target, RightKind.admin)) return false;
    if (_holds(by, RightKind.admin)) return true;
    if (k != RightKind.edit || placeId == null || !approved.contains(by)) return false;
    final above = chain(placeId).skip(1).toSet();
    return grants.any((g) => g.userId == by && g.kind == RightKind.edit && above.contains(g.placeId) && !_reach(target, g.placeId!));
  }

  /// Taking [g] away: your own always; others only from below you.
  bool canRevoke(String? by, Grant g) => by != null && (g.userId == by || outranks(by, g.userId, g.kind, g.placeId));

  /// Letting in or blocking [target].
  bool canSetApproved(String? by, String target, bool yes) {
    if (by == null || by == target || isOwner(target) || !canApprove(by)) return false;
    if (yes || !grants.any((g) => g.userId == target)) return true;
    return isOwner(by) || (_holds(by, RightKind.admin) && !_holds(target, RightKind.admin));
  }

  /// [u]'s rights.
  List<Grant> of(String u) => [for (final g in grants) if (g.userId == u) g];
}
