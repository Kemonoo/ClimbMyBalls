import 'package:hibi_climbing/places/near.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:hibi_climbing/places/shape.dart';
import 'package:test/test.dart';

void main() {
  const c = LatLng(48.1745, 16.9790);

  test('presets are boulder-sized and centred', () {
    final rect = presetShape(c, oval: false);
    expect(rect, hasLength(4));
    expect(ringWidthMetres(rect), closeTo(6, 0.01));
    expect(distanceMetres(rect[0], rect[1]), closeTo(6, 0.05));
    expect(distanceMetres(rect[1], rect[2]), closeTo(4, 0.05));
    final oval = presetShape(c);
    expect(oval, hasLength(10));
    expect(distanceMetres(ringCentre(oval), c), lessThan(0.01));
  });

  test('scale, rotate and move keep the shape', () {
    final rect = presetShape(c, oval: false);
    expect(ringWidthMetres(scaleRing(rect, 2)), closeTo(12, 0.02));
    final turned = rotateRing(rect, 90);
    expect(ringWidthMetres(turned), closeTo(4, 0.02));
    expect(distanceMetres(ringCentre(turned), c), lessThan(0.01));
    final moved = moveRing(rect, const LatLng(48.2, 17.0));
    expect(distanceMetres(ringCentre(moved), const LatLng(48.2, 17.0)), lessThan(0.01));
    expect(ringWidthMetres(moved), closeTo(6, 0.05));
  });
}
