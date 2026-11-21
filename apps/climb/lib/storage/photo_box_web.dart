import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// No kept photos on the web yet (#464).
Future<PhotoBox?> openPhotoBox() async => null;

class PhotoBox {
  bool has(String path) => false;
  ImageProvider image(String path) => throw UnsupportedError('No kept photos on the web.');
  Future<void> write(String path, Uint8List bytes) async {}
  Future<Uint8List?> read(String path) async => null;
  Future<void> delete(String path) async {}
}
