import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const _navy = PdfColor.fromInt(0xFF0F2A40);
const _gold = PdfColor.fromInt(0xFFA9812F);
const _grey = PdfColor.fromInt(0xFF5C6670);

String _money(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b MRU';
}

String _h(double h) => h.toStringAsFixed(1).replaceAll('.', ',');

/// Polices avec l'arabe (téléchargées une fois, puis en cache).
/// Sans Internet, on se rabat sur la police par défaut (sans arabe).
Future<pw.ThemeData> _theme() async {
  try {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final ar = await PdfGoogleFonts.notoNaskhArabicRegular();
    return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [ar]);
  } catch (_) {
    return pw.ThemeData.base();
  }
}

// ---------------------------------------------------------------------------
// Papier à en-tête AMANE : bande dorée avec le logo au centre, aigle en
// filigrane, pied de page avec les coordonnées et bandes bleu nuit / or.
// ---------------------------------------------------------------------------

const _white = PdfColors.white;

class _Letterhead {
  _Letterhead(this.logo, this.shield);
  final pw.MemoryImage logo;
  final pw.MemoryImage shield;

  static Future<_Letterhead> load() async {
    Future<pw.MemoryImage> img(String p) async =>
        pw.MemoryImage((await rootBundle.load(p)).buffer.asUint8List());
    return _Letterhead(await img('assets/logo_full_t.png'), await img('assets/logo.png'));
  }

  /// Aigle très clair derrière le texte.
  pw.Widget background(pw.Context c) => pw.Stack(children: [
        pw.Positioned(
          left: -70,
          top: 300,
          child: pw.Opacity(opacity: 0.06, child: pw.Image(shield, width: 420)),
        ),
      ]);

  /// En-tête : bande dorée pleine largeur, losange blanc et logo centré.
  pw.Widget header() => pw.SizedBox(
        height: 150,
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Positioned.fill(
              child: pw.CustomPaint(painter: (PdfGraphics g, PdfPoint size) {
                final w = size.x, mid = 46.0, half = 20.0;
                // Bande dorée
                g
                  ..setFillColor(_gold)
                  ..drawRect(0, mid - half, w, half * 2)
                  ..fillPath();
                // Pointes blanches de part et d'autre du logo
                final cx = w / 2;
                g
                  ..setFillColor(_white)
                  ..moveTo(cx - 135, mid)
                  ..lineTo(cx - 110, mid + half + 2)
                  ..lineTo(cx + 110, mid + half + 2)
                  ..lineTo(cx + 135, mid)
                  ..lineTo(cx + 110, mid - half - 2)
                  ..lineTo(cx - 110, mid - half - 2)
                  ..closePath()
                  ..fillPath();
              }),
            ),
            pw.Positioned(
              top: 6,
              child: pw.Image(logo, height: 128),
            ),
          ],
        ),
      );

  /// Pied de page : coordonnées puis bandes bleu nuit / or.
  pw.Widget footer() => pw.Column(children: [
        pw.Text('SOCIÉTÉ AMANE SÉCURITÉ PRIVÉE – SARL au capital de 10 000 MRU · RC 131667/1597 · CNSS 1312532025 · Tevragh Zeina, Nouakchott',
            style: const pw.TextStyle(fontSize: 7.5, color: _grey)),
        pw.SizedBox(height: 3),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 40),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('amane.services.securite@gmail.com',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Text('NIF : 01641620',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Tél. 26511010 - 32511010',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.SizedBox(
          height: 26,
          child: pw.CustomPaint(painter: (PdfGraphics g, PdfPoint size) {
            final w = size.x, h = size.y;
            // Bleu nuit à gauche, pointe vers la droite
            g
              ..setFillColor(_navy)
              ..moveTo(0, 0)
              ..lineTo(w * 0.20, 0)
              ..lineTo(w * 0.235, h / 2)
              ..lineTo(w * 0.20, h)
              ..lineTo(0, h)
              ..closePath()
              ..fillPath();
            // Or au centre, extrémités en flèche
            g
              ..setFillColor(_gold)
              ..moveTo(w * 0.225, 0)
              ..lineTo(w * 0.775, 0)
              ..lineTo(w * 0.81, h / 2)
              ..lineTo(w * 0.775, h)
              ..lineTo(w * 0.225, h)
              ..lineTo(w * 0.26, h / 2)
              ..closePath()
              ..fillPath();
            // Bleu nuit à droite, pointe vers la gauche
            g
              ..setFillColor(_navy)
              ..moveTo(w, 0)
              ..lineTo(w * 0.80, 0)
              ..lineTo(w * 0.765, h / 2)
              ..lineTo(w * 0.80, h)
              ..lineTo(w, h)
              ..closePath()
              ..fillPath();
          }),
        ),
      ]);

  /// Page A4 complète : en-tête, contenu avec marges, pied de page.
  pw.Page page(List<pw.Widget> body) => pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          buildBackground: background,
        ),
        build: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header(),
            pw.SizedBox(height: 18),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: body,
                ),
              ),
            ),
            footer(),
          ],
        ),
      );
}

/// Ligne « Nouakchott, le … » / « N° … » sous l'en-tête.
pw.Widget _refLine(String title, String ref) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Nouakchott, le ${_today()}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(ref, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Center(
          child: pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 20,
                  letterSpacing: 2,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy)),
        ),
        pw.SizedBox(height: 18),
      ],
    );

pw.Widget _table(List<String> head, List<List<String>> rows, String total) {
  return pw.TableHelper.fromTextArray(
    headers: head,
    data: [
      ...rows,
      ['', '', 'Total', total],
    ],
    headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerRight,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
    },
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
  );
}

/// Facture mensuelle d'un site (hors taxes).
Future<void> printInvoice({
  required String number,
  required String siteName,
  required String client,
  required String month,
  required double hours,
  required double rate,
  List<String> services = const [],
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  final amount = hours * rate;
  final label = services.isEmpty ? 'Prestation de gardiennage' : services.join(', ');
  doc.addPage(lh.page([
    _refLine('FACTURE', 'N° $number'),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Client', style: const pw.TextStyle(color: _grey)),
              pw.Text(client.isEmpty ? siteName : client,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text('Site : $siteName'),
            ],
          ),
        ),
        pw.Text('Période : $month'),
      ],
    ),
    pw.SizedBox(height: 20),
    _table(
      ['Désignation', 'Heures', 'Tarif horaire', 'Montant'],
      [
        ['$label – $siteName', _h(hours), _money(rate), _money(amount)],
      ],
      _money(amount),
    ),
    pw.SizedBox(height: 16),
    pw.Text('Montant hors taxes, calculé sur les heures de présence pointées.',
        style: const pw.TextStyle(color: _grey, fontSize: 10)),
    pw.SizedBox(height: 14),
    // Coordonnées bancaires (RIB BIM du 22/09/2025).
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _gold, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Règlement par virement bancaire',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _navy)),
          pw.SizedBox(height: 4),
          pw.Text('Titulaire : SOCIÉTÉ AMANE SÉCURITÉ PRIVÉE – SARL', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Banque : BIM – Banque Islamique de Mauritanie, agence Siège social', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('N° de compte : 00015 00001 210 438135 01 26', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('IBAN : MR13 0001 5000 0121 0438 1350 126', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text('SWIFT / BIC : BIMMMRMRXXX', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text('Merci de rappeler le numéro de facture dans le libellé du virement.',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
        ],
      ),
    ),
    pw.Spacer(),
    pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('Le Directeur Général', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Sidi Abdella Sylla'),
          pw.SizedBox(height: 50),
        ],
      ),
    ),
  ]));
  await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'Facture-$number.pdf');
}

/// Fiche de paie mensuelle d'un agent (brut, hors cotisations).
Future<void> printPayslip({
  required String name,
  required String phone,
  required String month,
  required double hours,
  required int shifts,
  required double rate,
  double monthly = 0,
  String job = '',
  List<(String, double)> lines = const [],
  double employerCharges = 0,
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  final amount = hours * rate + monthly;
  final net = amount + lines.fold<double>(0, (s, l) => s + l.$2);
  String signed(double v) => v < 0 ? '- ${_money(-v)}' : '+ ${_money(v)}';
  doc.addPage(lh.page([
    _refLine('FICHE DE PAIE', month),
    pw.Text(job.isEmpty ? 'Agent' : job, style: const pw.TextStyle(color: _grey)),
    pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
    if (phone.isNotEmpty) pw.Text('Tél. $phone'),
    pw.SizedBox(height: 20),
    _table(
      ['Élément', 'Heures', 'Taux horaire', 'Montant'],
      [
        if (monthly > 0) ['Salaire mensuel', '', '', _money(monthly)],
        if (hours > 0 || monthly == 0)
          ['Heures de service ($shifts missions)', _h(hours), _money(rate), _money(hours * rate)],
        for (final l in lines) [l.$1, '', '', signed(l.$2)],
      ],
      lines.isEmpty ? _money(amount) : 'Net : ${_money(net)}',
    ),
    pw.SizedBox(height: 16),
    pw.Text(
        lines.isEmpty
            ? 'Salaire brut calculé sur les heures pointées, avant cotisations et retenues.'
            : 'Net à payer = salaire + primes - avances - retenues - absences - CNSS salarié.',
        style: const pw.TextStyle(color: _grey, fontSize: 10)),
    if (employerCharges > 0)
      pw.Text(
          'Charges patronales (CNSS 13 % + médecine du travail 2 %, plafond 15 000 MRU) : ${_money(employerCharges)} MRU – CNSS n° 1312532025',
          style: const pw.TextStyle(color: _grey, fontSize: 9.5)),
    pw.SizedBox(height: 40),
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text("Signature de l'agent"),
        pw.Column(children: [
          pw.Text('Le Directeur Général', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Sidi Abdella Sylla'),
        ]),
      ],
    ),
  ]));
  await Printing.layoutPdf(
      onLayout: (_) => doc.save(), name: 'Paie-${name.replaceAll(' ', '_')}-$month.pdf');
}

String _today() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Tableau simple à plusieurs colonnes (la première à gauche, les autres à droite).
pw.Widget _grid(List<String> head, List<List<String>> rows, {bool numeric = true}) {
  return pw.TableHelper.fromTextArray(
    headers: head,
    data: rows,
    headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    cellStyle: const pw.TextStyle(fontSize: 9.5),
    cellAlignments: {
      for (var i = 0; i < head.length; i++)
        i: (i == 0 || !numeric) ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
    },
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
  );
}

pw.Widget _section(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
    );

pw.Widget _kpis(List<(String, String)> items) => pw.Row(
      children: [
        for (final k in items)
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _gold, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(children: [
                pw.Text(k.$2, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _navy)),
                pw.Text(k.$1, style: const pw.TextStyle(fontSize: 8.5, color: _grey), textAlign: pw.TextAlign.center),
              ]),
            ),
          ),
      ],
    );

/// Rapport mensuel d'activité (administration ou client d'un site).
/// [bySite] / [byAgent] : (nom, missions, heures, pointages hors site).
/// [incidents] / [alerts] : (date, site, texte).
Future<void> printActivityReport({
  required String month,
  required String scope,
  required double hours,
  required int missions,
  required int offSite,
  required List<(String, int, double, int)> bySite,
  required List<(String, int, double, int)> byAgent,
  required List<(String, String, String)> incidents,
  required List<(String, String, String)> alerts,
  required int logCount,
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  List<String> row((String, int, double, int) r) =>
      [r.$1, '${r.$2}', _h(r.$3), r.$4 == 0 ? '—' : '${r.$4}'];
  final body = <pw.Widget>[
    _refLine("RAPPORT MENSUEL D'ACTIVITÉ", month),
    pw.Text(scope, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
    pw.SizedBox(height: 10),
    _kpis([
      ('Heures de garde', _h(hours)),
      ('Missions', '$missions'),
      ('Hors site', '$offSite'),
      ('Alertes SOS', '${alerts.length}'),
      ('Incidents', '${incidents.length}'),
      ('Main courante', '$logCount'),
    ]),
    if (bySite.length > 1) ...[
      _section('Par site'),
      _grid(['Site', 'Missions', 'Heures', 'Hors site'], [for (final r in bySite) row(r)]),
    ],
    _section('Par agent'),
    if (byAgent.isEmpty)
      pw.Text('Aucune mission ce mois-ci.', style: const pw.TextStyle(color: _grey))
    else
      _grid(['Agent', 'Missions', 'Heures', 'Hors site'], [for (final r in byAgent.take(25)) row(r)]),
    _section('Alertes SOS'),
    if (alerts.isEmpty)
      pw.Text('Aucune alerte ce mois-ci.', style: const pw.TextStyle(color: _grey))
    else
      _grid(['Date', 'Site', 'Nature'], [for (final a in alerts.take(12)) [a.$1, a.$2, a.$3]],
          numeric: false),
    _section('Incidents (main courante)'),
    if (incidents.isEmpty)
      pw.Text('Aucun incident signalé.', style: const pw.TextStyle(color: _grey))
    else
      _grid(['Date', 'Site', 'Description'],
          [for (final i in incidents.take(12)) [i.$1, i.$2, i.$3.length > 90 ? '${i.$3.substring(0, 90)}…' : i.$3]],
          numeric: false),
  ];
  // Plusieurs pages si nécessaire : en-tête et pied AMANE sur chacune.
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      buildBackground: lh.background,
    ),
    header: (c) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 14), child: lh.header()),
    footer: (c) => lh.footer(),
    build: (c) => [
      for (final w in body)
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 40), child: w),
    ],
  ));
  await Printing.layoutPdf(
      onLayout: (_) => doc.save(), name: 'Rapport-${scope.replaceAll(' ', '_')}-${month.replaceAll('/', '-')}.pdf');
}

/// État mensuel des dépenses de la société, sur papier à en-tête.
/// [byCat] : (catégorie, total) ; [lines] : (date, catégorie, libellé, montant).
Future<void> printExpenses({
  required String month,
  required List<(String, double)> byCat,
  required List<(String, String, String, double)> lines,
  required double total,
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  final body = <pw.Widget>[
    _refLine('ÉTAT DES DÉPENSES', month),
    pw.SizedBox(height: 6),
    _kpis([
      ('Total des dépenses (MRU)', _money(total)),
      ('Opérations', '${lines.length}'),
      ('Catégories', '${byCat.length}'),
    ]),
    _section('Par catégorie'),
    _grid(['Catégorie', 'Montant (MRU)'], [
      for (final c in byCat) [c.$1, _money(c.$2)],
      ['TOTAL', _money(total)],
    ]),
    _section('Détail des opérations'),
    _grid(['Date', 'Catégorie', 'Libellé', 'Montant (MRU)'], [
      for (final l in lines) [l.$1, l.$2, l.$3, _money(l.$4)],
    ], numeric: false),
  ];
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      buildBackground: lh.background,
    ),
    header: (c) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 14), child: lh.header()),
    footer: (c) => lh.footer(),
    build: (c) => [
      for (final w in body)
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 40), child: w),
    ],
  ));
  await Printing.layoutPdf(
      onLayout: (_) => doc.save(), name: 'Depenses-${month.replaceAll('/', '-')}.pdf');
}

/// Formulaire de consentement pré-rempli (agent ou client), bilingue,
/// sur papier à en-tête, à imprimer et faire signer.
/// [fields] : (libellé FR · AR, valeur) ; une valeur vide laisse une ligne à remplir.
Future<void> printConsent({
  required bool client,
  required List<(String, String)> fields,
  required List<(String, List<String>)> textFr,
  required List<(String, List<String>)> textAr,
  required String date,
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  const rtl = pw.TextDirection.rtl;
  pw.Widget fr((String, List<String>) p) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 5),
          pw.Text(p.$1, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: _navy)),
          for (final l in p.$2) pw.Bullet(text: l, style: const pw.TextStyle(fontSize: 9.5)),
        ],
      );
  pw.Widget ar((String, List<String>) p) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(height: 5),
          pw.Text(p.$1,
              textDirection: rtl,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _navy)),
          for (final l in p.$2)
            pw.Text('• $l', textDirection: rtl, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10)),
        ],
      );
  final title = client
      ? "CONDITIONS D'UTILISATION – CLIENT"
      : "CONSENTEMENT DE L'EMPLOYÉ(E)";
  final titleAr = client ? 'شروط استعمال التطبيق – الزبون' : 'نموذج موافقة الموظف';
  final body = <pw.Widget>[
    _refLine(title, date),
    pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(titleAr,
          textDirection: rtl, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _navy)),
    ),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
      children: [
        for (final f in fields)
          pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(f.$1, style: const pw.TextStyle(fontSize: 9.5))),
            pw.Padding(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(f.$2.isEmpty ? ' ' : f.$2,
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
          ]),
      ],
    ),
    _section('Texte français'),
    for (final p in textFr) fr(p),
    _section('النص العربي'),
    for (final p in textAr) ar(p),
    pw.SizedBox(height: 12),
    pw.Text("J'ai lu et compris ce document et j'en accepte les termes.", style: const pw.TextStyle(fontSize: 10)),
    pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('قرأت هذا النموذج وفهمته، وأوافق على ما فيه.', textDirection: rtl, style: const pw.TextStyle(fontSize: 10.5)),
    ),
    pw.SizedBox(height: 14),
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(client ? 'Signature du client' : "Signature de l'employé(e)",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(client ? 'توقيع الزبون' : 'توقيع الموظف', textDirection: rtl),
          pw.SizedBox(height: 50),
        ]),
        pw.Column(children: [
          pw.Text('Le Directeur Général', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('المدير العام', textDirection: rtl),
          pw.Text('Sidi Abdella Sylla'),
          pw.Text('سيد عبدالله سيلا', textDirection: rtl),
          pw.SizedBox(height: 40),
        ]),
      ],
    ),
    pw.Text('Établi en deux exemplaires · يُحرَّر في نسختين', style: const pw.TextStyle(color: _grey, fontSize: 9)),
  ];
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      buildBackground: lh.background,
    ),
    header: (c) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: lh.header()),
    footer: (c) => lh.footer(),
    build: (c) => [
      for (final w in body)
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 40), child: w),
    ],
  ));
  await Printing.layoutPdf(onLayout: (_) => doc.save(), name: '${client ? 'Conditions-client' : 'Consentement'}-$date.pdf');
}
