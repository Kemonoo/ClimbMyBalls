import 'dart:typed_data';

import 'package:climbing_map/climbing_map.dart';

import 'idb_web.dart';

/// The map's style and downloaded areas in the browser's IndexedDB (#464).
Future<MapStore?> openMapStore() async {
  try {
    return _IdbMapStore(await IdbStore.open('climb-map'));
  } catch (_) {
    return null;
  }
}

class _IdbMapStore implements MapStore {
  _IdbMapStore(this.db);
  final IdbStore db;
  @override
  Future<Uint8List?> read(String key) => db.get(key);
  @override
  Future<void> write(String key, Uint8List bytes) => db.put(key, bytes);
  @override
  Future<void> delete(String key) => db.delete(key);
}
