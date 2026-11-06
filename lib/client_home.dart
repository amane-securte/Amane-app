import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'emergency.dart';
import 'geo.dart';
import 'i18n.dart';
import 'notify.dart';
import 'client_site.dart';
import 'messages.dart';
import 'theme.dart';
import 'trips.dart';
import 'silent.dart';
import 'catalog.dart';
import 'widgets.dart';

/// Besoins qu'un client peut signaler, dans l'ordre d'affichage.
const clientNeeds = ['patrol', 'police', 'fire', 'medical', 'accident', 'breakdown', 'request'];

IconData needIcon(String n) => switch (n) {
      'patrol' => Icons.local_police,
      'police' => Icons.gpp_maybe,
      'fire' => Icons.local_fire_department,
      'medical' => Icons.medical_services,
      'request' => Icons.support_agent,
      'accident' => Icons.car_crash,
      'breakdown' || 'roadside' => Icons.car_repair,
      'overdue' => Icons.timer_off,
      'silent' => Icons.volume_off,
      'duress' => Icons.key,
      'assault' => Icons.front_hand,
      'intrusion' => Icons.door_front_door,
      _ => Icons.warning_amber_rounded,
    };

/// Espace client : bouton SOS avec position, suivi de la demande en direct,
/// appels directs à AMANE, à la police (17) et à la protection civile (18).
class ClientHome extends StatefulWidget {
  const ClientHome({super.key, required this.prefs, required this.me});
  final Prefs prefs;
  final UserDoc me;

  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  bool _busy = false;
  /// Client à l'intérieur du pays (loin de Nouakchott) : km, sinon null.
  double? _inlandKm;
  late final Stream<QueryMap> _mine =
      db.collection('alerts').where('uid', isEqualTo: widget.me.id).snapshots();

  T get t => T(widget.prefs.lang);
  UserDoc get me => widget.me;

  final _chimeSubs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _shareSiteLocation();
    String s(Object? v) => v is String ? v : '';
    // Réponses d'AMANE et main courante du site : son + bandeau.
    _chimeSubs.add(watchNew(db.collection('messages').where('clientUid', isEqualTo: me.id), (m) {
      if (s(m['from']) == 'client') return;
      Chime.play();
      if (mounted) snack(context, t('chime_reply', {'x': s(m['text'])}), color: navy);
    }));
    final sid = me.siteId;
    if (sid != null) {
      _chimeSubs.add(watchNew(db.collection('logs').where('siteId', isEqualTo: sid), (m) {
        Chime.play();
        if (mounted) {
          snack(context, t('chime_log', {'n': s(m['name']), 's': s(m['siteName']), 'c': t('cat_${s(m['category'])}'), 'x': s(m['text'])}),
              color: s(m['category']) == 'incident' ? danger : navy);
        }
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _chimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Site créé « automatiquement depuis le téléphone du client » : à la
  /// première ouverture, on envoie la position du client ; l'administration
  /// la reporte sur le site.
  Future<void> _shareSiteLocation() async {
    final sid = me.siteId;
    if (sid == null) return;
    try {
      final site = await db.collection('sites').doc(sid).get();
      final m = site.data();
      if (m == null || m['Lat'] is num || m['autoFrom'] != me.id) return;
      final r = await getFix(seconds: 25);
      final f = r.fix;
      if (f == null) return;
      await db.collection('users').doc(me.id).update({
        ...f.write('home'),
        'homeAt': Timestamp.now(),
      });
      if (mounted) snack(context, t('loc_shared'), color: okGreen);
    } catch (_) {}
  }

  Future<void> _send() async {
    final need = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('client_need_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final n in clientNeeds)
              ListTile(
                leading: Icon(needIcon(n), color: n == 'request' ? navy : n == 'breakdown' ? warn : danger),
                title: Text(t('need_$n'), style: const TextStyle(fontSize: 17)),
                subtitle: Text(t('need_${n}_sub')),
                onTap: () => Navigator.pop(ctx, n),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (need == null || !mounted) return;

    String note = '';
    if (need == 'request') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('need_request')),
          content: TextField(
            controller: c,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(hintText: t('request_hint')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('send'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      note = c.text.trim();
    }

    setState(() => _busy = true);
    final r = await getFix(seconds: 10);
    if (!mounted) return;
    final f = r.fix;
    final write = db.collection('alerts').add({
      'uid': me.id,
      'name': me.name,
      'phone': me.phone,
      'siteName': me.siteName,
      'source': 'client',
      'type': need,
      'note': note,
      'status': 'open',
      'at': Timestamp.now(),
      if (f != null) ...f.write(''),
      if (f == null && r.error != null) 'gpsErr': r.error!.name,
    });
    if (f == null) write.then(completeAlertFix).ignore();
    var online = true;
    try {
      await write.timeout(const Duration(seconds: 6));
    } catch (_) {
      online = false; // part au retour du réseau
    }
    if (!mounted) return;
    final km = kmFromNouakchott(f);
    setState(() {
      _busy = false;
      if (km != null) _inlandKm = km > inlandKm ? km : null;
    });
    if (r.error != null) showGpsError(context, t, r.error!);
    snack(context, t(online ? 'client_sent' : 'client_queued'),
        color: online ? okGreen : danger);
    // Réseau absent ou faible : SOS aussi par SMS vers la salle de contrôle.
    if (!online) {
      final body = [
        'SOS AMANE: ${t('need_$need')}',
        me.name,
        if (me.siteName.isNotEmpty) me.siteName,
        if (note.isNotEmpty) note,
        if (f != null) f.mapUrl,
      ].join(' - ');
      await openUrl('sms:$controlPhone?body=${Uri.encodeComponent(body)}');
    }
    // Hors de Nouakchott : la gendarmerie / police locale arrive plus vite.
    if (km != null && km > inlandKm && mounted && need != 'request') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.security, color: Color(0xFF2E5E3A), size: 44),
          title: Text(t('inland_title')),
          content: Text(t('inland_text', {'km': km.round().toString()})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('close'))),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E5E3A)),
              onPressed: () {
                Navigator.pop(ctx);
                openUrl('tel:$gendarmerieNumber');
              },
              icon: const Icon(Icons.phone),
              label: Text(t('call_gendarmerie')),
            ),
          ],
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkInland();
  }

  bool _inlandChecked = false;
  Future<void> _checkInland() async {
    if (_inlandChecked) return;
    _inlandChecked = true;
    try {
      final r = await getFix(seconds: 8);
      final km = kmFromNouakchott(r.fix);
      if (mounted && km != null && km > inlandKm) setState(() => _inlandKm = km);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: amaneAppBar(
          context,
          widget.prefs,
          bottom: TabBar(
            labelColor: const Color(0xFFD1A850),
            unselectedLabelColor: const Color(0xFFB8C2CC),
            indicatorColor: const Color(0xFFD1A850),
            tabs: [
              Tab(text: t('ctab_sos')),
              Tab(text: t('ctab_site')),
              Tab(text: t('ctab_invoices')),
              Tab(text: t('ctab_msg')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _sosTab(),
            ClientSiteTab(t: t, me: me),
            ClientInvoicesTab(t: t, me: me),
            ClientMessagesTab(t: t, me: me),
          ],
        ),
      ),
    );
  }

  Widget _sosTab() {
    return SafeArea(
        child: StreamBuilder<QueryMap>(
          stream: _mine,
          builder: (context, snap) {
            // Les alertes silencieuses n'apparaissent jamais sur le téléphone de l'expéditeur.
            final alerts = (snap.data?.docs ?? const [])
                .map((d) => AlertDoc(d.id, d.data()))
                .where((a) => a.source != 'silent')
                .toList()
              ..sort((a, b) => b.at.compareTo(a.at));
            final active = alerts.where((a) => a.status != 'closed').toList();
            final past = alerts.where((a) => a.status == 'closed').take(10).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront, color: gold),
                    title: Text(me.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(me.siteName.isEmpty ? t('client_space') : me.siteName),
                  ),
                ),
                // Protection aussi pendant les déplacements du client.
                TripCard(t: t, me: me),
                const SizedBox(height: 4),
                SilentSosButton(t: t, me: me),
                const SizedBox(height: 4),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield, color: gold, size: 30),
                    title: Text(t('catalog_title'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t('catalog_sub')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => ServicesCatalog(t: t, me: me))),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _send,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        backgroundColor: danger,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: danger.withValues(alpha: 0.5),
                        elevation: 6,
                      ),
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Padding(
                              padding: const EdgeInsets.all(14),
                              child: FittedBox(
                                child: Text(t('sos_btn'),
                                    style: TextStyle(
                                        fontSize: 46,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: t('sos_btn') == 'SOS' ? 3 : 0)),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(_busy ? t('locating') : t('client_sos_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted)),
                ),
                const SizedBox(height: 18),
                if (active.isNotEmpty) ...[
                  Text(t('client_active'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...active.map(_statusCard),
                  const SizedBox(height: 12),
                ],
                if (_inlandKm != null)
                  Card(
                    color: const Color(0xFFE8F5E9),
                    child: ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFF2E5E3A)),
                      title: Text(t('inland_banner', {'km': _inlandKm!.round().toString()}),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(t('inland_banner_sub')),
                    ),
                  ),
                Text(t('client_calls'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_inlandKm != null)
                  _callButton(Icons.security, t('call_gendarmerie'), 'tel:$gendarmerieNumber', const Color(0xFF2E5E3A)),
                _callButton(Icons.shield, t('call_amane'), 'tel:$controlPhone', navy),
                _callButton(Icons.local_police, t('call_police'), 'tel:$policeNumber', const Color(0xFF1F4E99)),
                _callButton(Icons.local_fire_department, t('call_civil'), 'tel:$fireNumber', danger),
                if (_inlandKm == null)
                  _callButton(Icons.security, t('call_gendarmerie'), 'tel:$gendarmerieNumber', const Color(0xFF2E5E3A)),
                emergencyButton(context, t),
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(t('client_history'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...past.map(_statusCard),
                ],
              ],
            );
          },
        ),
      );
  }

  Widget _callButton(IconData icon, String label, String url, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: color, side: BorderSide(color: color)),
            onPressed: () => openUrl(url),
            icon: Icon(icon),
            label: Text(label, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );

  Widget _statusCard(AlertDoc a) {
    final (txt, col, ic) = clientStatus(t, a);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(ic, color: col, size: 30),
        title: Text(txt, style: TextStyle(color: col, fontWeight: FontWeight.w600)),
        subtitle: Text('${t('need_${a.type}')} · ${dm(a.at)} ${hm(a.at)}'),
      ),
    );
  }
}

/// Ce que voit le client : où en est sa demande.
(String, Color, IconData) clientStatus(T t, AlertDoc a) {
  if (a.status == 'closed') return (t('cst_closed'), okGreen, Icons.check_circle);
  if (a.action.isNotEmpty) {
    return (t('act_${a.action}_client'), navy, needIcon(a.action == 'civil' ? 'fire' : a.action == 'ambulance' ? 'medical' : a.action == 'gendarmerie' ? 'police' : a.action));
  }
  if (a.status == 'taken') return (t('cst_taken'), warn, Icons.support_agent);
  return (t('cst_open'), danger, Icons.hourglass_top);
}
