import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Une position GPS : latitude, longitude, précision en mètres.
class Fix {
  const Fix(this.lat, this.lng, this.acc);
  final double lat;
  final double lng;
  final double acc;

  String get mapUrl =>
      'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  /// Lit une position enregistrée sous la forme `<p>Lat`, `<p>Lng`, `<p>Acc`.
  static Fix? read(Map<String, dynamic> m, String p) {
    final lat = m['${p}Lat'], lng = m['${p}Lng'], acc = m['${p}Acc'];
    if (lat is! num || lng is! num) return null;
    return Fix(lat.toDouble(), lng.toDouble(), acc is num ? acc.toDouble() : 0);
  }

  Map<String, dynamic> write(String p) =>
      {'${p}Lat': lat, '${p}Lng': lng, '${p}Acc': acc.round()};

  /// Comprend « 20.94, -17.03 » ou un lien Google Maps.
  static Fix? parse(String s) {
    final m = RegExp(r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)').firstMatch(s);
    if (m == null) return null;
    final lat = double.parse(m.group(1)!), lng = double.parse(m.group(2)!);
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return Fix(lat, lng, 0);
  }
}

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
      // GPS lent (intérieur, téléphone froid) : position réseau, plus rapide.
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        return GeoResult(Fix(pos.latitude, pos.longitude, pos.accuracy), null);
      } catch (_) {}
      Position? last;
      try {
        last = await Geolocator.getLastKnownPosition();
      } catch (_) {}
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

/// Centre de Nouakchott : au-delà de [inlandKm], le client est « à l'intérieur »
/// (hors de portée des patrouilles AMANE) : gendarmerie / police locale d'abord.
const nouakchott = Fix(18.0858, -15.9785, 0);
const inlandKm = 35.0;

/// Distance en km depuis Nouakchott, ou null sans position.
double? kmFromNouakchott(Fix? f) => f == null ? null : distanceM(f, nouakchott) / 1000;

bool isInland(Fix? f) => (kmFromNouakchott(f) ?? 0) > inlandKm;


/// SOS parti sans position : on continue à chercher (3 essais de 30 s) et on
/// complète l'alerte dès que le GPS répond.
Future<void> completeAlertFix(DocumentReference<Map<String, dynamic>> ref) async {
  for (var i = 0; i < 3; i++) {
    final r = await getFix(seconds: 30);
    final f = r.fix;
    if (f != null) {
      try {
        await ref.update({...f.write(''), 'lateFix': true});
      } catch (_) {}
      return;
    }
    if (r.error == GeoErr.denied || r.error == GeoErr.deniedForever || r.error == GeoErr.serviceOff) return;
  }
}
