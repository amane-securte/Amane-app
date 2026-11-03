import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'geo.dart';
import 'i18n.dart';
import 'theme.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: cream,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo_full_t.png', height: 220),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: gold),
            ],
          ),
        ),
      );
}

/// Barre du haut commune : logo, nom, bouton de langue, déconnexion.
PreferredSizeWidget amaneAppBar(BuildContext context, Prefs prefs,
    {bool showLogout = true, PreferredSizeWidget? bottom}) {
  final t = T(prefs.lang);
  return AppBar(
    titleSpacing: 12,
    bottom: bottom,
    title: Row(
      children: [
        Image.asset('assets/logo.png', height: 34),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AMANE',
                style: TextStyle(
                    fontSize: 19, letterSpacing: 2, fontWeight: FontWeight.w600)),
            Text(t('app_sub'),
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFD1A850))),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: prefs.toggleLang,
        child: Text(t('lang_btn'),
            style: const TextStyle(color: Color(0xFFFBF6EA))),
      ),
      if (showLogout && FirebaseAuth.instance.currentUser != null)
        IconButton(
          tooltip: t('change_pass'),
          icon: const Icon(Icons.key),
          onPressed: () => changePassword(context, t),
        ),
      if (showLogout && FirebaseAuth.instance.currentUser != null)
        IconButton(
          tooltip: t('logout'),
          icon: const Icon(Icons.logout),
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
    ],
  );
}

Widget pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );

void snack(BuildContext context, String msg,
    {Color? color, SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      action: action,
      duration: const Duration(seconds: 5),
    ));
}

/// Texte et couleur d'un pointage : sur site, hors site, sans GPS…
(String, Color) locInfo(T t, Fix? f, double? dist, bool? ok) {
  if (f == null) return (t('no_gps'), muted);
  if (dist == null || ok == null) return (t('no_site'), muted);
  final d = dist.round().toString();
  return ok ? (t('on_site', {'d': d}), okGreen) : (t('off_site', {'d': d}), danger);
}

String gpsErrorText(T t, GeoErr e) => switch (e) {
      GeoErr.serviceOff => t('gps_off'),
      GeoErr.denied || GeoErr.deniedForever => t('gps_denied'),
      GeoErr.timeout => t('gps_timeout'),
    };

void showGpsError(BuildContext context, T t, GeoErr e) {
  snack(context, gpsErrorText(t, e),
      color: warn,
      action: e == GeoErr.timeout
          ? null
          : SnackBarAction(
              label: t('open_settings'),
              textColor: Colors.white,
              onPressed: () => openGeoSettings(e),
            ));
}

Future<void> openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String durText(T t, Duration d) {
  final m = d.inMinutes;
  return t('dur', {'h': '${m ~/ 60}', 'm': '${m % 60}'});
}

/// Heure en chiffres latins, toujours de gauche à droite.
Widget ltrText(String s, {TextStyle? style}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Text(s, style: style),
    );

/// Changer son mot de passe (le compte doit être connecté depuis peu).
Future<void> changePassword(BuildContext context, T t) async {
  final c1 = TextEditingController(), c2 = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('change_pass')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: c1, obscureText: true,
              decoration: InputDecoration(labelText: t('new_pass'))),
          const SizedBox(height: 10),
          TextField(controller: c2, obscureText: true,
              decoration: InputDecoration(labelText: t('new_pass2'))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (c1.text.length < 6) { snack(context, t('err_weak'), color: danger); return; }
  if (c1.text != c2.text) { snack(context, t('pass_mismatch'), color: danger); return; }
  try {
    await FirebaseAuth.instance.currentUser?.updatePassword(c1.text);
    if (context.mounted) snack(context, t('pass_changed'), color: okGreen);
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return;
    snack(context, e.code == 'requires-recent-login' ? t('relogin') : t('err_generic', {'e': e.code}),
        color: danger);
  }
}
