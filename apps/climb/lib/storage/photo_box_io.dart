import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// The folder for kept photos; null where photos can't be kept.
Future<PhotoBox?> openPhotoBox() async => PhotoBox(Directory('${(await getApplicationDocumentsDirectory()).path}/photos'));

/// Photos by their storage path ('topo-id/photo.jpg').
class PhotoBox {
  PhotoBox(this.dir);
  final Directory dir;

  File _file(String path) => File('${dir.path}/${path.replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '_')}');

  bool has(String path) => path.isNotEmpty && _file(path).existsSync();

  ImageProvider image(String path) => FileImage(_file(path));

  /// Whole or nothing: written next to it, then moved over.
  Future<void> write(String path, Uint8List bytes) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> read(String path) async {
    final f = _file(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> delete(String path) async {
    final f = _file(path);
    if (await f.exists()) await f.delete();
  }
}
