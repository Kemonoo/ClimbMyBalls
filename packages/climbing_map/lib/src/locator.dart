part of '../climbing_map.dart';

/// Where the phone is, or why we can't tell.
typedef Located = ({LatLng? at, String? problem});

/// Your position. Tests pass a fixed one.
abstract class Locator {
  const Locator();
  Future<Located> current();
}

/// A fixed position (tests, and the "move me" pin later).
class FixedLocator extends Locator {
  const FixedLocator(this.at);
  final LatLng? at;
  @override
  Future<Located> current() async => (at: at, problem: null);
}

/// The phone's GPS. Asks for permission the first time; a refusal is shown,
/// never hidden, and the map keeps working around its centre.
class DeviceLocator extends Locator {
  const DeviceLocator();

  @override
  Future<Located> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (at: null, problem: 'Location is off. Turn it on to see what is near you.');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return (at: null, problem: 'No location permission, so the list is sorted from the map centre.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return (at: LatLng(p.latitude, p.longitude), problem: null);
    } catch (e) {
      return (at: null, problem: 'Could not get your position ($e).');
    }
  }
}
