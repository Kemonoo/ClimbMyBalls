import 'package:web/web.dart' as web;

import 'text_box.dart';

/// The browser's local storage, under `climb.name`.
Future<TextBox> openTextBox(String name) async => _LocalBox('climb.$name');

class _LocalBox implements TextBox {
  _LocalBox(this.key);
  final String key;

  @override
  String? read() => web.window.localStorage.getItem(key);

  @override
  void write(String text) => web.window.localStorage.setItem(key, text);
}
