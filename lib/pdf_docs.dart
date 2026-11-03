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

Future<pw.Widget> _header(String title, String subtitle) async {
  final logo = pw.MemoryImage(
      (await rootBundle.load('assets/logo.png')).buffer.asUint8List());
  return pw.Column(children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Image(logo, width: 56),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('AMANE',
                  style: pw.TextStyle(
                      fontSize: 22,
                      letterSpacing: 3,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.Text('Sécurité privée',
                  style: const pw.TextStyle(color: _gold, fontSize: 11)),
              pw.Text('أمان للأمن الخصوصي',
                  textDirection: pw.TextDirection.rtl,
                  style: const pw.TextStyle(color: _gold, fontSize: 11)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.Text(subtitle, style: const pw.TextStyle(color: _grey)),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Divider(color: _gold, thickness: 1.5),
    pw.SizedBox(height: 14),
  ]);
}

pw.Widget _footer() => pw.Column(children: [
      pw.Divider(color: _grey, thickness: 0.5),
      pw.Text(
        'AMANE Sécurité privée · Tél. +222 26 51 10 10 · amane.services.securite@gmail.com',
        style: const pw.TextStyle(color: _grey, fontSize: 9),
      ),
    ]);

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
  final header = await _header('FACTURE', 'N° $number');
  final amount = hours * rate;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (c) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        header,
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
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Période : $month'),
                pw.Text('Date : ${_today()}'),
              ],
            ),
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
        _footer(),
      ],
    ),
  ));
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
  final header = await _header('FICHE DE PAIE', month);
  final amount = hours * rate;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (c) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        header,
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
            pw.Text('Signature de l\'agent'),
            pw.Text('Pour AMANE, le gérant'),
          ],
        ),
        pw.Spacer(),
        _footer(),
      ],
    ),
  ));
  await Printing.layoutPdf(
      onLayout: (_) => doc.save(), name: 'Paie-${name.replaceAll(' ', '_')}-$month.pdf');
}

String _today() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}
