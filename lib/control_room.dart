import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';

/// « Salle de contrôle » : écoute des alertes SOS pour l'administration.
///
/// - Tant que l'écran d'administration est ouvert, chaque nouvelle alerte
///   déclenche la sirène (boucle) et est publiée sur [newAlerts].
/// - Si le « mode salle de contrôle » est activé, un service Android de
///   premier plan (notification permanente) garde l'application vivante
///   en arrière-plan : la sirène sonne même application réduite ou écran
///   éteint, sans serveur ni forfait Blaze.
class ControlRoom {
  ControlRoom._();
  static final instance = ControlRoom._();

  static const _prefKey = 'control_room';

  final _newAlerts = StreamController<AlertDoc>.broadcast();
  Stream<AlertDoc> get newAlerts => _newAlerts.stream;

  /// Mode arrière-plan activé (mémorisé sur le téléphone).
  final enabled = ValueNotifier<bool>(false);

  StreamSubscription<QueryMap>? _alertsSub;
  StreamSubscription<Position>? _keepAlive;
  final _seen = <String>{};
  bool _loaded = false;
  AudioPlayer? _siren;
  Timer? _vibe, _autoStop;

  /// Démarre l'écoute (appelé à l'ouverture de l'écran d'administration).
  Future<void> attach({required String title, required String text}) async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_prefKey) ?? false;
    } catch (_) {}
    _alertsSub ??= db
        .collection('alerts')
        .where('status', whereIn: ['open', 'taken'])
        .snapshots()
        .listen(_onAlerts, onError: (_) {});
    if (enabled.value) await _startKeepAlive(title, text);
  }

  /// Arrête tout (déconnexion).
  Future<void> detach() async {
    await _alertsSub?.cancel();
    _alertsSub = null;
    _seen.clear();
    _loaded = false;
    await _stopKeepAlive();
    silence();
  }

  /// Active / désactive le mode arrière-plan. Renvoie false si la
  /// localisation (nécessaire au service Android) est refusée.
  Future<bool> setEnabled(bool on, {required String title, required String text}) async {
    if (on) {
      final ok = await _startKeepAlive(title, text);
      if (!ok) return false;
    } else {
      await _stopKeepAlive();
    }
    enabled.value = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, on);
    } catch (_) {}
    return true;
  }

  void _onAlerts(QueryMap q) {
    final alerts = q.docs.map((d) => AlertDoc(d.id, d.data())).toList();
    final fresh = alerts.where((a) => a.status == 'open' && !_seen.contains(a.id)).toList();
    _seen.addAll(alerts.map((a) => a.id));
    // Plusieurs directeurs ou opérateurs : dès qu'un collègue a pris en charge
    // toutes les alertes, la sirène s'arrête aussi sur les autres téléphones.
    if (_loaded && alerts.every((a) => a.status != 'open')) silence();
    if (_loaded && fresh.isNotEmpty) {
      fresh.sort((a, b) => b.at.compareTo(a.at));
      ring();
      for (final a in fresh) {
        _newAlerts.add(a);
      }
    }
    _loaded = true;
  }

  /// Sirène en boucle + vibrations, coupée par [silence] ou après 3 minutes.
  Future<void> ring() async {
    if (_siren != null) return;
    final s = AudioPlayer();
    _siren = s;
    try {
      await s.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
          stayAwake: true,
        ),
      ));
      await s.setReleaseMode(ReleaseMode.loop);
      await s.play(AssetSource('siren.wav'), volume: 1.0);
    } catch (_) {}
    _vibe = Timer.periodic(const Duration(milliseconds: 900), (_) => HapticFeedback.heavyImpact());
    _autoStop = Timer(const Duration(minutes: 3), silence);
  }

  void silence() {
    _vibe?.cancel();
    _autoStop?.cancel();
    _vibe = null;
    _autoStop = null;
    final s = _siren;
    _siren = null;
    if (s != null) {
      s.stop().catchError((_) {});
      s.dispose();
    }
  }

  /// Service de premier plan : un flux GPS très économe (1 point / 15 min)
  /// dont la notification permanente empêche Android d'arrêter l'appli.
  Future<bool> _startKeepAlive(String title, String text) async {
    if (_keepAlive != null) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return false;
      }
      _keepAlive = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 5000,
          intervalDuration: const Duration(minutes: 15),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).listen((_) {}, onError: (_) {}, cancelOnError: false);
      return true;
    } catch (_) {
      _keepAlive = null;
      return false;
    }
  }

  Future<void> _stopKeepAlive() async {
    await _keepAlive?.cancel();
    _keepAlive = null;
  }
}
