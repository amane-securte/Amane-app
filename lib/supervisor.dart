import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'geo.dart';
import 'guard_home.dart';
import 'i18n.dart';
import 'logbook.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tableau du superviseur : sites et agents en service, main courante de tous
/// les sites et alertes SOS (origine, position). Lecture seule, sans paie,
/// tarifs, factures ni messages clients (réservés au Directeur).
class SupervisorScreen extends StatelessWidget {
  const SupervisorScreen({super.key, required this.t});
  final T t;

  static DateTime get _since => DateTime.now().subtract(const Duration(hours: 24));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('sup_title')),
          bottom: TabBar(tabs: [
            Tab(icon: const Icon(Icons.warning_amber_rounded), text: t('sup_tab_sos')),
            Tab(icon: const Icon(Icons.location_city), text: t('sup_tab_sites')),
            Tab(icon: const Icon(Icons.menu_book), text: t('sup_tab_logs')),
          ]),
        ),
        body: TabBarView(children: [_sos(), _sites(), _logs()]),
      ),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('rules_needed'), textAlign: TextAlign.center, style: const TextStyle(color: danger)),
        ),
      );

  Widget _empty(String s) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(s, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
      );

  Widget _sos() => StreamBuilder<QueryMap>(
        stream: db.collection('alerts').where('status', whereIn: ['open', 'taken']).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _err();
          final list = (snap.data?.docs ?? const []).map((d) => AlertDoc(d.id, d.data())).toList()
            ..sort((a, b) => b.at.compareTo(a.at));
          if (list.isEmpty) return _empty(t('no_alerts'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final a in list) _alert(a)],
          );
        },
      );

  Widget _alert(AlertDoc a) {
    final open = a.status == 'open';
    final f = a.fix;
    return Card(
      color: open ? const Color(0xFFFBE9E7) : paper,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t(a.fromClient ? 'need_${a.type}' : 'ty_${a.type}'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            pill(t(open ? 'st_open' : 'st_taken'), open ? danger : warn),
          ]),
          const SizedBox(height: 6),
          // Origine de l'alerte : qui, d'où, quand.
          whoWhere(a.name, a.siteName, client: a.fromClient),
          if (isInland(a.fix))
            Text(t('inland_pill', {'km': kmFromNouakchott(a.fix)!.round().toString()}),
                style: const TextStyle(color: Color(0xFF2E5E3A))),
          ltrText('${dm(a.at)} ${hm(a.at)}', style: const TextStyle(color: muted)),
          if (a.note.isNotEmpty)
            Text('« ${a.note} »', style: const TextStyle(fontStyle: FontStyle.italic)),
          if (a.action.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: pill(t('act_${a.action}'), okGreen)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (f != null)
              OutlinedButton.icon(
                onPressed: () => openUrl(f.mapUrl),
                icon: const Icon(Icons.map, size: 18),
                label: Text('${t('map')} (±${f.acc.round()} m)'),
              ),
            if (a.phone.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => openUrl('tel:${a.phone}'),
                icon: const Icon(Icons.phone, size: 18),
                label: Text(t('call')),
              ),
            OutlinedButton.icon(
              onPressed: () => openUrl('tel:$controlPhone'),
              icon: const Icon(Icons.support_agent, size: 18),
              label: Text(t('call_control')),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _sites() => StreamBuilder<QueryMap>(
        stream: db.collection('sites').snapshots(),
        builder: (context, sSnap) {
          if (sSnap.hasError) return _err();
          return StreamBuilder<QueryMap>(
            stream: db
                .collection('punches')
                .where('inAt', isGreaterThan: Timestamp.fromDate(_since))
                .snapshots(),
            builder: (context, pSnap) {
              if (pSnap.hasError) return _err();
              final sites = (sSnap.data?.docs ?? const []).map((d) => Site(d.id, d.data())).toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final onDuty = (pSnap.data?.docs ?? const [])
                  .map((d) => PunchDoc(d.id, d.data()))
                  .where((p) => p.open)
                  .toList();
              final bySite = <String, List<PunchDoc>>{};
              for (final p in onDuty) {
                bySite.putIfAbsent(p.siteName, () => []).add(p);
              }
              final known = sites.map((s) => s.name).toSet();
              final elsewhere = onDuty.where((p) => !known.contains(p.siteName)).toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(t('on_duty_now', {'n': '${onDuty.length}'}),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final s in sites)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        leading: Icon(Icons.location_on,
                            color: (bySite[s.name]?.isNotEmpty ?? false) ? okGreen : muted),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(t('sup_site_line', {'n': '${bySite[s.name]?.length ?? 0}'})),
                        children: [
                          if (s.fix != null)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.directions),
                              title: Text(t('directions')),
                              onTap: () => openUrl(s.fix!.mapUrl),
                            ),
                          if (bySite[s.name]?.isEmpty ?? true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(t('none_on_duty'), style: const TextStyle(color: muted)),
                            ),
                          for (final p in bySite[s.name] ?? const <PunchDoc>[])
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: PunchTile(t: t, p: p),
                            ),
                        ],
                      ),
                    ),
                  if (elsewhere.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(t('sup_elsewhere'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final p in elsewhere) PunchTile(t: t, p: p),
                  ],
                ],
              );
            },
          );
        },
      );

  Widget _logs() => StreamBuilder<QueryMap>(
        stream: db.collection('logs').where('at', isGreaterThan: Timestamp.fromDate(_since)).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _err();
          final logs = (snap.data?.docs ?? const []).map((d) => LogDoc(d.id, d.data())).toList()
            ..sort((a, b) => b.at.compareTo(a.at));
          if (logs.isEmpty) return _empty(t('no_logs'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t('logs_24h'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final l in logs) LogTile(t: t, l: l),
            ],
          );
        },
      );
}
