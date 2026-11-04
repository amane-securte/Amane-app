import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'data.dart';
import 'i18n.dart';
import 'logbook.dart';
import 'pdf_docs.dart';

const _typesFr = {
  'assault': 'Agression',
  'intrusion': 'Intrusion',
  'fire': 'Incendie',
  'medical': 'Urgence médicale',
  'other': 'Autre',
  'patrol': 'Demande de patrouille',
  'police': 'Vol / agression',
  'request': 'Demande de service',
};

String _d(DateTime d) => '${two(d.day)}/${two(d.month)} ${hm(d)}';

/// Rassemble les données du mois et produit le rapport PDF.
/// - Administration : [siteId] nul = toute la société, sinon un seul site.
/// - Client : [siteId] obligatoire, [clientUid] pour ses propres alertes.
Future<void> monthlyReport({
  required DateTime month,
  required String scope,
  String? siteId,
  String? clientUid,
}) async {
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  bool inMonth(DateTime d) => !d.isBefore(from) && d.isBefore(to);

  // Requêtes simples (sans index composé) puis filtrage sur le téléphone.
  final QueryMap pSnap, lSnap, aSnap;
  if (siteId == null) {
    pSnap = await db.collection('punches')
        .where('inAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('inAt', isLessThan: Timestamp.fromDate(to)).get();
    lSnap = await db.collection('logs')
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('at', isLessThan: Timestamp.fromDate(to)).get();
    aSnap = await db.collection('alerts')
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('at', isLessThan: Timestamp.fromDate(to)).get();
  } else {
    pSnap = await db.collection('punches').where('siteId', isEqualTo: siteId).get();
    lSnap = await db.collection('logs').where('siteId', isEqualTo: siteId).get();
    aSnap = clientUid != null
        ? await db.collection('alerts').where('uid', isEqualTo: clientUid).get()
        : await db.collection('alerts')
            .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
            .where('at', isLessThan: Timestamp.fromDate(to)).get();
  }

  final punches = pSnap.docs
      .map((d) => (d.data()['siteId'] as String? ?? '', PunchDoc(d.id, d.data())))
      .where((e) => inMonth(e.$2.inAt) && !e.$2.open)
      .toList();
  final logs = lSnap.docs
      .map((d) => LogDoc(d.id, d.data()))
      .where((l) => inMonth(l.at))
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final alerts = aSnap.docs
      .map((d) => AlertDoc(d.id, d.data()))
      .where((a) => inMonth(a.at) && (siteId == null || clientUid != null || a.siteName == scope))
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));

  final site = <String, (String, int, double, int)>{};
  final agent = <String, (String, int, double, int)>{};
  var hours = 0.0;
  var off = 0;
  for (final (sid, p) in punches) {
    final h = math.min(24.0, p.outAt!.difference(p.inAt).inMinutes / 60.0);
    final o = p.offSite ? 1 : 0;
    hours += h;
    off += o;
    final s0 = site[sid] ?? (p.siteName.isEmpty ? '—' : p.siteName, 0, 0.0, 0);
    site[sid] = (s0.$1, s0.$2 + 1, s0.$3 + h, s0.$4 + o);
    final a0 = agent[p.uid] ?? (p.name, 0, 0.0, 0);
    agent[p.uid] = (a0.$1, a0.$2 + 1, a0.$3 + h, a0.$4 + o);
  }
  int byHours((String, int, double, int) a, (String, int, double, int) b) => b.$3.compareTo(a.$3);

  await printActivityReport(
    month: '${two(month.month)}/${month.year}',
    scope: scope,
    hours: hours,
    missions: punches.length,
    offSite: off,
    bySite: site.values.toList()..sort(byHours),
    byAgent: agent.values.toList()..sort(byHours),
    incidents: [
      for (final l in logs.where((l) => l.category == 'incident'))
        (_d(l.at), l.siteName, '${l.name} : ${l.text}${l.photos.isEmpty ? '' : ' [${l.photos.length} photo(s)]'}'),
    ],
    alerts: [
      for (final a in alerts)
        (_d(a.at), a.siteName, '${_typesFr[a.type] ?? a.type}${a.fromClient ? ' (client)' : ''} – ${a.name}'),
    ],
    logCount: logs.length,
  );
}
