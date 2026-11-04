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
  String? _punchId;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _sub != null;

  /// Démarre (ou garde) le suivi pour ce pointage.
  Future<void> start(String punchId, {required String title, required String text}) async {
    if (_punchId == punchId && _sub != null) return;
    await stop();
    _punchId = punchId;
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
          distanceFilter: 50,
          intervalDuration: const Duration(minutes: 2),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      } else {
        settings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50);
      }
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _sub = null;
    }
  }

  void _onPosition(Position p) {
    final id = _punchId;
    if (id == null) return;
    final now = DateTime.now();
    // Une écriture au plus toutes les 90 s pour ménager batterie et forfait.
    if (now.difference(_lastWrite) < const Duration(seconds: 90)) return;
    _lastWrite = now;
    db.collection('punches').doc(id).update({
      'lastLat': p.latitude,
      'lastLng': p.longitude,
      'lastAcc': p.accuracy.round(),
      'lastAt': Timestamp.fromDate(now),
    }).catchError((_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _punchId = null;
  }
}
