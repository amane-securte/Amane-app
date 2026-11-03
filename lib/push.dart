import 'package:firebase_messaging/firebase_messaging.dart';

import 'data.dart';

/// Enregistre l'appareil pour les notifications (alertes SOS, réponses
/// d'AMANE au client). L'envoi est fait par la fonction serveur
/// `functions/index.js`, active une fois le forfait Blaze activé.
class Push {
  static String? _savedFor;

  static Future<void> register(String uid) async {
    if (_savedFor == uid) return;
    _savedFor = uid;
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, sound: true, badge: true);
      final token = await m.getToken();
      if (token == null) return;
      await db.collection('users').doc(uid).update({'fcmToken': token});
      m.onTokenRefresh.listen((tk) {
        db.collection('users').doc(uid).update({'fcmToken': tk}).catchError((_) {});
      });
    } catch (_) {
      // Pas de Google Play Services, refus, ou hors ligne : l'appli marche sans.
      _savedFor = null;
    }
  }
}
