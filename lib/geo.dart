import 'package:geolocator/geolocator.dart';

import 'store.dart';

enum GeoErr { serviceOff, denied, deniedForever, timeout }

class GeoResult {
  const GeoResult(this.fix, this.error);
  final Fix? fix;
  final GeoErr? error;
}

/// Demande la position GPS actuelle. Ne lève jamais d'exception :
/// en cas d'échec, renvoie la dernière position connue ou une erreur.
Future<GeoResult> getFix({int seconds = 15}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const GeoResult(null, GeoErr.serviceOff);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return const GeoResult(null, GeoErr.denied);
    }
    if (perm == LocationPermission.deniedForever) {
      return const GeoResult(null, GeoErr.deniedForever);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: seconds),
        ),
      );
      return GeoResult(Fix(pos.latitude, pos.longitude, pos.accuracy), null);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return GeoResult(Fix(last.latitude, last.longitude, last.accuracy), null);
      }
      return const GeoResult(null, GeoErr.timeout);
    }
  } catch (_) {
    return const GeoResult(null, GeoErr.timeout);
  }
}

Future<void> openGeoSettings(GeoErr e) async {
  if (e == GeoErr.serviceOff) {
    await Geolocator.openLocationSettings();
  } else {
    await Geolocator.openAppSettings();
  }
}

double distanceM(Fix a, Fix b) =>
    Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);
