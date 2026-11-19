import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'text_box.dart';

/// A file in the app's documents folder.
Future<TextBox> openTextBox(String name) async => FileBox(File('${(await getApplicationDocumentsDirectory()).path}/$name'));

class FileBox implements TextBox {
  FileBox(this.file);
  final File file;

  @override
  String? read() {
    try {
      return file.existsSync() ? file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  /// Whole or nothing: written next to it, then moved over.
  @override
  void write(String text) {
    file.parent.createSync(recursive: true);
    File('${file.path}.tmp')
      ..writeAsStringSync(text)
      ..renameSync(file.path);
  }
}
