// One named piece of text the app keeps between runs (its sessions, its copy
// of the shared places): a file on phones and PCs, the browser's storage on
// the web.
export 'text_box_io.dart' if (dart.library.js_interop) 'text_box_web.dart';

/// Reads and writes one piece of text; null when there's none yet.
abstract interface class TextBox {
  String? read();
  void write(String text);
}
