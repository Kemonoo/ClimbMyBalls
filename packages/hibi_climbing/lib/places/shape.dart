// Boulder outlines (docs/climb/plan.md step 6): a preset shape dropped on the
// map, then moved, resized, rotated or reshaped corner by corner. Works in
// metres around the shape's centre, which is exact enough at boulder size.
import 'dart:math' as math;

import 'place.dart';

const _mPerDegLat = 110540.0;
double _mPerDegLng(double lat) => 111320.0 * math.cos(lat * math.pi / 180);

/// The vertex average of [ring].
LatLng ringCentre(List<LatLng> ring) {
  var lat = 0.0, lng = 0.0;
  for (final p in ring) {
    lat += p.lat;
    lng += p.lng;
  }
  return LatLng(lat / ring.length, lng / ring.length);
}

/// A boulder-sized shape around [centre]: a rectangle, or an oval with
/// [sides] corners. [width] and [depth] in metres.
List<LatLng> presetShape(LatLng centre, {bool oval = true, double width = 6, double depth = 4, int sides = 10}) {
  final pts = oval
      ? [for (var i = 0; i < sides; i++) (math.cos(2 * math.pi * i / sides) * width / 2, math.sin(2 * math.pi * i / sides) * depth / 2)]
      : [(-width / 2, -depth / 2), (width / 2, -depth / 2), (width / 2, depth / 2), (-width / 2, depth / 2)];
  return [for (final (x, y) in pts) LatLng(centre.lat + y / _mPerDegLat, centre.lng + x / _mPerDegLng(centre.lat))];
}

List<LatLng> _transform(List<LatLng> ring, (double, double) Function(double x, double y) f) {
  final c = ringCentre(ring), k = _mPerDegLng(c.lat);
  return [
    for (final p in ring)
      () {
        final (x, y) = f((p.lng - c.lng) * k, (p.lat - c.lat) * _mPerDegLat);
        return LatLng(c.lat + y / _mPerDegLat, c.lng + x / k);
      }(),
  ];
}

/// [ring] grown or shrunk by [factor] around its centre.
List<LatLng> scaleRing(List<LatLng> ring, double factor) => _transform(ring, (x, y) => (x * factor, y * factor));

/// [ring] turned by [degrees] clockwise (as seen on a north-up map).
List<LatLng> rotateRing(List<LatLng> ring, double degrees) {
  final a = -degrees * math.pi / 180, c = math.cos(a), s = math.sin(a);
  return _transform(ring, (x, y) => (x * c - y * s, x * s + y * c));
}

/// [ring] moved so its centre is at [to].
List<LatLng> moveRing(List<LatLng> ring, LatLng to) {
  final c = ringCentre(ring);
  return [for (final p in ring) LatLng(p.lat + to.lat - c.lat, p.lng + to.lng - c.lng)];
}

/// The width of [ring] across, east to west, in metres.
double ringWidthMetres(List<LatLng> ring) {
  final c = ringCentre(ring), k = _mPerDegLng(c.lat);
  final xs = [for (final p in ring) (p.lng - c.lng) * k];
  return xs.reduce(math.max) - xs.reduce(math.min);
}
