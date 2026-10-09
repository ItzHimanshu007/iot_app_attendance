import 'package:geolocator/geolocator.dart';

/// One GPS fix for the campus geofence check.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.isMocked,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final bool isMocked;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracy,
    'is_mocked': isMocked,
  };

  static LocationFix fromPosition(Position p) => LocationFix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    isMocked: p.isMocked,
  );
}

class LocationService {
  LocationService._();

  /// Best-effort current position. Returns null when location is off or denied
  /// (the server decides whether that is acceptable — see geofence_mode).
  static Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 12)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return LocationFix.fromPosition(position);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : LocationFix.fromPosition(last);
    }
  }
}
