// The map's style and downloaded areas (#461): files on phones and PCs;
// nothing on the web yet (#464), where the map layer's own browser cache
// keeps the tiles you looked at.
export 'map_store_io.dart' if (dart.library.js_interop) 'map_store_web.dart';
