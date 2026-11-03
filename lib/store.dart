import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geo.dart';

/// Une position GPS : latitude, longitude, précision en mètres.
class Fix {
  const Fix(this.lat, this.lng, this.acc);
  final double lat;
  final double lng;
  final double acc;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'acc': acc};

  static Fix? fromJson(dynamic j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    final acc = j['acc'];
    return Fix(lat.toDouble(), lng.toDouble(), acc is num ? acc.toDouble() : 0);
  }

  String get mapUrl =>
      'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// Une mission pointée : arrivée et, une fois terminée, départ.
class Punch {
  Punch(this.inAt, this.inFix, {this.outAt, this.outFix});
  final DateTime inAt;
  final Fix? inFix;
  DateTime? outAt;
  Fix? outFix;

  Map<String, dynamic> toJson() => {
        'inAt': inAt.toIso8601String(),
        'inFix': inFix?.toJson(),
        'outAt': outAt?.toIso8601String(),
        'outFix': outFix?.toJson(),
      };

  static Punch? fromJson(dynamic j) {
    if (j is! Map) return null;
    final inAt = DateTime.tryParse('${j['inAt']}');
    if (inAt == null) return null;
    return Punch(
      inAt,
      Fix.fromJson(j['inFix']),
      outAt: j['outAt'] == null ? null : DateTime.tryParse('${j['outAt']}'),
      outFix: Fix.fromJson(j['outFix']),
    );
  }
}

/// État de l'application, enregistré sur le téléphone.
/// (Version de test : sera synchronisé avec le serveur Firebase plus tard.)
class AppState extends ChangeNotifier {
  late SharedPreferences _p;

  String lang = 'ar';
  String name = '';
  String phone = '';
  String site = '';
  Fix? siteFix;
  int radius = 200;
  Punch? current;
  List<Punch> history = [];

  bool get configured => name.trim().isNotEmpty;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    lang = _p.getString('lang') ?? 'ar';
    if (lang != 'ar' && lang != 'fr') lang = 'ar';
    name = _p.getString('name') ?? '';
    phone = _p.getString('phone') ?? '';
    site = _p.getString('site') ?? '';
    radius = _p.getInt('radius') ?? 200;
    siteFix = _decode(_p.getString('siteFix'), Fix.fromJson);
    current = _decode(_p.getString('current'), Punch.fromJson);
    final h = _p.getString('history');
    if (h != null) {
      try {
        history = (jsonDecode(h) as List)
            .map(Punch.fromJson)
            .whereType<Punch>()
            .toList();
      } catch (_) {
        history = [];
      }
    }
  }

  T? _decode<T>(String? s, T? Function(dynamic) f) {
    if (s == null) return null;
    try {
      return f(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  Future<void> setLang(String l) async {
    lang = l;
    await _p.setString('lang', l);
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String phone,
    required String site,
    required int radius,
    Fix? siteFix,
  }) async {
    this.name = name.trim();
    this.phone = phone.trim();
    this.site = site.trim();
    this.radius = radius;
    this.siteFix = siteFix;
    await _p.setString('name', this.name);
    await _p.setString('phone', this.phone);
    await _p.setString('site', this.site);
    await _p.setInt('radius', radius);
    if (siteFix == null) {
      await _p.remove('siteFix');
    } else {
      await _p.setString('siteFix', jsonEncode(siteFix.toJson()));
    }
    notifyListeners();
  }

  Future<void> punchIn(Fix? f) async {
    current = Punch(DateTime.now(), f);
    await _p.setString('current', jsonEncode(current!.toJson()));
    notifyListeners();
  }

  Future<void> punchOut(Fix? f) async {
    final c = current;
    if (c == null) return;
    c.outAt = DateTime.now();
    c.outFix = f;
    history.insert(0, c);
    if (history.length > 60) history = history.sublist(0, 60);
    current = null;
    await _p.remove('current');
    await _p.setString(
        'history', jsonEncode(history.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  /// Distance en mètres entre une position et le site, ou null si inconnue.
  double? distToSite(Fix? f) {
    final s = siteFix;
    if (f == null || s == null) return null;
    return distanceM(f, s);
  }

  /// Vrai si la position est dans le rayon du site (avec la précision GPS).
  bool? onSite(Fix? f) {
    final d = distToSite(f);
    if (d == null || f == null) return null;
    return d <= radius + math.min(f.acc, 150);
  }
}
