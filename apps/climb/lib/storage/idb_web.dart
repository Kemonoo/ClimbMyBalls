// A key-value store in the browser's IndexedDB (#464): photos and map tiles
// for use without signal on the web and on iPhones, where there are no files.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class IdbStore {
  IdbStore._(this._db);
  final web.IDBDatabase _db;
  static const _name = 'kv';

  /// Opens (or makes) the database [db]. Also asks the browser to keep the
  /// site's storage (Safari otherwise clears it after a week unused).
  static Future<IdbStore> open(String db) async {
    unawaited(web.window.navigator.storage.persist().toDart.then((_) {}, onError: (_) {}));
    final req = web.window.indexedDB.open(db, 1);
    req.onupgradeneeded = ((web.Event _) => (req.result as web.IDBDatabase).createObjectStore(_name)).toJS;
    return IdbStore._(await _done<web.IDBDatabase>(req));
  }

  web.IDBObjectStore _store(String mode) => _db.transaction(_name.toJS, mode).objectStore(_name);

  Future<Uint8List?> get(String key) async {
    final r = await _done<JSAny?>(_store('readonly').get(key.toJS));
    return r == null ? null : (r as JSUint8Array).toDart;
  }

  Future<void> put(String key, Uint8List bytes) => _done<JSAny?>(_store('readwrite').put(bytes.toJS, key.toJS));

  Future<void> delete(String key) => _done<JSAny?>(_store('readwrite').delete(key.toJS));

  Future<Set<String>> keys() async {
    final r = await _done<JSArray<JSAny?>>(_store('readonly').getAllKeys());
    return {for (final k in r.toDart) (k as JSString).toDart};
  }

  static Future<T> _done<T extends JSAny?>(web.IDBRequest req) {
    final c = Completer<T>();
    req.onsuccess = ((web.Event _) => c.complete(req.result as T)).toJS;
    req.onerror = ((web.Event _) => c.completeError(StateError('Browser storage: ${req.error?.message ?? 'failed'}'))).toJS;
    return c.future;
  }
}
