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
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  final amount = hours * rate;
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
        ['Prestation de gardiennage – $siteName', _h(hours), _money(rate), _money(amount)],
      ],
      _money(amount),
    ),
    pw.SizedBox(height: 16),
    pw.Text('Montant hors taxes, calculé sur les heures de présence pointées.',
        style: const pw.TextStyle(color: _grey, fontSize: 10)),
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
}) async {
  final doc = pw.Document(theme: await _theme());
  final lh = await _Letterhead.load();
  final amount = hours * rate;
  doc.addPage(lh.page([
    _refLine('FICHE DE PAIE', month),
    pw.Text('Agent', style: const pw.TextStyle(color: _grey)),
    pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
    if (phone.isNotEmpty) pw.Text('Tél. $phone'),
    pw.SizedBox(height: 20),
    _table(
      ['Élément', 'Heures', 'Taux horaire', 'Montant'],
      [
        ['Heures de service ($shifts missions)', _h(hours), _money(rate), _money(amount)],
      ],
      _money(amount),
    ),
    pw.SizedBox(height: 16),
    pw.Text('Salaire brut calculé sur les heures pointées, avant cotisations et retenues.',
        style: const pw.TextStyle(color: _grey, fontSize: 10)),
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
