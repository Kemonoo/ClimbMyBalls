// Section photos kept on the device, so a guide opens without signal (#459):
// files in the app's documents folder on phones and PCs, IndexedDB in the
// browser (#464).
export 'photo_box_io.dart' if (dart.library.js_interop) 'photo_box_web.dart';
