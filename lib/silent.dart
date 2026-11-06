import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'geo.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Alerte silencieuse (enlèvement, menace) : rien ne s'affiche ni ne sonne sur
/// le téléphone de l'expéditeur ; seule la salle de contrôle est alertée.
/// [type] : 'silent' (bouton discret) ou 'duress' (code sous contrainte).
Future<void> sendSilentAlert(UserDoc me, {required String type, String note = ''}) async {
  final r = await getFix(seconds: 12);
  final f = r.fix;
  final ref = db.collection('alerts').doc();
  // Écriture sans attendre : gardée hors réseau, envoyée dès le retour du réseau.
  ref.set({
    'uid': me.id,
    'name': me.name,
    'phone': me.phone,
    'siteName': me.siteName,
    'type': type,
    'fromClient': me.role == 'client',
    'status': 'open',
    'source': 'silent',
    'note': note,
    'at': Timestamp.now(),
    if (f != null) ...f.write(''),
    if (f == null && r.error != null) 'gpsErr': r.error!.name,
  }).catchError((_) {});
  if (f == null) completeAlertFix(ref).ignore();
}

/// Bouton discret : appui long de 2 secondes, une simple vibration en retour.
class SilentSosButton extends StatelessWidget {
  const SilentSosButton({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: t('silent_tip'),
        child: GestureDetector(
          onLongPress: () {
            HapticFeedback.lightImpact();
            sendSilentAlert(me, type: 'silent');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFDBD1BA)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.volume_off, size: 18, color: muted),
              const SizedBox(width: 6),
              Text(t('silent_btn'), style: const TextStyle(color: muted, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Codes de sécurité gardés sur le téléphone seulement (jamais envoyés) :
/// code normal et code sous contrainte.
class SafetyCodes {
  static const _safe = 'safe_pin', _duress = 'duress_pin';

  static Future<(String?, String?)> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_safe), p.getString(_duress));
  }

  static Future<void> save(String safe, String duress) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_safe, safe);
    await p.setString(_duress, duress);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_safe);
    await p.remove(_duress);
  }

  /// Écran de réglage des deux codes.
  static Future<void> setup(BuildContext context, T t) async {
    final (s0, d0) = await load();
    if (!context.mounted) return;
    final safe = TextEditingController(text: s0 ?? '');
    final duress = TextEditingController(text: d0 ?? '');
    String? err;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          icon: const Icon(Icons.key, color: navy, size: 34),
          title: Text(t('codes_title')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('codes_hint'), style: const TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: safe,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(labelText: t('code_safe')),
              ),
              TextField(
                controller: duress,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(labelText: t('code_duress'), helperText: t('code_duress_help')),
              ),
              if (err != null) Text(err!, style: const TextStyle(color: danger)),
            ]),
          ),
          actions: [
            if (s0 != null) TextButton(onPressed: () => Navigator.pop(ctx, 'clear'), child: Text(t('codes_off'))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(
              onPressed: () {
                final a = safe.text.trim(), b = duress.text.trim();
                if (a.length < 4 || b.length < 4) return setD(() => err = t('codes_short'));
                if (a == b) return setD(() => err = t('codes_same'));
                Navigator.pop(ctx, 'save');
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
    if (v == 'save') {
      await save(safe.text.trim(), duress.text.trim());
      if (context.mounted) snack(context, t('codes_saved'), color: okGreen);
    } else if (v == 'clear') {
      await clear();
      if (context.mounted) snack(context, t('codes_cleared'), color: okGreen);
    }
  }

  /// Avant « Je suis arrivé » ou « Je vais bien » : demande le code si des
  /// codes sont réglés. Retourne false si l'action doit être annulée.
  /// Code sous contrainte : l'action se fait normalement à l'écran, et une
  /// alerte silencieuse part vers la salle de contrôle.
  static Future<bool> confirm(BuildContext context, T t, UserDoc me, {String note = ''}) async {
    final (safe, duress) = await load();
    if (safe == null || duress == null || !context.mounted) return true;
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('code_enter')),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t('ok'))),
        ],
      ),
    );
    if (v == null) return false;
    if (v == duress) {
      sendSilentAlert(me, type: 'duress', note: note);
      return true;
    }
    if (v == safe) return true;
    if (context.mounted) snack(context, t('code_wrong'), color: danger);
    return false;
  }
}
