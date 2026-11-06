import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'audit.dart';
import 'data.dart';
import 'i18n.dart';
import 'pdf_docs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Fiche de paie publiée pour l'employé (collection « payslips »,
/// lisible uniquement par l'administration et l'employé concerné).
class Payslip {
  Payslip(this.id, Map<String, dynamic> m)
      : uid = _s(m['uid']),
        name = _s(m['name']),
        job = _s(m['job']),
        phone = _s(m['phone']),
        month = _s(m['month']),
        monthKey = _s(m['monthKey']),
        hours = _d(m['hours']),
        shifts = (m['shifts'] is num) ? (m['shifts'] as num).toInt() : 0,
        rate = _d(m['rate']),
        monthly = _d(m['monthly']),
        gross = _d(m['gross']),
        net = _d(m['net']),
        cnssCo = _d(m['cnssCo']),
        lines = [
          if (m['lines'] is List)
            for (final l in m['lines'] as List)
              if (l is Map) (_s(l['label']), _d(l['amount'])),
        ];
  final String id, uid, name, job, phone, month, monthKey;
  final double hours, rate, monthly, gross, net, cnssCo;
  final int shifts;
  final List<(String, double)> lines;

  static String _s(Object? v) => v is String ? v : '';
  static double _d(Object? v) => v is num ? v.toDouble() : 0;

  Future<void> pdf({bool share = false}) => printPayslip(
        name: name,
        phone: phone,
        month: month,
        hours: hours,
        shifts: shifts,
        rate: rate,
        monthly: monthly,
        job: job,
        lines: lines,
        employerCharges: cnssCo,
        share: share,
      );
}

/// Publie (ou remplace) la fiche du mois de l'employé.
Future<void> publishPayslip({
  required String uid,
  required String name,
  required String job,
  required String phone,
  required DateTime month,
  required double hours,
  required int shifts,
  required double rate,
  required double monthly,
  required double gross,
  required List<(String, double)> lines,
  required double net,
  required double cnssCo,
}) {
  final key = '${month.year}-${two(month.month)}';
  audit('payslip', '$name · $key · ${net.round()} MRU');
  return db.collection('payslips').doc('${uid}_$key').set({
    'uid': uid,
    'name': name,
    'job': job,
    'phone': phone,
    'month': '${two(month.month)}/${month.year}',
    'monthKey': key,
    'hours': double.parse(hours.toStringAsFixed(2)),
    'shifts': shifts,
    'rate': rate,
    'monthly': monthly,
    'gross': gross.roundToDouble(),
    'lines': [for (final l in lines) {'label': l.$1, 'amount': l.$2.roundToDouble()}],
    'net': net.roundToDouble(),
    'cnssCo': cnssCo,
    'sentAt': Timestamp.now(),
  });
}

/// « Mes fiches de paie » : écran de l'employé.
class MyPayslipsScreen extends StatelessWidget {
  const MyPayslipsScreen({super.key, required this.t, required this.me});
  final T t;
  final UserDoc me;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('my_payslips'))),
      body: StreamBuilder<QueryMap>(
        stream: db.collection('payslips').where('uid', isEqualTo: me.id).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(t('rules_needed'), style: const TextStyle(color: danger)));
          }
          final list = (snap.data?.docs ?? const [])
              .map((d) => Payslip(d.id, d.data()))
              .toList()
            ..sort((a, b) => b.monthKey.compareTo(a.monthKey));
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t('payslips_none'), textAlign: TextAlign.center, style: const TextStyle(color: muted)),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                const Icon(Icons.lock, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(child: Text(t('payslips_private'), style: const TextStyle(color: muted, fontSize: 12))),
              ]),
              const SizedBox(height: 8),
              for (final p in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, color: navy),
                    title: Text(p.month, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t('payslip_net', {'n': _fmt(p.net)})),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'PDF',
                        icon: const Icon(Icons.picture_as_pdf, color: danger),
                        onPressed: () => _run(context, () => p.pdf()),
                      ),
                      IconButton(
                        tooltip: t('share'),
                        icon: const Icon(Icons.share, color: navy),
                        onPressed: () => _run(context, () => p.pdf(share: true)),
                      ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) snack(context, t('err_generic', {'e': '$e'}), color: danger);
    }
  }
}

String _fmt(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b MRU';
}
