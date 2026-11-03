import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'logbook.dart';
import 'pdf_docs.dart';
import 'planning.dart';
import 'theme.dart';
import 'widgets.dart';

/// Message affiché quand le client n'a pas encore de site attribué.
Widget _noSite(T t) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t('client_no_site'),
            textAlign: TextAlign.center, style: const TextStyle(color: muted)),
      ),
    );

/// Erreur de lecture : le plus souvent, règles Firestore pas encore mises à jour.
Widget _readError(T t) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(t('rules_needed'),
          textAlign: TextAlign.center, style: const TextStyle(color: danger)),
    );

/// « Mon site » : agents en service, missions du jour, main courante (7 jours).
class ClientSiteTab extends StatefulWidget {
  const ClientSiteTab({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;

  @override
  State<ClientSiteTab> createState() => _ClientSiteTabState();
}

class _ClientSiteTabState extends State<ClientSiteTab> {
  Stream<QueryMap>? _punches, _logs, _shifts;

  @override
  void initState() {
    super.initState();
    final sid = widget.me.siteId;
    if (sid != null) {
      // Filtrés sur le site du client : les règles de sécurité l'exigent.
      _punches = db.collection('punches').where('siteId', isEqualTo: sid).snapshots();
      _logs = db.collection('logs').where('siteId', isEqualTo: sid).snapshots();
      _shifts = db.collection('shifts').where('siteId', isEqualTo: sid).snapshots();
    }
  }

  T get t => widget.t;

  @override
  Widget build(BuildContext context) {
    if (_punches == null) return _noSite(t);
    final now = DateTime.now();
    final today = ymd(now);
    return StreamBuilder<QueryMap>(
      stream: _punches,
      builder: (context, pSnap) {
        if (pSnap.hasError) return _readError(t);
        final onDuty = (pSnap.data?.docs ?? const [])
            .map((d) => PunchDoc(d.id, d.data()))
            .where((p) => p.open)
            .toList()
          ..sort((a, b) => a.inAt.compareTo(b.inAt));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.me.siteName,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            _h(t('client_on_duty', {'n': '${onDuty.length}'}),
                color: onDuty.isEmpty ? warn : okGreen),
            if (onDuty.isEmpty)
              _empty(t('client_nobody'))
            else
              ...onDuty.map((p) {
                final (txt, col) = locInfo(t, p.inFix, p.inDist, p.inOk);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.shield, color: okGreen),
                    title: Text(p.name),
                    subtitle: Text(t('status_on', {'t': hm(p.inAt)})),
                    trailing: pill(txt, col),
                  ),
                );
              }),
            const SizedBox(height: 18),
            _h(t('client_today_shifts')),
            StreamBuilder<QueryMap>(
              stream: _shifts,
              builder: (context, sSnap) {
                final list = (sSnap.data?.docs ?? const [])
                    .map((d) => ShiftDoc(d.id, d.data()))
                    .where((s) => s.date == today)
                    .toList()
                  ..sort((a, b) => a.start.compareTo(b.start));
                if (list.isEmpty) return _empty(t('no_shift'));
                return Column(
                  children: list
                      .map((s) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: ltrText('${s.start}–${s.end}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              title: Text(s.name),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            _h(t('client_logs')),
            StreamBuilder<QueryMap>(
              stream: _logs,
              builder: (context, lSnap) {
                final week = now.subtract(const Duration(days: 7));
                final logs = (lSnap.data?.docs ?? const [])
                    .map((d) => LogDoc(d.id, d.data()))
                    .where((l) => l.at.isAfter(week))
                    .toList()
                  ..sort((a, b) => b.at.compareTo(a.at));
                if (logs.isEmpty) return _empty(t('no_logs'));
                return Column(children: logs.map((l) => LogTile(t: t, l: l)).toList());
              },
            ),
          ],
        );
      },
    );
  }

  Widget _h(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(color: muted)),
      );
}

/// « Mes factures » : factures envoyées par AMANE, téléchargeables en PDF.
class ClientInvoicesTab extends StatefulWidget {
  const ClientInvoicesTab({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;

  @override
  State<ClientInvoicesTab> createState() => _ClientInvoicesTabState();
}

class _ClientInvoicesTabState extends State<ClientInvoicesTab> {
  Stream<QueryMap>? _inv;

  @override
  void initState() {
    super.initState();
    final sid = widget.me.siteId;
    if (sid != null) {
      _inv = db.collection('invoices').where('siteId', isEqualTo: sid).snapshots();
    }
  }

  T get t => widget.t;

  static String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b MRU';
  }

  @override
  Widget build(BuildContext context) {
    if (_inv == null) return _noSite(t);
    return StreamBuilder<QueryMap>(
      stream: _inv,
      builder: (context, snap) {
        if (snap.hasError) return _readError(t);
        final docs = (snap.data?.docs ?? const []).toList()
          ..sort((a, b) {
            final ta = a.data()['sentAt'], tb = b.data()['sentAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t('client_no_invoices'),
                  textAlign: TextAlign.center, style: const TextStyle(color: muted)),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final d in docs)
              Builder(builder: (context) {
                final m = d.data();
                final number = '${m['number'] ?? d.id}';
                final month = '${m['month'] ?? ''}';
                final hours = (m['hours'] is num) ? (m['hours'] as num).toDouble() : 0.0;
                final rate = (m['rate'] is num) ? (m['rate'] as num).toDouble() : 0.0;
                final amount = (m['amount'] is num) ? (m['amount'] as num).toDouble() : hours * rate;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, color: navy),
                    title: Text('$month · $number'),
                    subtitle: Text(t('inv_line', {
                      'h': hours.toStringAsFixed(1),
                      'r': _money(rate).replaceAll(' MRU', ''),
                    })),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(amount),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Icon(Icons.picture_as_pdf, color: danger, size: 18),
                      ],
                    ),
                    onTap: () async {
                      try {
                        await printInvoice(
                          number: number,
                          siteName: '${m['siteName'] ?? widget.me.siteName}',
                          client: '${m['client'] ?? ''}',
                          month: month,
                          hours: hours,
                          rate: rate,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          snack(context, t('err_generic', {'e': '$e'}), color: danger);
                        }
                      }
                    },
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
