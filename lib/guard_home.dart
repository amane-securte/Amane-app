import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'client_home.dart' show needIcon;
import 'data.dart';
import 'geo.dart';
import 'emergency.dart';
import 'i18n.dart';
import 'instructions.dart';
import 'logbook.dart';
import 'payslips.dart';
import 'supervisor.dart';
import 'silent.dart';
import 'planning.dart';
import 'tracking.dart';
import 'theme.dart';
import 'widgets.dart';

/// Écran de l'agent : pointage GPS, SOS, historique.
class GuardHome extends StatefulWidget {
  const GuardHome(
      {super.key, required this.prefs, required this.me, this.embedded = false});
  final Prefs prefs;
  final UserDoc me;

  /// Vrai quand l'écran est affiché dans un onglet de l'administrateur.
  final bool embedded;

  @override
  State<GuardHome> createState() => _GuardHomeState();
}

class _GuardHomeState extends State<GuardHome> {
  bool _busy = false;
  late Stream<QueryMap> _punches;
  late Stream<DocumentSnapshotMap?> _site;
  late final Stream<QueryMap> _shifts =
      db.collection('shifts').where('uid', isEqualTo: me.id).snapshots();

  T get t => T(widget.prefs.lang);
  UserDoc get me => widget.me;

  @override
  void initState() {
    super.initState();
    // Filtré sur l'agent : les règles de sécurité l'exigent.
    _punches =
        db.collection('punches').where('uid', isEqualTo: me.id).snapshots();
    _site = _siteStream();
  }

  Stream<DocumentSnapshotMap?> _siteStream() {
    final id = me.siteId;
    if (id == null) return Stream.value(null);
    return db.collection('sites').doc(id).snapshots();
  }

  @override
  void didUpdateWidget(GuardHome old) {
    super.didUpdateWidget(old);
    if (old.me.siteId != me.siteId) _site = _siteStream();
  }

  Future<GeoResult> _locate({int seconds = 15}) async {
    setState(() => _busy = true);
    final r = await getFix(seconds: seconds);
    if (mounted) setState(() => _busy = false);
    return r;
  }

  /// Le suivi suit l'état du pointage : actif pendant la mission seulement.
  void _syncTracking(PunchDoc? open) {
    final tr = ShiftTracker.instance;
    if (open != null) {
      tr.start(open.id, title: t('track_title'), text: t('track_text'), mobile: mobileJobs.contains(me.job));
    } else if (tr.running) {
      tr.stop();
    }
  }

  Future<void> _punch(PunchDoc? open, Site? site) async {
    // ignore: parameter_assignments
    final r = await _locate();
    if (!mounted) return;
    // Départ : contrôle sur le site du pointage d'arrivée (site détecté
    // automatiquement), pas forcément sur le site habituel.
    final sid = open?.siteId;
    if (open != null && sid != null && sid != site?.id) {
      try {
        final d = await db.collection('sites').doc(sid).get();
        final m = d.data();
        if (m != null) site = Site(d.id, m);
      } catch (_) {}
      if (!mounted) return;
    }
    var (dist, ok) = checkSite(r.fix, site);
    // Prise de service hors de son site habituel (ou sans site attribué) :
    // on cherche automatiquement le site AMANE où se trouve l'agent.
    var auto = false;
    if (open == null && r.fix != null && ok != true) {
      try {
        final all = await db.collection('sites').get();
        for (final d in all.docs) {
          final s = Site(d.id, d.data());
          final (dd, okk) = checkSite(r.fix, s);
          if (okk == true && dd != null && (!auto || dd < dist!)) {
            site = s;
            dist = dd;
            ok = true;
            auto = true;
          }
        }
      } catch (_) {}
      if (!mounted) return;
    }
    // Agents itinérants (mobiles, superviseurs, gardes du corps, chauffeurs) :
    // hors d'un site AMANE, on n'enregistre pas d'anomalie « hors site ».
    if (!auto && ok == false && mobileJobs.contains(me.job)) {
      ok = null;
      dist = null;
    }
    final p = open == null ? 'in' : 'out';
    final data = <String, dynamic>{
      '${p}At': Timestamp.now(),
      if (r.fix != null) ...r.fix!.write(p),
      if (dist != null) '${p}Dist': dist.round(),
      if (ok != null) '${p}Ok': ok,
    };
    // Écriture sans attendre : Firestore la garde si le réseau est coupé.
    if (open == null) {
      db.collection('punches').add({
        'uid': me.id,
        'name': me.name,
        'phone': me.phone,
        'siteId': site?.id,
        'siteName': site?.name ?? '',
        if (me.job.isNotEmpty) 'job': me.job,
        if (auto) 'autoSite': true,
        ...data,
      });
    } else {
      db.collection('punches').doc(open.id).update(data);
    }
    if (r.error != null) {
      showGpsError(context, t, r.error!);
    } else {
      final (txt, col) = locInfo(t, r.fix, dist, ok);
      snack(
          context,
          '${t(open == null ? 'saved_in' : 'saved_out')} · '
          '${auto ? '${t('auto_site')} ${site?.name} · ' : ''}$txt',
          color: col);
    }
  }

  Future<void> _sos(Site? site) async {
    const types = ['assault', 'intrusion', 'fire', 'medical', 'accident', 'breakdown', 'other'];
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('sos_title'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final ty in types)
              ListTile(
                leading: Icon(needIcon(ty), color: ty == 'breakdown' ? warn : danger),
                title: Text(t('ty_$ty'), style: const TextStyle(fontSize: 17)),
                onTap: () => Navigator.pop(ctx, ty),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;

    // En urgence, on n'attend pas le GPS plus de 10 secondes.
    final r = await _locate(seconds: 10);
    if (!mounted) return;
    final f = r.fix;
    final now = DateTime.now();

    // 1) Alerte enregistrée sur le serveur (visible aussitôt par l'administration).
    var online = true;
    final write = db.collection('alerts').add({
      'uid': me.id,
      'name': me.name,
      'phone': me.phone,
      'siteName': site?.name ?? '',
      'type': type,
      'status': 'open',
      'at': Timestamp.fromDate(now),
      if (f != null) ...f.write(''),
      if (f == null && r.error != null) 'gpsErr': r.error!.name,
    });
    if (f == null) write.then(completeAlertFix).ignore();
    try {
      await write.timeout(const Duration(seconds: 6));
    } catch (_) {
      online = false; // restera en file d'attente jusqu'au retour du réseau
    }
    if (!mounted) return;

    // 2) SMS de secours vers la salle de contrôle.
    final text = t('sms_text', {
      'type': t('ty_$type'),
      'site': site?.name ?? '',
      'name': me.name,
      'pos': f == null ? '' : ' - ${f.mapUrl}',
      'time': hm(now),
    });
    await openUrl('sms:$controlPhone?body=${Uri.encodeComponent(text)}');
    if (!mounted) return;
    snack(context, t(online ? 'sos_sent' : 'sos_queued'),
        color: online ? navy : danger);
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
        child: StreamBuilder<DocumentSnapshotMap?>(
          stream: _site,
          builder: (context, siteSnap) {
            final sd = siteSnap.data;
            final site = (sd != null && sd.exists)
                ? Site(sd.id, sd.data() ?? const {})
                : null;
            return StreamBuilder<QueryMap>(
              stream: _punches,
              builder: (context, snap) {
                final all = (snap.data?.docs ?? const [])
                    .map((d) => PunchDoc(d.id, d.data()))
                    .toList()
                  ..sort((a, b) => b.inAt.compareTo(a.inAt));
                final open = all.where((p) => p.open).firstOrNull;
                final done = all.where((p) => !p.open).take(15).toList();
                _syncTracking(open);
                return _body(site, open, done);
              },
            );
          },
        ),
      );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: amaneAppBar(context, widget.prefs),
      body: content,
    );
  }

  Widget _body(Site? site, PunchDoc? open, List<PunchDoc> done) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (me.job == 'supervisor') ...[
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => SupervisorScreen(t: t))),
            icon: const Icon(Icons.supervisor_account),
            label: Text(t('sup_title')),
          ),
          const SizedBox(height: 12),
        ],
        _statusCard(site, open),
        const SizedBox(height: 14),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _punch(open, site),
            icon: Icon(open == null ? Icons.login : Icons.logout),
            label: Text(open == null ? t('btn_in') : t('btn_out'),
                style: const TextStyle(fontSize: 18)),
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(t('locating')),
              ],
            ),
          ),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 170,
            height: 170,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _sos(site),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: danger.withValues(alpha: 0.5),
                elevation: 6,
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: FittedBox(
                  child: Text(t('sos_btn'),
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: t('sos_btn') == 'SOS' ? 3 : 0)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
            child: Text(t('sos_hint'), style: const TextStyle(color: muted))),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => openUrl('tel:$controlPhone'),
            icon: const Icon(Icons.phone),
            label: Text(t('call_control')),
          ),
        ),
        const SizedBox(height: 8),
        SilentSosButton(t: t, me: me),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => MyPayslipsScreen(t: t, me: me))),
            icon: const Icon(Icons.receipt_long),
            label: Text(t('my_payslips')),
          ),
        ),
        const SizedBox(height: 12),
        // Les trois numéros les plus importants, en un geste.
        Row(
          children: [
            _quickCall(Icons.local_police, '117', t('quick_police'), const Color(0xFF1F4E99)),
            const SizedBox(width: 8),
            _quickCall(Icons.local_fire_department, '118', t('quick_fire'), danger),
            const SizedBox(width: 8),
            _quickCall(Icons.security, '116', t('quick_gendarmerie'), const Color(0xFF2E5E3A)),
          ],
        ),
        const SizedBox(height: 8),
        Center(child: emergencyButton(context, t)),
        const SizedBox(height: 20),
        GuardInstructions(t: t, siteId: site?.id ?? me.siteId),
        const SizedBox(height: 8),
        MyShifts(t: t, stream: _shifts),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LogbookScreen(t: t, me: me, siteName: site?.name ?? ''),
            ),
          ),
          icon: const Icon(Icons.menu_book),
          label: Text(t('open_logbook')),
        ),
        const SizedBox(height: 28),
        Text(t('history'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (done.isEmpty)
          Text(t('empty_history'), style: const TextStyle(color: muted))
        else
          ...done.map((p) => PunchTile(t: t, p: p, showName: false)),
      ],
    );
  }

  Widget _quickCall(IconData icon, String number, String label, Color color) =>
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: () => openUrl('tel:$number'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              Text(number,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _statusCard(Site? site, PunchDoc? open) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(me.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            Text(site?.name ?? t(mobileJobs.contains(me.job) ? 'mobile_mission' : 'no_site_assigned'),
                style: TextStyle(color: site == null && !mobileJobs.contains(me.job) ? warn : muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(open != null ? Icons.shield : Icons.shield_outlined,
                    color: open != null ? okGreen : muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    open != null
                        ? t('status_on', {'t': hm(open.inAt)})
                        : t('status_off'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: open != null ? okGreen : ink),
                  ),
                ),
              ],
            ),
            if (open != null) ...[
              const SizedBox(height: 6),
              Builder(builder: (_) {
                final (txt, col) =
                    locInfo(t, open.inFix, open.inDist, open.inOk);
                return pill('📍 $txt', col);
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ligne d'une mission : date, heures, durée, contrôle GPS.
class PunchTile extends StatelessWidget {
  const PunchTile(
      {super.key, required this.t, required this.p, this.showName = true});
  final T t;
  final PunchDoc p;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final out = p.outAt;
    final (inTxt, inCol) = locInfo(t, p.inFix, p.inDist, p.inOk);
    final (outTxt, outCol) = locInfo(t, p.outFix, p.outDist, p.outOk);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName)
              whoWhere(p.name, p.siteName),
            Row(
              children: [
                Text(dm(p.inAt),
                    style: TextStyle(
                        fontWeight:
                            showName ? FontWeight.normal : FontWeight.w600)),
                const SizedBox(width: 10),
                ltrText('${hm(p.inAt)} → ${out == null ? '…' : hm(out)}'),
                const Spacer(),
                Text(durText(t, (out ?? DateTime.now()).difference(p.inAt)),
                    style: const TextStyle(color: muted)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                InkWell(
                  onTap: p.inFix == null ? null : () => openUrl(p.inFix!.mapUrl),
                  child: pill('${t('arrival')}: $inTxt', inCol),
                ),
                if (out != null)
                  InkWell(
                    onTap: p.outFix == null
                        ? null
                        : () => openUrl(p.outFix!.mapUrl),
                    child: pill('${t('departure')}: $outTxt', outCol),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
