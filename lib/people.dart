import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lien de téléchargement public de l'application (APK universel).
const appDownloadUrl =
    'https://github.com/amane-securte/Amane-app/releases/download/test-build/Amane.apk';

String _invite(T t, {String? phone, String? pass}) => [
      t('invite_intro'),
      appDownloadUrl,
      if (phone != null) '${t('invite_login')} $phone',
      if (pass != null) '${t('invite_pass')} $pass',
    ].join('\n');

String _intl(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 8) d = '222$d';
  return d;
}

/// Feuille « envoyer le lien de l'application » (WhatsApp, SMS, copier).
Future<void> shareInvite(BuildContext context, T t,
    {String? phone, String? pass}) async {
  final text = _invite(t, phone: phone, pass: pass);
  final to = phone == null ? '' : _intl(phone);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('invite_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(text, textDirection: TextDirection.rtl),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
              onPressed: () => openUrl(
                  'https://wa.me/$to?text=${Uri.encodeComponent(text)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.sms),
              label: const Text('SMS'),
              onPressed: () => openUrl(
                  'sms:${to.isEmpty ? '' : '+$to'}?body=${Uri.encodeComponent(text)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(t('copy')),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
                snack(context, t('copied'));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Crée le compte d'un agent ou d'un client depuis l'administration,
/// sans déconnecter l'administrateur (instance Firebase secondaire).
Future<void> addPerson(BuildContext context, T t, List<Site> sites) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final pass = TextEditingController(
      text: '${100000 + math.Random.secure().nextInt(900000)}');
  var role = 'guard';
  String? siteId;
  String? error;
  var busy = false;

  final done = await showDialog<(String, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> submit() async {
          final n = name.text.trim(), p = phone.text.trim(), pw = pass.text.trim();
          if (n.isEmpty || p.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
            setS(() => error = t('add_err_fields'));
            return;
          }
          if (pw.length < 6) {
            setS(() => error = t('add_err_pass'));
            return;
          }
          setS(() {
            busy = true;
            error = null;
          });
          try {
            final app = Firebase.apps.any((a) => a.name == 'adder')
                ? Firebase.app('adder')
                : await Firebase.initializeApp(name: 'adder', options: firebaseOptions);
            final a2 = FirebaseAuth.instanceFor(app: app);
            final email = loginEmail(p);
            final cred = await a2.createUserWithEmailAndPassword(email: email, password: pw);
            final uid = cred.user!.uid;
            await cred.user!.updateDisplayName(n);
            // Le nouveau compte crée lui-même son profil « en attente »
            // (autorisé par les règles), puis l'administrateur le valide.
            await FirebaseFirestore.instanceFor(app: app).collection('users').doc(uid).set({
              'name': n,
              'phone': p,
              'email': email,
              'role': 'pending',
              'createdAt': Timestamp.now(),
            });
            await a2.signOut();
            final s = sites.where((s) => s.id == siteId).firstOrNull;
            await db.collection('users').doc(uid).update({
              'role': role,
              if (s != null) 'siteId': s.id,
              if (s != null) 'siteName': s.name,
            });
            if (ctx.mounted) Navigator.pop(ctx, (p, pw));
          } on FirebaseAuthException catch (e) {
            setS(() {
              busy = false;
              error = e.code == 'email-already-in-use'
                  ? t('add_err_exists')
                  : t('err_generic', {'e': e.code});
            });
          } catch (e) {
            setS(() {
              busy = false;
              error = t('err_generic', {'e': '$e'});
            });
          }
        }

        return AlertDialog(
          title: Text(t('add_person')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'guard',
                        icon: const Icon(Icons.badge),
                        label: Text(t('role_guard'))),
                    ButtonSegment(
                        value: 'client',
                        icon: const Icon(Icons.storefront),
                        label: Text(t('role_client'))),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) => setS(() => role = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: t('name')),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t('phone'), hintText: '22 11 33 44'),
                ),
                TextField(
                  controller: pass,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t('add_pass')),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: siteId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('choose_site')),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final s in sites)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setS(() => siteId = v),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t('create_account')),
            ),
          ],
        );
      },
    ),
  );
  if (done == null || !context.mounted) return;
  snack(context, t('add_ok'), color: okGreen);
  await shareInvite(context, t, phone: done.$1, pass: done.$2);
}
