import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'data.dart';

/// Suivi GPS pendant la mission : position envoyée toutes les 2 minutes
/// (ou après 50 m de déplacement) dans le pointage ouvert.
/// Sur Android, une notification « AMANE – suivi de mission » reste affichée
/// pour que la position continue d'être transmise écran éteint.
class ShiftTracker {
  ShiftTracker._();
  static final instance = ShiftTracker._();

  StreamSubscription<Position>? _sub;
  Timer? _beat;
  bool _mobile = false;
  String? _punchId;
  /// « punches » (service d'un agent) ou « trips » (trajet d'un client).
  String collection = 'punches';
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _sub != null;

  /// Démarre (ou garde) le suivi pour ce pointage.
  /// [mobile] : garde du corps, agent mobile, superviseur, chauffeur. Suivi
  /// plus serré et position renvoyée toutes les 5 min même à l'arrêt, pour
  /// que la salle de contrôle sache toujours où il est.
  Future<void> start(String punchId,
      {required String title, required String text, bool mobile = false, String collection = 'punches'}) async {
    if (_punchId == punchId && _sub != null && _mobile == mobile) return;
    await stop();
    _punchId = punchId;
    this.collection = collection;
    _mobile = mobile;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      final LocationSettings settings;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: mobile ? 25 : 50,
          intervalDuration: Duration(minutes: mobile ? 1 : 2),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      } else {
        settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: mobile ? 25 : 50);
      }
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (_) {},
        cancelOnError: false,
      );
      if (mobile) {
        _beat = Timer.periodic(const Duration(minutes: 5), (_) async {
          if (DateTime.now().difference(_lastWrite) < const Duration(minutes: 4)) return;
          try {
            final p = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 30)));
            _write(p, force: true);
          } catch (_) {}
        });
      }
    } catch (_) {
      _sub = null;
    }
  }

  void _onPosition(Position p) => _write(p);

  void _write(Position p, {bool force = false}) {
    final id = _punchId;
    if (id == null) return;
    final now = DateTime.now();
    // Une écriture au plus toutes les 90 s (60 s pour les itinérants).
    if (!force && now.difference(_lastWrite) < Duration(seconds: _mobile ? 60 : 90)) return;
    _lastWrite = now;
    db.collection(collection).doc(id).update({
      'lastLat': p.latitude,
      'lastLng': p.longitude,
      'lastAcc': p.accuracy.round(),
      'lastAt': Timestamp.fromDate(now),
    }).catchError((_) {});
  }

  Future<void> stop() async {
    _beat?.cancel();
    _beat = null;
    await _sub?.cancel();
    _sub = null;
    _punchId = null;
  }
}
