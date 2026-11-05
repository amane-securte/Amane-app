import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geo.dart';

/// Configuration du projet Firebase « amane-securite » (application Android).
const _androidOptions = FirebaseOptions(
  apiKey: 'AIzaSyD2f7Zmx3kSwUZ0FE7X0cDM1h56vAJFIIM',
  appId: '1:1053668841593:android:c1277c6200182984205ca8',
  messagingSenderId: '1053668841593',
  projectId: 'amane-securite',
  storageBucket: 'amane-securite.firebasestorage.app',
);

/// Version web (iPhone, ordinateur) : https://amane-securite.web.app
const _webOptions = FirebaseOptions(
  apiKey: 'AIzaSyDXqmiS42hshRVV1G-z8fildsJOxo4-cBU',
  appId: '1:1053668841593:web:f37c1a80453a7a08205ca8',
  messagingSenderId: '1053668841593',
  projectId: 'amane-securite',
  authDomain: 'amane-securite.firebaseapp.com',
  storageBucket: 'amane-securite.firebasestorage.app',
  measurementId: 'G-YN8DHXSWE3',
);

const firebaseOptions = kIsWeb ? _webOptions : _androidOptions;

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

/// Postes dans la société (indépendants des droits dans l'appli).
const jobs = ['guard', 'mobile', 'bodyguard', 'driver', 'supervisor', 'accountant', 'admin_staff', 'manager', 'dg', 'other'];

const jobsFr = {
  'guard': 'Agent de sécurité',
  'mobile': 'Agent mobile (renfort et appui)',
  'bodyguard': 'Garde du corps (protection rapprochée)',
  'driver': 'Chauffeur',
  'supervisor': 'Superviseur',
  'accountant': 'Comptable',
  'admin_staff': 'Employé administratif',
  'manager': 'Directeur / responsable',
  'dg': 'Directeur Général',
  'other': 'Autre',
};

class UserDoc {
  UserDoc(this.id, Map<String, dynamic> m)
      : name = _str(m['name']),
        phone = _str(m['phone']),
        role = _str(m['role']).isEmpty ? 'pending' : _str(m['role']),
        siteName = _str(m['siteName']),
        mission = _str(m['mission']),
        job = _str(m['job']).isNotEmpty
            ? _str(m['job'])
            : (_str(m['role']) == 'admin' ? 'manager' : 'guard'),
        idNo = _str(m['idNo']),
        address = _str(m['address']),
        contractNo = _str(m['contractNo']),
        emergency = _str(m['emergency']),
        rep = _str(m['rep']),
        consentAt = _date(m['consentAt']),
        siteId = m['siteId'] is String ? m['siteId'] as String : null;
  final String id, name, phone, role, siteName;
  /// Fiche : pièce d'identité (NNI), adresse, n° de contrat,
  /// personne à prévenir (agents), représentant (clients).
  final String idNo, address, contractNo, emergency, rep;
  /// Date d'acceptation électronique des conditions (null = pas encore).
  final DateTime? consentAt;
  /// Poste (guard, bodyguard, driver, accountant, manager, dg…).
  final String job;
  /// Mission en cours (ex. : protection de l'ambassadeur X, chauffeur de la DG).
  final String mission;
  final String? siteId;
}

class Site {
  Site(this.id, Map<String, dynamic> m)
      : name = _str(m['name']),
        client = _str(m['client']),
        type = _str(m['type']),
        services = [
          if (m['services'] is List)
            for (final x in m['services'] as List)
              if (x is String) x,
        ],
        fix = Fix.read(m, ''),
        radius = m['radius'] is num ? (m['radius'] as num).toInt() : 200;
  final String id, name, client;
  /// Type de site (particulier, villa, institution, banque, boutique…).
  final String type;
  /// Prestations souscrites (voir services.dart).
  final List<String> services;
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
        outOk = m['outOk'] is bool ? m['outOk'] as bool : null,
        lastFix = Fix.read(m, 'last'),
        lastAt = _date(m['lastAt']);
  final String id, uid, name, phone, siteName;
  /// Dernière position transmise pendant la mission (suivi continu).
  final Fix? lastFix;
  final DateTime? lastAt;

  /// Position la plus récente connue : suivi, sinon pointage d'arrivée.
  Fix? get bestFix => lastFix ?? inFix;
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
        source = _str(m['source']).isEmpty ? 'guard' : _str(m['source']),
        action = _str(m['action']),
        note = _str(m['note']),
        at = _date(m['at']) ?? DateTime.now(),
        fix = Fix.read(m, '');
  final String id, uid, name, phone, siteName, type, status, source, action, note;
  bool get fromClient => source == 'client';
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

/// Postes itinérants : pas de site fixe, donc pas d'alerte « hors site ».
const mobileJobs = {'mobile', 'supervisor', 'bodyguard', 'driver'};

// ---------------------------------------------------------------------------
// Société et cotisations sociales (notification CNSS du 15/05/2025).
// ---------------------------------------------------------------------------

/// Plafond mensuel de cotisation et SMIG (MRU).
const cnssCeiling = 15000.0;
const smig = 4500.0;
/// 14 % sécurité sociale (1 % salarié, 13 % employeur) + 2 % médecine du travail (employeur).
const cnssEmployeeRate = 0.01;
const cnssEmployerRate = 0.13;
const workMedicineRate = 0.02;

/// Cotisations d'un mois sur la base [taxable] (plafonnée).
/// Renvoie (part salarié, part employeur y compris médecine du travail).
(double, double) cnssFor(double taxable) {
  final base = taxable <= 0 ? 0.0 : (taxable > cnssCeiling ? cnssCeiling : taxable);
  return (
    (base * cnssEmployeeRate).roundToDouble(),
    (base * (cnssEmployerRate + workMedicineRate)).roundToDouble(),
  );
}
