import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'expenses.dart';
import 'i18n.dart';
import 'logbook.dart';

/// Une ligne de paie telle que calculée dans l'onglet Comptabilité.
typedef PayRow = (String name, String job, double hours, int shifts, double rate, double monthly, double gross, double adj, double cnssEmp, double net, double cnssCo);

/// Une ligne de facture : (site, client, heures, tarif, montant).
typedef InvRow = (String site, String client, double hours, double rate, double amount);

CellValue _t(String s) => TextCellValue(s);
CellValue _n(num v) => DoubleCellValue(v.toDouble());

String _dt(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year} ${hm(d)}';

/// Classeur Excel du mois : présences, paie, dépenses, factures, main courante.
/// Sert de sauvegarde et de support pour le comptable.
Future<void> exportMonthXlsx({
  required DateTime month,
  required List<PunchDoc> punches,
  required List<PayRow> pay,
  required List<Expense> expenses,
  required List<InvRow> invoices,
}) async {
  final x = Excel.createExcel();
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);

  void sheet(String name, List<String> head, List<List<CellValue>> rows) {
    final s = x[name];
    s.appendRow([for (final h in head) _t(h)]);
    for (final r in rows) {
      s.appendRow(r);
    }
  }

  sheet('Présences', ['Agent', 'Site', 'Arrivée', 'Départ', 'Heures', 'Sur site'], [
    for (final p in [...punches]..sort((a, b) => a.inAt.compareTo(b.inAt)))
      [
        _t(p.name),
        _t(p.siteName),
        _t(_dt(p.inAt)),
        _t(p.outAt == null ? '' : _dt(p.outAt!)),
        _n(p.outAt == null ? 0 : math.min(24.0, p.outAt!.difference(p.inAt).inMinutes / 60.0)),
        _t(p.inOk == null ? '' : (p.inOk! ? 'Oui' : 'Non')),
      ],
  ]);

  sheet('Paie', ['Employé', 'Poste', 'Heures', 'Missions', 'Taux horaire', 'Salaire mensuel', 'Brut', 'Primes/retenues', 'CNSS salarié 1 %', 'Net', 'CNSS employeur 13 % + médecine 2 %'], [
    for (final r in pay) [_t(r.$1), _t(r.$2), _n(r.$3), _n(r.$4), _n(r.$5), _n(r.$6), _n(r.$7), _n(r.$8), _n(r.$9), _n(r.$10), _n(r.$11)],
  ]);

  sheet('Dépenses', ['Date', 'Catégorie', 'Libellé', 'Employé', 'Site', 'Montant'], [
    for (final e in [...expenses]..sort((a, b) => a.date.compareTo(b.date)))
      [
        _t('${two(e.date.day)}/${two(e.date.month)}/${e.date.year}'),
        _t(expenseCatsFr[e.cat] ?? e.cat),
        _t(e.label),
        _t(e.person),
        _t(e.siteName),
        _n(e.amount),
      ],
  ]);

  sheet('Factures', ['Site', 'Client', 'Heures', 'Tarif horaire', 'Montant'], [
    for (final r in invoices) [_t(r.$1), _t(r.$2), _n(r.$3), _n(r.$4), _n(r.$5)],
  ]);

  // Main courante du mois (lue directement : administration seulement).
  final logs = <LogDoc>[];
  try {
    final q = await db
        .collection('logs')
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('at', isLessThan: Timestamp.fromDate(to))
        .get();
    logs.addAll(q.docs.map((d) => LogDoc(d.id, d.data())));
  } catch (_) {}
  logs.sort((a, b) => a.at.compareTo(b.at));
  sheet('Main courante', ['Date', 'Agent', 'Site', 'Type', 'Texte', 'Photos'], [
    for (final l in logs)
      [_t(_dt(l.at)), _t(l.name), _t(l.siteName), _t(l.category), _t(l.text), _n(l.photos.length)],
  ]);

  x.delete('Sheet1');
  final bytes = x.save();
  if (bytes == null) throw Exception('Excel');
  final name = 'AMANE-${month.year}-${two(month.month)}.xlsx';
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: name,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ],
    fileNameOverrides: [name],
    subject: 'AMANE – export $name',
  ));
}
