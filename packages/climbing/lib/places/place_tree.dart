import 'place.dart';

/// The hierarchy of places: search by name, the path to a place, and children.
///
/// Built once from a flat list. A place whose parent is missing, or whose
/// parent chain loops back on itself, is treated as a root so it still shows.
class PlaceTree {
  final Map<String, Place> _byId;
  final Map<String?, List<Place>> _children;

  PlaceTree._(this._byId, this._children);

  factory PlaceTree(Iterable<Place> places) {
    final byId = <String, Place>{};
    for (final p in places) {
      byId[p.id] = p; // a later duplicate id wins
    }
    final children = <String?, List<Place>>{};
    for (final p in byId.values) {
      final parent = _hasValidParent(p, byId) ? p.parentId : null;
      (children[parent] ??= []).add(p);
    }
    for (final list in children.values) {
      list.sort(_byName);
    }
    return PlaceTree._(byId, children);
  }

  static int _byName(Place a, Place b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  static bool _hasValidParent(Place p, Map<String, Place> byId) {
    final seen = <String>{p.id};
    var parentId = p.parentId;
    while (parentId != null) {
      final parent = byId[parentId];
      if (parent == null || !seen.add(parentId)) return false;
      parentId = parent.parentId;
    }
    return p.parentId != null;
  }

  int get length => _byId.length;
  Iterable<Place> get all => _byId.values;

  Place? operator [](String id) => _byId[id];

  /// Top-level places (countries, plus any orphans), sorted by name.
  List<Place> get roots => List.unmodifiable(_children[null] ?? const []);

  /// The places directly under [id], sorted by name.
  List<Place> childrenOf(String id) => List.unmodifiable(_children[id] ?? const []);

  /// Every place under [id], depth first.
  Iterable<Place> descendantsOf(String id) sync* {
    for (final c in childrenOf(id)) {
      yield c;
      yield* descendantsOf(c.id);
    }
  }

  /// From the top down to [id] itself; empty for an unknown id.
  List<Place> pathTo(String id) {
    final path = <Place>[];
    Place? p = _byId[id];
    while (p != null) {
      path.add(p);
      if (!(_children[p.parentId]?.contains(p) ?? false)) break; // orphan: stop here
      p = p.parentId == null ? null : _byId[p.parentId!];
    }
    return path.reversed.toList();
  }

  /// "Slovakia › Bratislava › Hrad Devín".
  String pathLabel(String id, {String separator = ' › '}) => pathTo(id).map((p) => p.name).join(separator);

  /// Places whose name contains every word of [query], ignoring case and
  /// accents ("devin" finds "Devín"). Prefix matches come first, then higher
  /// places in the hierarchy, then by name. [kinds] narrows the result.
  List<Place> search(String query, {Set<PlaceKind>? kinds, bool? indoor, int limit = 50}) {
    final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final hits = <(int, Place)>[];
    for (final p in _byId.values) {
      if (kinds != null && !kinds.contains(p.kind)) continue;
      if (indoor != null && p.indoor != indoor) continue;
      final name = foldForSearch(p.name);
      if (!words.every(name.contains)) continue;
      final prefix = name.startsWith(words.first) || name.contains(' ${words.first}');
      hits.add((prefix ? 0 : 1, p));
    }
    hits.sort((a, b) {
      if (a.$1 != b.$1) return a.$1 - b.$1;
      if (a.$2.kind != b.$2.kind) return a.$2.kind.index - b.$2.kind.index;
      return _byName(a.$2, b.$2);
    });
    return [for (final h in hits.take(limit)) h.$2];
  }
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ą': 'a',
  'č': 'c', 'ć': 'c', 'ç': 'c', 'ď': 'd', 'đ': 'd',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ě': 'e', 'ę': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ĺ': 'l', 'ľ': 'l', 'ł': 'l', 'ň': 'n', 'ń': 'n', 'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ő': 'o', 'ø': 'o',
  'ŕ': 'r', 'ř': 'r', 'š': 's', 'ś': 's', 'ß': 'ss', 'ť': 't',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y', 'ž': 'z', 'ź': 'z', 'ż': 'z',
};

/// Lower case without accents, for matching typed searches against names.
String foldForSearch(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_accents[ch] ?? ch);
  }
  return out.toString();
}
