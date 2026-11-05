import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Son court de notification (nouveau message, nouvelle entrée de la main
/// courante). Fonctionne tant que l'application est ouverte, ou en arrière-plan
/// sur le téléphone de la salle de contrôle (mode « salle de contrôle »).
class Chime {
  static AudioPlayer? _p;
  static DateTime _last = DateTime(2000);

  static Future<void> play() async {
    // Pas plus d'un son toutes les 3 secondes (arrivées groupées).
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 3)) return;
    _last = now;
    HapticFeedback.mediumImpact();
    try {
      final p = _p ??= AudioPlayer();
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.notification,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      await p.stop();
      await p.play(AssetSource('chime.wav'), volume: 1.0);
    } catch (_) {}
  }
}

/// Écoute [q] et appelle [onNew] pour chaque document ajouté après le premier
/// chargement (les anciens documents ne sonnent pas).
StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchNew(
  Query<Map<String, dynamic>> q,
  void Function(Map<String, dynamic> data) onNew,
) {
  var first = true;
  return q.snapshots().listen((s) {
    if (first) {
      first = false;
      return;
    }
    for (final c in s.docChanges) {
      if (c.type == DocumentChangeType.added && !c.doc.metadata.hasPendingWrites) {
        final m = c.doc.data();
        if (m == null) continue;
        // Entrées anciennes arrivées avec la synchronisation : pas de son.
        final at = m['at'];
        if (at is Timestamp && DateTime.now().difference(at.toDate()) > const Duration(minutes: 15)) continue;
        onNew(m);
      }
    }
  }, onError: (_) {});
}
