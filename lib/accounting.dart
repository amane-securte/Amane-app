import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'pdf_docs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onglet « Comptabilité » : salaires et factures du mois,
/// calculés à partir des heures réellement pointées.
/// Les taux (salaire horaire, tarif facturé) sont dans `rates`, lisible
/// uniquement par l'administration.
class AccountingTab extends StatefulWidget {
  const AccountingTab(
      {super.key, required this.t, required this.users, required this.sites});
  final T t;
  final List<UserDoc> users;
  final List<Site> sites;

  @override
  State<AccountingTab> createState() => _AccountingTabState();
}

class _AccountingTabState extends State<AccountingTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Stream<QueryMap> _punches = _query();
  late final Stream<QueryMap> _rates = db.collection('rates').snapshots();

  T get t => widget.t;

  Stream<QueryMap> _query() => db
      .collection('punches')
      .where('inAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_month))
      .where('inAt',
          isLessThan: Timestamp.fromDate(DateTime(_month.year, _month.month + 1)))
      .snapshots();

  void _move(int n) => setState(() {
        _month = n == 0
            ? DateTime(DateTime.now().year, DateTime.now().month)
            : DateTime(_month.year, _month.month + n);
        _punches = _query();
      });

  static String money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String hours(double h) => h.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: _rates,
      builder: (context, rSnap) {
        final rates = <String, double>{
          for (final d in rSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            d.id: (d.data()['rate'] is num) ? (d.data()['rate'] as num).toDouble() : 0,
        };
        return StreamBuilder<QueryMap>(
          stream: _punches,
          builder: (context, pSnap) {
            final ps = (pSnap.data?.docs ?? const [])
                .map((d) => PunchDoc(d.id, d.data()))
                .where((p) => !p.open)
                .toList();
            return _body(ps, rates, pSnap.data?.docs ?? const []);
          },
        );
      },
    );
  }

  Widget _body(List<PunchDoc> ps, Map<String, double> rates,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> raw) {
    // siteId de chaque pointage (gardé dans le document brut).
    final siteOf = {for (final d in raw) d.id: d.data()['siteId'] as String? ?? ''};

    final byGuard = <String, double>{};
    final byGuardCount = <String, int>{};
    final bySite = <String, double>{};
    for (final p in ps) {
      final h = math.min(24.0, p.outAt!.difference(p.inAt).inMinutes / 60.0);
      byGuard[p.uid] = (byGuard[p.uid] ?? 0) + h;
      byGuardCount[p.uid] = (byGuardCount[p.uid] ?? 0) + 1;
      final sid = siteOf[p.id] ?? '';
      bySite[sid] = (bySite[sid] ?? 0) + h;
    }

    final userName = {for (final u in widget.users) u.id: u.name};
    final siteName = {for (final s in widget.sites) s.id: s.name};
    final nameFromPunch = {for (final p in ps) p.uid: p.name};
    final siteFromPunch = {for (final p in ps) (siteOf[p.id] ?? ''): p.siteName};

    var payTotal = 0.0, hTotal = 0.0;
    final payRows = byGuard.entries.map((e) {
      final rate = rates['g_${e.key}'] ?? 0;
      final amt = e.value * rate;
      payTotal += amt;
      hTotal += e.value;
      return (e.key, userName[e.key] ?? nameFromPunch[e.key] ?? '—', e.value,
          byGuardCount[e.key] ?? 0, rate, amt);
    }).toList()
      ..sort((a, b) => b.$6.compareTo(a.$6));

    var invTotal = 0.0;
    final invRows = bySite.entries.map((e) {
      final rate = rates['s_${e.key}'] ?? 0;
      final amt = e.value * rate;
      invTotal += amt;
      return (e.key, siteName[e.key] ?? siteFromPunch[e.key] ?? '—', e.value, rate, amt);
    }).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final margin = invTotal - payTotal;
    final monthKey = '${_month.year}${two(_month.month)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: TextButton(
                onPressed: () => _move(0),
                child: Text('${two(_month.month)}/${_month.year}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        // Synthèse
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _kv(t('total_invoiced'), '${money(invTotal)} MRU'),
                _kv(t('total_salaries'), '${money(payTotal)} MRU'),
                const Divider(),
                _kv(t('margin'), '${money(margin)} MRU',
                    color: margin < 0 ? danger : okGreen, bold: true),
                _kv(t('hours_worked'), hours(hTotal)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(t('salaries'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text(t('tap_row'), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        if (payRows.isEmpty) Text(t('no_hours'), style: const TextStyle(color: muted)),
        ...payRows.map((r) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(r.$2),
                subtitle: Text(t('pay_line', {
                  'h': hours(r.$3),
                  'n': '${r.$4}',
                  'r': money(r.$5),
                })),
                trailing: Text('${money(r.$6)} MRU',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _rowActions(
                  pdf: () => printPayslip(
                    name: r.$2,
                    phone: widget.users.where((u) => u.id == r.$1).firstOrNull?.phone ?? '',
                    month: '${two(_month.month)}/${_month.year}',
                    hours: r.$3,
                    shifts: r.$4,
                    rate: r.$5,
                  ),
                  rate: () => _editRate('g_${r.$1}', r.$2, r.$5, t('hourly_pay')),
                  pdfLabel: t('pdf_payslip'),
                ),
              ),
            )),
        const SizedBox(height: 18),
        Text(t('invoices'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text(t('tap_row'), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        if (invRows.isEmpty) Text(t('no_hours'), style: const TextStyle(color: muted)),
        ...invRows.map((r) {
          final no = 'AMN-$monthKey-${r.$1.length >= 4 ? r.$1.substring(0, 4).toUpperCase() : r.$1}';
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(r.$2),
              subtitle: Text('$no · ${t('inv_line', {'h': hours(r.$3), 'r': money(r.$4)})}'),
              trailing: Text('${money(r.$5)} MRU',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => _rowActions(
                pdf: () => printInvoice(
                  number: no,
                  siteName: r.$2,
                  client: widget.sites.where((s) => s.id == r.$1).firstOrNull?.client ?? '',
                  month: '${two(_month.month)}/${_month.year}',
                  hours: r.$3,
                  rate: r.$4,
                ),
                rate: () => _editRate('s_${r.$1}', r.$2, r.$4, t('billing_rate')),
                pdfLabel: t('pdf_invoice'),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        Text(t('acc_note'), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 12),
        // Taux des sites / agents sans heures ce mois-ci
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('all_rates')),
          children: [
            for (final u in widget.users.where((u) => u.role == 'guard'))
              ListTile(
                dense: true,
                leading: const Icon(Icons.badge, size: 18),
                title: Text(u.name),
                trailing: Text('${money(rates['g_${u.id}'] ?? 0)} MRU/h'),
                onTap: () => _editRate('g_${u.id}', u.name, rates['g_${u.id}'] ?? 0, t('hourly_pay')),
              ),
            for (final s in widget.sites)
              ListTile(
                dense: true,
                leading: const Icon(Icons.location_on, size: 18),
                title: Text(s.name),
                trailing: Text('${money(rates['s_${s.id}'] ?? 0)} MRU/h'),
                onTap: () => _editRate('s_${s.id}', s.name, rates['s_${s.id}'] ?? 0, t('billing_rate')),
              ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            ltrText(v,
                style: TextStyle(
                    color: color,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    fontSize: bold ? 17 : 15)),
          ],
        ),
      );

  Future<void> _rowActions({
    required Future<void> Function() pdf,
    required Future<void> Function() rate,
    required String pdfLabel,
  }) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: danger),
              title: Text(pdfLabel),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(t('edit_rate')),
              onTap: () => Navigator.pop(ctx, 'rate'),
            ),
          ],
        ),
      ),
    );
    if (v == 'pdf') {
      try {
        await pdf();
      } catch (e) {
        if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
      }
    } else if (v == 'rate') {
      await rate();
    }
  }

  Future<void> _editRate(String key, String who, double cur, String label) async {
    final c = TextEditingController(text: cur == 0 ? '' : cur.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(who),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '$label (MRU/h)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.').trim())),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (v == null || v < 0) return;
    await db.collection('rates').doc(key).set({'rate': v});
    if (mounted) snack(context, t('saved'), color: okGreen);
  }
}
