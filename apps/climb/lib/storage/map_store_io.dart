import 'dart:io';
import 'dart:typed_data';

import 'package:climbing_map/climbing_map.dart';
import 'package:path_provider/path_provider.dart';

Future<MapStore?> openMapStore() async => FileMapStore(Directory('${(await getApplicationDocumentsDirectory()).path}/map'));

class FileMapStore implements MapStore {
  FileMapStore(this.dir);
  final Directory dir;

  File _file(String key) => File('${dir.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '_')}');

  @override
  Future<Uint8List?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final f = _file(key);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }
}
