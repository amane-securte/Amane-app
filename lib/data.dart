import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geo.dart';

/// Configuration du projet Firebase « amane-securite » (application Android).
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyD2f7Zmx3kSwUZ0FE7X0cDM1h56vAJFIIM',
  appId: '1:1053668841593:android:c1277c6200182984205ca8',
  messagingSenderId: '1053668841593',
  projectId: 'amane-securite',
  storageBucket: 'amane-securite.firebasestorage.app',
);

/// Le compte du gérant est toujours administrateur.
const ownerEmail = 'amane.services.securite@gmail.com';

FirebaseFirestore get db => FirebaseFirestore.instance;

typedef DocumentSnapshotMap = DocumentSnapshot<Map<String, dynamic>>;
typedef QueryMap = QuerySnapshot<Map<String, dynamic>>;

/// Les agents se connectent avec leur numéro : il est converti en adresse
/// interne (22226511010@amane.app). Une vraie adresse e-mail reste telle quelle.
String loginEmail(String input) {
  final t = input.trim();
  if (t.contains('@')) return t.toLowerCase();
  var d = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 8) d = '222$d';
  return '$d@amane.app';
}

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;
String _str(dynamic v) => v is String ? v : '';

class UserDoc {
  UserDoc(this.id, Map<String, dynamic> m)
      : name = _str(m['name']),
        phone = _str(m['phone']),
        role = _str(m['role']).isEmpty ? 'pending' : _str(m['role']),
        siteId = m['siteId'] is String ? m['siteId'] as String : null;
  final String id, name, phone, role;
  final String? siteId;
}

class Site {
  Site(this.id, Map<String, dynamic> m)
      : name = _str(m['name']),
        fix = Fix.read(m, ''),
        radius = m['radius'] is num ? (m['radius'] as num).toInt() : 200;
  final String id, name;
  final Fix? fix;
  final int radius;
}

class PunchDoc {
  PunchDoc(this.id, Map<String, dynamic> m)
      : uid = _str(m['uid']),
        name = _str(m['name']),
        phone = _str(m['phone']),
        siteName = _str(m['siteName']),
        inAt = _date(m['inAt']) ?? DateTime.now(),
        inFix = Fix.read(m, 'in'),
        inDist = m['inDist'] is num ? (m['inDist'] as num).toDouble() : null,
        inOk = m['inOk'] is bool ? m['inOk'] as bool : null,
        outAt = _date(m['outAt']),
        outFix = Fix.read(m, 'out'),
        outDist = m['outDist'] is num ? (m['outDist'] as num).toDouble() : null,
        outOk = m['outOk'] is bool ? m['outOk'] as bool : null;
  final String id, uid, name, phone, siteName;
  final DateTime inAt;
  final Fix? inFix;
  final double? inDist;
  final bool? inOk;
  final DateTime? outAt;
  final Fix? outFix;
  final double? outDist;
  final bool? outOk;

  bool get open => outAt == null;
  bool get offSite => inOk == false || outOk == false;
}

class AlertDoc {
  AlertDoc(this.id, Map<String, dynamic> m)
      : uid = _str(m['uid']),
        name = _str(m['name']),
        phone = _str(m['phone']),
        siteName = _str(m['siteName']),
        type = _str(m['type']),
        status = _str(m['status']),
        at = _date(m['at']) ?? DateTime.now(),
        fix = Fix.read(m, '');
  final String id, uid, name, phone, siteName, type, status;
  final DateTime at;
  final Fix? fix;
}

/// Distance au site et « sur site / hors site », ou (null, null) si inconnu.
(double?, bool?) checkSite(Fix? f, Site? s) {
  final sf = s?.fix;
  if (f == null || s == null || sf == null) return (null, null);
  final d = distanceM(f, sf);
  return (d, d <= s.radius + math.min(f.acc, 150));
}

/// Langue de l'interface, enregistrée sur le téléphone.
class Prefs extends ChangeNotifier {
  late SharedPreferences _p;
  String lang = 'ar';

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final l = _p.getString('lang');
    lang = (l == 'fr') ? 'fr' : 'ar';
  }

  Future<void> toggleLang() async {
    lang = lang == 'ar' ? 'fr' : 'ar';
    await _p.setString('lang', lang);
    notifyListeners();
  }
}
