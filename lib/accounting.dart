import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'expenses.dart';
import 'export.dart';
import 'guard_home.dart';
import 'people.dart';
import 'services.dart';
import 'i18n.dart';
import 'pdf_docs.dart';
import 'payslips.dart';
import 'report.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onglet « Comptabilité » : salaires et factures du mois,
/// calculés à partir des heures réellement pointées.
/// Les taux (salaire horaire, tarif facturé) sont dans `rates`, lisible
/// uniquement par l'administration.
class AccountingTab extends StatefulWidget {
  const AccountingTab(
      {super.key, required this.t, required this.users, required this.sites, this.director = true});
  final T t;
  /// false : comptable (salaires seulement, sans changer les postes).
  final bool director;
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
            final adjs = (rSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => d.data()['adj'] == true)
                .map((d) => Adj(d.id, d.data()))
                .where((a) => a.month == _monthKey)
                .toList();
            final exps = (rSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => d.data()['exp'] == true)
                .map((d) => Expense(d.id, d.data()))
                .where((e) => e.month == _monthKey)
                .toList();
            return _body(ps, rates, pSnap.data?.docs ?? const [], adjs, exps);
          },
        );
      },
    );
  }

  String? _job(String uid) => widget.users.where((u) => u.id == uid).firstOrNull?.job;

  String get _monthKey => '${_month.year}-${two(_month.month)}';

  Widget _body(List<PunchDoc> ps, Map<String, double> rates,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> raw, List<Adj> adjs,
      List<Expense> exps) {
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

    // Agents avec des heures ou des éléments de paie ce mois-ci.
    final adjByGuard = <String, List<Adj>>{};
    for (final a in adjs) {
      (adjByGuard[a.uid] ??= []).add(a);
    }
    // Salariés au mois (direction, comptables, chauffeurs…).
    final monthlyUids = {
      for (final u in widget.users)
        if ((rates['m_${u.id}'] ?? 0) > 0 && u.role != 'client' && u.role != 'disabled') u.id,
    };
    // Le compte du DG lui-même n'est pas dans widget.users : on l'ajoute s'il a un salaire.
    for (final k in rates.keys) {
      if (k.startsWith('m_') && (rates[k] ?? 0) > 0) monthlyUids.add(k.substring(2));
    }
    final payUids = {...byGuard.keys, ...adjByGuard.keys, ...monthlyUids};
    var payTotal = 0.0, hTotal = 0.0, netTotal = 0.0, cnssEmpTotal = 0.0, cnssCoTotal = 0.0;
    final payRows = payUids.map((uid) {
      final h = byGuard[uid] ?? 0;
      final rate = rates['g_$uid'] ?? 0;
      final monthly = rates['m_$uid'] ?? 0;
      final gross = h * rate + monthly;
      final list = adjByGuard[uid] ?? const <Adj>[];
      // Base CNSS : brut + primes − absences (avances et retenues exclues).
      final taxable = gross +
          list.where((a) => a.kind == 'bonus' || a.kind == 'absence').fold<double>(0, (s, a) => s + a.signed);
      final (cnssEmp, cnssCo) = cnssFor(taxable);
      cnssEmpTotal += cnssEmp;
      cnssCoTotal += cnssCo;
      final net = gross + list.fold<double>(0, (s, a) => s + a.signed) - cnssEmp;
      // Coût pour la société : l'avance n'est qu'un paiement anticipé.
      final cost = gross +
          list.where((a) => a.kind != 'advance').fold<double>(0, (s, a) => s + a.signed);
      payTotal += cost;
      netTotal += net;
      hTotal += h;
      final name = userName[uid] ??
          nameFromPunch[uid] ??
          (list.isNotEmpty ? list.first.name : '—');
      return (uid, name, h, byGuardCount[uid] ?? 0, rate, gross, list, net, monthly, cnssEmp, cnssCo);
    }).toList()
      ..sort((a, b) => b.$8.compareTo(a.$8));

    var invTotal = 0.0;
    final invRows = bySite.entries.map((e) {
      final rate = rates['s_${e.key}'] ?? 0;
      final amt = e.value * rate;
      invTotal += amt;
      return (e.key, siteName[e.key] ?? siteFromPunch[e.key] ?? '—', e.value, rate, amt);
    }).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    final expTotal = exps.fold<double>(0, (s, e) => s + e.amount);
    final margin = invTotal - payTotal - cnssCoTotal - expTotal;
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
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.table_view, color: okGreen),
              label: Text(t('export_xlsx')),
              onPressed: () async {
                try {
                  await exportMonthXlsx(
                    month: _month,
                    punches: ps,
                    pay: [
                      for (final r in payRows)
                        (
                          r.$2,
                          jobsFr[_job(r.$1) ?? ''] ?? '',
                          r.$3,
                          r.$4,
                          r.$5,
                          r.$9,
                          r.$6,
                          r.$7.fold<double>(0, (s, a) => s + a.signed),
                          r.$10,
                          r.$8,
                          r.$11,
                        ),
                    ],
                    expenses: exps,
                    invoices: [
                      for (final r in invRows)
                        (
                          r.$2,
                          widget.sites.where((s) => s.id == r.$1).firstOrNull?.client ?? '',
                          r.$3,
                          r.$4,
                          r.$5,
                        ),
                    ],
                  );
                } catch (e) {
                  if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.groups, color: navy),
              label: Text(t('payroll_register')),
              onPressed: payRows.isEmpty
                  ? null
                  : () async {
                      try {
                        await printPayrollRegister(
                          month: '${two(_month.month)}/${_month.year}',
                          rows: [
                            for (final r in payRows)
                              (
                                r.$2,
                                jobsFr[_job(r.$1) ?? ''] ?? '',
                                r.$3,
                                r.$9,
                                r.$6,
                                r.$7.fold<double>(0, (s, a) => s + a.signed),
                                r.$10,
                                r.$8,
                                r.$11,
                              ),
                          ],
                        );
                      } catch (e) {
                        if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
                      }
                    },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.send_to_mobile, color: okGreen),
              label: Text(t('payslips_publish_all')),
              onPressed: payRows.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(t('payslips_publish_all')),
                          content: Text(t('payslips_publish_q', {'n': '${payRows.length}'})),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('send'))),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        for (final r in payRows) {
                          await _publish(r.$1, r.$2, r.$3, r.$4, r.$5, r.$9, r.$6, r.$7, r.$8, r.$10, r.$11);
                        }
                        if (mounted) snack(context, t('payslips_sent', {'n': '${payRows.length}'}), color: okGreen);
                      } catch (e) {
                        if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
                      }
                    },
            ),
            if (widget.director) OutlinedButton.icon(
              icon: const Icon(Icons.summarize, color: danger),
              label: Text(t('monthly_report')),
              onPressed: () async {
                try {
                  await monthlyReport(month: _month, scope: 'AMANE Sécurité privée – tous les sites');
                } catch (e) {
                  if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Synthèse
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _kv(t('total_invoiced'), '${money(invTotal)} MRU'),
                _kv(t('total_salaries'), '${money(payTotal)} MRU'),
                _kv(t('cnss_employer'), '${money(cnssCoTotal)} MRU'),
                _kv(t('other_expenses'), '${money(expTotal)} MRU'),
                _kv(t('total_expenses'), '${money(payTotal + cnssCoTotal + expTotal)} MRU', bold: true),
                _kv(t('net_to_pay'), '${money(netTotal)} MRU'),
                const Divider(),
                _kv(t('margin'), '${money(margin)} MRU',
                    color: margin < 0 ? danger : okGreen, bold: true),
                _kv(t('hours_worked'), hours(hTotal)),
                const Divider(),
                _kv(t('cnss_due'), '${money(cnssEmpTotal + cnssCoTotal)} MRU', color: navy, bold: true),
                Text(t('cnss_note'), style: const TextStyle(color: muted, fontSize: 11.5)),
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
                subtitle: Text(
                    [
                      if (_job(r.$1) != null) t('job_${_job(r.$1)}'),
                      if (r.$9 > 0) t('monthly_line', {'m': money(r.$9)}),
                      if (r.$3 > 0 || r.$9 == 0)
                        t('pay_line', {'h': hours(r.$3), 'n': '${r.$4}', 'r': money(r.$5)}),
                    ].join(' · ') +
                    (r.$7.isEmpty
                        ? ''
                        : '\n${t('gross')} ${money(r.$6)} · ${t('adj_count', {'n': '${r.$7.length}'})}')),
                isThreeLine: r.$7.isNotEmpty,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${money(r.$8)} MRU',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: r.$8 < 0 ? danger : null)),
                    Text(t('net'), style: const TextStyle(fontSize: 11, color: muted)),
                  ],
                ),
                onTap: () => _payDetail(
                    uid: r.$1,
                    name: r.$2,
                    hours: r.$3,
                    shifts: r.$4,
                    rate: r.$5,
                    gross: r.$6,
                    adjs: r.$7,
                    monthly: r.$9,
                    cnssEmp: r.$10,
                    cnssCo: r.$11),
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
                  services: [
                    for (final x in widget.sites.where((s) => s.id == r.$1).firstOrNull?.services ?? const <String>[])
                      servicesFr[x] ?? x,
                  ],
                ),
                rate: () => _editRate('s_${r.$1}', r.$2, r.$4, t('billing_rate')),
                pdfLabel: t('pdf_invoice'),
                send: () async {
                  final site = widget.sites.where((s) => s.id == r.$1).firstOrNull;
                  await db.collection('invoices').doc(no).set({
                    'siteId': r.$1,
                    'siteName': r.$2,
                    'client': site?.client ?? '',
                    'number': no,
                    'month': '${two(_month.month)}/${_month.year}',
                    'hours': double.parse(r.$3.toStringAsFixed(1)),
                    'rate': r.$4,
                    'amount': (r.$3 * r.$4).roundToDouble(),
                    'sentAt': Timestamp.now(),
                  });
                  if (mounted) snack(context, t('invoice_sent'), color: okGreen);
                },
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        ExpensesSection(
            t: t,
            month: _month,
            items: exps,
            sites: widget.sites,
            users: widget.users,
            salaries: payTotal,
            cnss: cnssCoTotal),
        const SizedBox(height: 12),
        Text(t('acc_note'), style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 12),
        // Taux des sites / agents sans heures ce mois-ci
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('all_rates')),
          children: [
            for (final u in widget.users.where((u) => u.role == 'guard' || u.role == 'admin'))
              ListTile(
                dense: true,
                leading: Icon(jobIcon(u.job), size: 18),
                title: Text(u.name),
                subtitle: Text(t('job_${u.job}')),
                trailing: Text((rates['m_${u.id}'] ?? 0) > 0
                    ? '${money(rates['m_${u.id}']!)} MRU/${t('per_month')}'
                    : '${money(rates['g_${u.id}'] ?? 0)} MRU/h'),
                onTap: () => editStaff(context, t, u, salaryOnly: !widget.director),
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

  /// Fiche de paie d'un agent : brut, avances, retenues, absences, primes, net.
  Future<void> _payDetail({
    required String uid,
    required String name,
    required double hours,
    required int shifts,
    required double rate,
    required double gross,
    required List<Adj> adjs,
    double monthly = 0,
    double cnssEmp = 0,
    double cnssCo = 0,
  }) async {
    final phone = widget.users.where((u) => u.id == uid).firstOrNull?.phone ?? '';
    final job = _job(uid);
    final net = gross + adjs.fold<double>(0, (s, a) => s + a.signed) - cnssEmp;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              Text('${two(_month.month)}/${_month.year}', style: const TextStyle(color: muted)),
              const SizedBox(height: 10),
              if (job != null)
                Text(t('job_$job'), style: const TextStyle(color: navy, fontWeight: FontWeight.w600)),
              _kv(t('gross'), '${money(gross)} MRU'),
              if (monthly > 0)
                Text(t('monthly_line', {'m': money(monthly)}),
                    style: const TextStyle(color: muted, fontSize: 12)),
              if (hours > 0 || monthly == 0)
                Text(t('pay_line', {'h': hours.toStringAsFixed(1), 'n': '$shifts', 'r': money(rate)}),
                    style: const TextStyle(color: muted, fontSize: 12)),
              const Divider(),
              if (adjs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(t('no_adj'), style: const TextStyle(color: muted)),
                ),
              for (final a in adjs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(adjIcon(a.kind), color: a.signed < 0 ? danger : okGreen),
                  title: Text(t('adj_${a.kind}') + (a.note.isEmpty ? '' : ' · ${a.note}')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ltrText('${a.signed < 0 ? '−' : '+'}${money(a.amount)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: a.signed < 0 ? danger : okGreen)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => Navigator.pop(ctx, 'del:${a.id}'),
                      ),
                    ],
                  ),
                ),
              if (cnssEmp > 0)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.health_and_safety, color: danger),
                  title: Text(t('cnss_employee')),
                  trailing: ltrText('−${money(cnssEmp)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: danger)),
                ),
              const Divider(),
              _kv(t('net_to_pay'), '${money(net)} MRU', color: net < 0 ? danger : okGreen, bold: true),
              if (cnssCo > 0)
                Text(t('cnss_co_line', {'a': money(cnssCo)}),
                    style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in adjKinds)
                    ActionChip(
                      avatar: Icon(adjIcon(k), size: 18),
                      label: Text('+ ${t('adj_$k')}'),
                      onPressed: () => Navigator.pop(ctx, 'add:$k'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'pdf'),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(t('pdf_payslip')),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'publish'),
                    icon: const Icon(Icons.send_to_mobile, color: okGreen),
                    label: Text(t('payslip_publish')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'share'),
                    icon: const Icon(Icons.share, color: okGreen),
                    label: Text(t('payslip_whatsapp')),
                  ),
                ),
              ]),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'rate'),
                icon: const Icon(Icons.edit),
                label: Text(t('edit_staff')),
              ),
            ],
          ),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'publish') {
      try {
        await _publish(uid, name, hours, shifts, rate, monthly, gross, adjs, net, cnssEmp, cnssCo);
        if (mounted) snack(context, t('payslip_published', {'n': name}), color: okGreen);
      } catch (e) {
        if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
      }
    } else if (v == 'pdf' || v == 'share') {
      try {
        await printPayslip(
          share: v == 'share',
          name: name,
          phone: phone,
          month: '${two(_month.month)}/${_month.year}',
          hours: hours,
          shifts: shifts,
          rate: rate,
          monthly: monthly,
          job: jobsFr[job ?? 'guard'] ?? '',
          lines: [
            for (final a in adjs) (pdfAdjLabel(a), a.signed),
            if (cnssEmp > 0) ('Cotisation CNSS salarié (1 %)', -cnssEmp),
          ],
          employerCharges: cnssCo,
        );
      } catch (e) {
        if (mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
      }
    } else if (v == 'rate') {
      final u = widget.users.where((u) => u.id == uid).firstOrNull;
      if (u != null) {
        await editStaff(context, t, u, salaryOnly: !widget.director);
      } else {
        await _editRate('g_$uid', name, rate, t('hourly_pay'));
      }
    } else if (v.startsWith('del:')) {
      await db.collection('rates').doc(v.substring(4)).delete();
      if (mounted) snack(context, t('saved'), color: okGreen);
    } else if (v.startsWith('add:')) {
      await _addAdj(v.substring(4), uid, name, rate, monthly: monthly);
    }
  }

  /// Publie la fiche du mois dans l'espace de l'employé (« Mes fiches de paie »).
  Future<void> _publish(String uid, String name, double hours, int shifts, double rate, double monthly,
      double gross, List<Adj> adjs, double net, double cnssEmp, double cnssCo) {
    final u = widget.users.where((u) => u.id == uid).firstOrNull;
    return publishPayslip(
      uid: uid,
      name: name,
      job: jobsFr[_job(uid) ?? 'guard'] ?? '',
      phone: u?.phone ?? '',
      month: _month,
      hours: hours,
      shifts: shifts,
      rate: rate,
      monthly: monthly,
      gross: gross,
      lines: [
        for (final a in adjs) (pdfAdjLabel(a), a.signed),
        if (cnssEmp > 0) ('Cotisation CNSS salarié (1 %)', -cnssEmp),
      ],
      net: net,
      cnssCo: cnssCo,
    );
  }

  /// Ajoute une avance, une retenue, une absence ou une prime pour le mois affiché.
  Future<void> _addAdj(String kind, String uid, String name, double rate,
      {double monthly = 0}) async {
    // Valeur d'une journée : 1/30 du salaire mensuel + 12 h au taux horaire.
    final dayValue = monthly / 30 + 12 * rate;
    final amount = TextEditingController();
    final days = TextEditingController(text: '1');
    final note = TextEditingController();
    final absence = kind == 'absence';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t('adj_$kind')} · $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (absence) ...[
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('absence_days')),
              ),
              const SizedBox(height: 6),
              Text(t('absence_hint2', {'d': money(dayValue)}),
                  style: const TextStyle(color: muted, fontSize: 12)),
            ] else
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t('amount_mru')),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: t('adj_note')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    double value;
    var n = note.text.trim();
    if (absence) {
      final d = double.tryParse(days.text.replaceAll(',', '.').trim()) ?? 0;
      if (d <= 0) return;
      value = d * dayValue;
      n = '${d % 1 == 0 ? d.toInt() : d} ${t('days')}${n.isEmpty ? '' : ' · $n'}';
    } else {
      value = double.tryParse(amount.text.replaceAll(',', '.').replaceAll(' ', '').trim()) ?? 0;
    }
    if (value <= 0) return;
    // Rangé avec les taux : la collection est déjà réservée à l'administration.
    await db.collection('rates').add({
      'adj': true,
      'kind': kind,
      'uid': uid,
      'name': name,
      'month': _monthKey,
      'amount': value.roundToDouble(),
      'note': n,
      'at': Timestamp.now(),
    });
    if (mounted) snack(context, t('saved'), color: okGreen);
  }

  String pdfAdjLabel(Adj a) {
    const fr = {
      'advance': 'Avance sur salaire',
      'deduction': 'Retenue',
      'absence': 'Absence',
      'bonus': 'Prime',
    };
    return '${fr[a.kind] ?? a.kind}${a.note.isEmpty ? '' : ' – ${a.note}'}';
  }

  Future<void> _rowActions({
    required Future<void> Function() pdf,
    required Future<void> Function() rate,
    required String pdfLabel,
    Future<void> Function()? send,
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
            if (send != null)
              ListTile(
                leading: const Icon(Icons.send, color: navy),
                title: Text(t('send_invoice')),
                subtitle: Text(t('send_invoice_sub')),
                onTap: () => Navigator.pop(ctx, 'send'),
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
    } else if (v == 'send' && send != null) {
      try {
        await send();
      } catch (e) {
        if (mounted) snack(context, t('rules_needed'), color: danger);
      }
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

/// Élément de paie du mois : avance, retenue, absence (retenue) ou prime.
const adjKinds = ['advance', 'deduction', 'absence', 'bonus'];

IconData adjIcon(String k) => switch (k) {
      'advance' => Icons.payments,
      'deduction' => Icons.remove_circle_outline,
      'absence' => Icons.event_busy,
      'bonus' => Icons.card_giftcard,
      _ => Icons.circle,
    };

class Adj {
  Adj(this.id, Map<String, dynamic> m)
      : kind = m['kind'] is String ? m['kind'] as String : 'deduction',
        uid = m['uid'] is String ? m['uid'] as String : '',
        name = m['name'] is String ? m['name'] as String : '',
        month = m['month'] is String ? m['month'] as String : '',
        note = m['note'] is String ? m['note'] as String : '',
        amount = m['amount'] is num ? (m['amount'] as num).toDouble() : 0;
  final String id, kind, uid, name, month, note;
  final double amount;

  /// Positif pour une prime, négatif pour tout ce qui réduit le net.
  double get signed => kind == 'bonus' ? amount : -amount;
}


/// Espace du comptable : uniquement la comptabilité (paie, dépenses, factures,
/// CNSS, exports). Ni suivi, ni SOS, ni main courante, ni messages clients.
class AccountantHome extends StatelessWidget {
  const AccountantHome({super.key, required this.prefs, required this.me});
  final Prefs prefs;
  final UserDoc me;

  @override
  Widget build(BuildContext context) {
    final t = T(prefs.lang);
    // Le comptable pointe aussi son arrivée et son départ (onglet « Mon service »).
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: amaneAppBar(context, prefs,
          bottom: TabBar(
            labelColor: const Color(0xFFD1A850),
            unselectedLabelColor: const Color(0xFFB8C2CC),
            indicatorColor: const Color(0xFFD1A850),
            tabs: [Tab(text: t('tab_acc')), Tab(text: t('tab_mine'))],
          )),
      body: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
      StreamBuilder<QueryMap>(
        stream: db.collection('sites').snapshots(),
        builder: (context, sSnap) => StreamBuilder<QueryMap>(
          stream: db.collection('users').snapshots(),
          builder: (context, uSnap) {
            if (sSnap.hasError || uSnap.hasError) {
              return Center(child: Text(t('rules_needed'), style: const TextStyle(color: danger)));
            }
            final sites = (sSnap.data?.docs ?? const []).map((d) => Site(d.id, d.data())).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            final users = (uSnap.data?.docs ?? const []).map((d) => UserDoc(d.id, d.data())).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return AccountingTab(t: t, users: users, sites: sites, director: false);
          },
        ),
      ),
      GuardHome(prefs: prefs, me: me, embedded: true),
      ]),
      ),
    );
  }
}
