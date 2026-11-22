import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'idb_web.dart';

/// Kept photos in the browser's IndexedDB (#464); null where the browser
/// has none (private windows in some browsers).
Future<PhotoBox?> openPhotoBox() async {
  try {
    final db = await IdbStore.open('climb-photos');
    return PhotoBox._(db, await db.keys());
  } catch (_) {
    return null;
  }
}

/// Photos by their storage path ('topo-id/photo.jpg').
class PhotoBox {
  PhotoBox._(this._db, this._kept);
  final IdbStore _db;
  final Set<String> _kept;

  bool has(String path) => path.isNotEmpty && _kept.contains(path);

  ImageProvider image(String path) => _IdbImage(this, path);

  Future<void> write(String path, Uint8List bytes) async {
    await _db.put(path, bytes);
    _kept.add(path);
  }

  Future<Uint8List?> read(String path) => _db.get(path);

  Future<void> delete(String path) async {
    await _db.delete(path);
    _kept.remove(path);
  }
}

/// A kept photo, read from IndexedDB when it is drawn.
@immutable
class _IdbImage extends ImageProvider<_IdbImage> {
  const _IdbImage(this.box, this.path);
  final PhotoBox box;
  final String path;

  @override
  Future<_IdbImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_IdbImage key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await box.read(path);
    if (bytes == null) throw StateError('$path is no longer kept');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _IdbImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
