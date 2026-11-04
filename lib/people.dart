import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'geo.dart';
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
const _newSite = '__new__';

Future<void> addPerson(BuildContext context, T t, List<Site> sites) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final pass = TextEditingController(
      text: '${100000 + math.Random.secure().nextInt(900000)}');
  var role = 'guard';
  var job = 'guard';
  final mission = TextEditingController();
  final monthly = TextEditingController();
  String? siteId;
  final siteName = TextEditingController();
  // Nouveau site : position prise ici (« here ») ou plus tard (« later » ;
  // pour un client, son téléphone la fournira à la première connexion).
  var where = 'later';
  Fix? here;
  var locating = false;
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
          if (siteId == _newSite && where == 'here' && here == null) {
            setS(() => error = t('add_err_here'));
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
            String? sid = siteId;
            String sName = sites.where((s) => s.id == siteId).firstOrNull?.name ?? '';
            if (siteId == _newSite) {
              sName = siteName.text.trim().isEmpty ? n : siteName.text.trim();
              final ref = await db.collection('sites').add({
                'name': sName,
                'client': role == 'client' ? n : '',
                'radius': 200,
                'Lat': where == 'here' ? here?.lat : null,
                'Lng': where == 'here' ? here?.lng : null,
                if (where == 'later' && role == 'client') 'autoFrom': uid,
              });
              sid = ref.id;
            }
            await db.collection('users').doc(uid).update({
              'role': role,
              if (role != 'client') 'job': job,
              if (role != 'client' && mission.text.trim().isNotEmpty) 'mission': mission.text.trim(),
              if (sid != null) 'siteId': sid,
              if (sid != null) 'siteName': sName,
            });
            final m = double.tryParse(monthly.text.replaceAll(RegExp(r'[^0-9.]'), ''));
            if (role != 'client' && m != null && m > 0) {
              await db.collection('rates').doc('m_$uid').set({'rate': m});
            }
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
                  onSelectionChanged: (s) => setS(() {
                    role = s.first;
                    if (role == 'client' && siteId == null) siteId = _newSite;
                  }),
                ),
                if (role != 'client') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: job,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t('job')),
                    items: [
                      for (final j in jobs)
                        DropdownMenuItem(
                            value: j,
                            child: Row(children: [
                              Icon(jobIcon(j), size: 18, color: navy),
                              const SizedBox(width: 8),
                              Text(t('job_$j')),
                            ])),
                    ],
                    onChanged: (v) => setS(() => job = v ?? 'guard'),
                  ),
                  TextField(
                    controller: mission,
                    decoration: InputDecoration(
                        labelText: t('mission'), hintText: t('mission_hint_$job')),
                  ),
                  if (job != 'guard' && job != 'bodyguard')
                    TextField(
                      controller: monthly,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: t('monthly_salary'), suffixText: 'MRU'),
                    ),
                ],
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
                  key: ValueKey('site-$role'),
                  initialValue: siteId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('choose_site')),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final s in sites)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                    DropdownMenuItem(
                        value: _newSite,
                        child: Text(t('new_site'),
                            style: const TextStyle(color: navy, fontWeight: FontWeight.w600))),
                  ],
                  onChanged: (v) => setS(() => siteId = v),
                ),
                if (siteId == _newSite) ...[
                  TextField(
                    controller: siteName,
                    decoration: InputDecoration(
                        labelText: t('site_name'),
                        hintText: role == 'client' ? t('site_name_hint') : null),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.my_location, size: 18),
                      label: Text(t('loc_here')),
                      selected: where == 'here',
                      onSelected: (_) => setS(() => where = 'here'),
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: Text(t(role == 'client' ? 'loc_client' : 'loc_later')),
                      selected: where == 'later',
                      onSelected: (_) => setS(() => where = 'later'),
                    ),
                  ]),
                  if (where == 'here' && here != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('📍 ±${here!.acc.round()} m',
                          style: const TextStyle(color: okGreen)),
                    ),
                  if (where == 'here')
                    OutlinedButton.icon(
                      icon: locating
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: Text(t(here == null ? 'loc_take' : 'loc_retake')),
                      onPressed: locating
                          ? null
                          : () async {
                              setS(() => locating = true);
                              final r = await getFix();
                              setS(() {
                                locating = false;
                                here = r.fix ?? here;
                                if (r.fix == null) error = t('add_err_gps');
                              });
                            },
                    ),
                ],
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


IconData jobIcon(String j) => switch (j) {
      'guard' => Icons.badge,
      'bodyguard' => Icons.shield_moon,
      'driver' => Icons.directions_car,
      'supervisor' => Icons.supervisor_account,
      'accountant' => Icons.calculate,
      'admin_staff' => Icons.business_center,
      'manager' => Icons.manage_accounts,
      'dg' => Icons.workspace_premium,
      _ => Icons.person,
    };

/// Poste, mission et salaire d'un employé (administration).
Future<void> editStaff(BuildContext context, T t, UserDoc u) async {
  double rate(DocumentSnapshot<Map<String, dynamic>> d) =>
      (d.data()?['rate'] is num) ? (d.data()!['rate'] as num).toDouble() : 0;
  var job = u.job;
  final mission = TextEditingController(text: u.mission);
  final monthly = TextEditingController();
  final hourly = TextEditingController();
  try {
    final m = await db.collection('rates').doc('m_${u.id}').get();
    final h = await db.collection('rates').doc('g_${u.id}').get();
    if (rate(m) > 0) monthly.text = rate(m).toStringAsFixed(0);
    if (rate(h) > 0) hourly.text = rate(h).toStringAsFixed(0);
  } catch (_) {}
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(u.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: jobs.contains(job) ? job : 'other',
                isExpanded: true,
                decoration: InputDecoration(labelText: t('job')),
                items: [
                  for (final j in jobs)
                    DropdownMenuItem(
                        value: j,
                        child: Row(children: [
                          Icon(jobIcon(j), size: 18, color: navy),
                          const SizedBox(width: 8),
                          Text(t('job_$j')),
                        ])),
                ],
                onChanged: (v) => setS(() => job = v ?? job),
              ),
              TextField(
                controller: mission,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: t('mission'), hintText: t('mission_hint_$job')),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: monthly,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t('monthly_salary'), suffixText: 'MRU'),
              ),
              TextField(
                controller: hourly,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t('hourly_pay'), suffixText: 'MRU/h'),
              ),
              const SizedBox(height: 6),
              Text(t('salary_hint'), style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  double? num_(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(RegExp(r'[^0-9.]'), ''));
  await db.collection('users').doc(u.id).update({'job': job, 'mission': mission.text.trim()});
  await db.collection('rates').doc('m_${u.id}').set({'rate': num_(monthly) ?? 0});
  await db.collection('rates').doc('g_${u.id}').set({'rate': num_(hourly) ?? 0});
  if (context.mounted) snack(context, t('saved'), color: okGreen);
}
