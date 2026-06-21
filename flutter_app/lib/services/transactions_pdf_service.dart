import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models/company_settings.dart';
import '../data/models/view_models.dart';


/// Builds the "Rapport de transactions" / "Rapport produit" PDF, mirroring
/// the layout of the desktop app's reportlab-based export
/// (ui/transactions_page.py `_build_pdf`).
class TransactionsPdfService {
  static const _primary = PdfColor.fromInt(0xFF1A5276);
  static const _primaryLight = PdfColor.fromInt(0xFF2E86C1);
  static const _accent = PdfColor.fromInt(0xFF2874A6);
  static const _green = PdfColor.fromInt(0xFF1E8449);
  static const _red = PdfColor.fromInt(0xFFC0392B);
  static const _orange = PdfColor.fromInt(0xFFD68910);
  static const _greyText = PdfColor.fromInt(0xFF555555);
  static const _border = PdfColor.fromInt(0xFFAEB6BF);
  static const _borderLight = PdfColor.fromInt(0xFFD5D8DC);
  static const _band = PdfColor.fromInt(0xFFEAF2F8);
  static const _rowIn = PdfColor.fromInt(0xFFD5F5E3);
  static const _rowOut = PdfColor.fromInt(0xFFFADBD8);

  static Future<Uint8List> build({
    required String? productRef,
    required List<TransactionRow> transactions,
    required ProductOverview? overview,
    required CompanySettings company,
    StoreAvailability? storeAvailability,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    final totalIn = transactions.fold<int>(0, (sum, t) => sum + t.inQty);
    final totalOut = transactions.fold<int>(0, (sum, t) => sum + t.outQty);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 10 * PdfPageFormat.mm,
          marginRight: 10 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        header: (context) {
          if (context.pageNumber != 1) return pw.SizedBox();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(company, productRef, now),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),
              _buildKpiRow(productRef, overview, totalIn, totalOut, transactions.length, storeAvailability: storeAvailability),
              pw.SizedBox(height: 6 * PdfPageFormat.mm),
              pw.Text(
                'DÉTAIL DES MOUVEMENTS',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _primary),
              ),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
            ],
          );
        },
        footer: (context) => _buildFooter(company, transactions.length, now),
        build: (context) => [_buildTransactionsTable(transactions)],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildDocumentHeader(CompanySettings company, String? productRef, DateTime now) {
    final name = company.name.isEmpty ? 'SOCOGEN' : company.name;

    final leftChildren = <pw.Widget>[
      pw.Text(name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primary)),
    ];

    final infoParts = <String>[
      if (company.address.isNotEmpty) company.address,
      if (company.city.isNotEmpty) company.city,
    ];
    if (infoParts.isNotEmpty) {
      leftChildren.add(pw.Text(infoParts.join('  |  '), style: pw.TextStyle(fontSize: 8, color: _greyText)));
    }

    final contactParts = <String>[
      if (company.phone.isNotEmpty) 'Tél : ${company.phone}',
      if (company.email.isNotEmpty) 'Email : ${company.email}',
      if (company.website.isNotEmpty) company.website,
    ];
    if (contactParts.isNotEmpty) {
      leftChildren.add(pw.Text(contactParts.join('  |  '), style: pw.TextStyle(fontSize: 8, color: _greyText)));
    }

    final legalParts = <String>[
      if (company.taxId.isNotEmpty) 'N° Contribuable : ${company.taxId}',
      if (company.rccm.isNotEmpty) 'RCCM : ${company.rccm}',
    ];
    if (legalParts.isNotEmpty) {
      leftChildren.add(pw.SizedBox(height: 1 * PdfPageFormat.mm));
      leftChildren.add(
        pw.Text(legalParts.join('    '), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _primary)),
      );
    }

    final rightChildren = <pw.Widget>[
      pw.Text(
        productRef != null ? 'RAPPORT PRODUIT' : 'RAPPORT DE TRANSACTIONS',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primary),
        textAlign: pw.TextAlign.right,
      ),
      pw.SizedBox(height: 2 * PdfPageFormat.mm),
      pw.Text(
        "Date d'édition : ${DateFormat('dd/MM/yyyy').format(now)}",
        style: pw.TextStyle(fontSize: 8, color: _greyText),
        textAlign: pw.TextAlign.right,
      ),
      pw.Text(
        'Heure : ${DateFormat('HH:mm').format(now)}',
        style: pw.TextStyle(fontSize: 8, color: _greyText),
        textAlign: pw.TextAlign.right,
      ),
    ];
    if (productRef != null) {
      rightChildren.add(pw.SizedBox(height: 2 * PdfPageFormat.mm));
      rightChildren.add(
        pw.RichText(
          textAlign: pw.TextAlign.right,
          text: pw.TextSpan(children: [
            pw.TextSpan(text: 'Produit : ', style: pw.TextStyle(fontSize: 9, color: _greyText)),
            pw.TextSpan(text: productRef, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _greyText)),
          ]),
        ),
      );
    }

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _primary, width: 2.5),
          bottom: pw.BorderSide(color: _primary, width: 1.2),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 3, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: leftChildren)),
          pw.Expanded(flex: 2, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: rightChildren)),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiRow(
    String? productRef,
    ProductOverview? overview,
    int totalIn,
    int totalOut,
    int count, {
    StoreAvailability? storeAvailability,
  }) {
    final items = <_KpiItem>[];
    if (productRef != null && overview != null) {
      final sa = storeAvailability;
      final storeName = sa != null ? sa.storeName : (overview.storeNames.isEmpty ? '-' : overview.storeNames);
      final initialStock = sa != null ? sa.initialStock : overview.initialStock;
      final current = sa != null ? sa.available : overview.currentStock;
      final currentColor = current > 10 ? _green : (current > 0 ? _orange : _red);
      items.addAll([
        _KpiItem('MAGASIN', storeName, _accent),
        _KpiItem('UNITÉ', overview.product.unit, PdfColors.black),
        _KpiItem('STOCK INITIAL', '$initialStock', PdfColors.black),
        _KpiItem('ENTRÉES', '+ $totalIn', _green),
        _KpiItem('SORTIES', '- $totalOut', _red),
        _KpiItem('STOCK ACTUEL', '$current', currentColor),
        _KpiItem('MOUVEMENTS', '$count', PdfColors.black),
      ]);
    } else {
      items.addAll([
        _KpiItem('TOUS LES PRODUITS', '-', PdfColors.black),
        _KpiItem('ENTRÉES TOTALES', '+ $totalIn', _green),
        _KpiItem('SORTIES TOTALES', '- $totalOut', _red),
        _KpiItem('MOUVEMENTS', '$count', PdfColors.black),
      ]);
    }

    final children = <pw.Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(pw.Container(
          width: 0.5,
          height: 9 * PdfPageFormat.mm,
          margin: const pw.EdgeInsets.symmetric(horizontal: 14),
          color: _borderLight,
        ));
      }
      children.add(pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(items[i].label, style: pw.TextStyle(fontSize: 7.5, color: _greyText)),
            pw.SizedBox(height: 2),
            pw.Text(items[i].value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: items[i].color)),
          ],
        ),
      ));
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _band,
        border: pw.Border.all(color: _border, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: pw.Row(children: children),
    );
  }

  static pw.Widget _buildTransactionsTable(List<TransactionRow> rows) {
    const headers = [
      'DATE',
      'TYPE',
      'RÉFÉRENCE',
      'DÉSIGNATION',
      'MAGASIN',
      'FOURN. / DEST.',
      'FACTURE',
      'ENTRÉE',
      'SORTIE',
      'SOLDE',
    ];
    // Total = 190mm to fit A4 portrait (210mm - 20mm margins)
    const widthsMm = [18.0, 13.0, 22.0, 32.0, 22.0, 28.0, 17.0, 13.0, 13.0, 12.0];
    final columnWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < widthsMm.length; i++) i: pw.FixedColumnWidth(widthsMm[i] * PdfPageFormat.mm),
    };

    pw.Widget headerCell(String text, int index) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: pw.Text(
            text,
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            textAlign: (index == 2 || index == 3 || index == 5) ? pw.TextAlign.left : pw.TextAlign.center,
          ),
        );

    pw.Widget cell(String text, {pw.TextAlign align = pw.TextAlign.left, PdfColor? color, bool bold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 7.5,
            color: color ?? PdfColors.black,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: align,
        ),
      );
    }

    String truncate(String text, int max) => text.length > max ? text.substring(0, max) : text;

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _primary),
        children: [for (var i = 0; i < headers.length; i++) headerCell(headers[i], i)],
      ),
    ];

    for (final row in rows) {
      final isEntry = row.type == TransactionType.entry;

      var displayDate = row.date;
      try {
        displayDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(row.date));
      } catch (_) {}

      final inTxt = row.inQty > 0 ? '+ ${row.inQty}' : '-';
      final outTxt = row.outQty > 0 ? '- ${row.outQty}' : '-';
      final balColor = row.balance > 10 ? _green : (row.balance > 0 ? _orange : _red);
      final partner = row.partner.isEmpty ? '-' : row.partner;
      final invoice = row.invoiceNumber.isEmpty ? '-' : row.invoiceNumber;

      tableRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: isEntry ? _rowIn : _rowOut),
        children: [
          cell(displayDate, align: pw.TextAlign.center),
          cell(isEntry ? 'Entrée' : 'Sortie', align: pw.TextAlign.center, color: isEntry ? _green : _red, bold: true),
          cell(row.reference),
          cell(truncate(row.designation, 36)),
          cell(row.storeName.isEmpty ? '-' : row.storeName),
          cell(truncate(partner, 40)),
          cell(invoice, align: pw.TextAlign.center),
          cell(inTxt, align: pw.TextAlign.right, color: _green, bold: true),
          cell(outTxt, align: pw.TextAlign.right, color: _red, bold: true),
          cell('${row.balance}', align: pw.TextAlign.right, color: balColor, bold: true),
        ],
      ));
    }

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _borderLight, width: 0.4),
      children: tableRows,
    );
  }

  static pw.Widget _buildFooter(CompanySettings company, int count, DateTime now) {
    final name = company.name.isEmpty ? 'SOCOGEN' : company.name;
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1, color: _primaryLight, margin: const pw.EdgeInsets.only(bottom: 3)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(name, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _primary)),
            pw.Text(
              'Document généré le ${DateFormat('dd/MM/yyyy à HH:mm').format(now)}',
              style: pw.TextStyle(fontSize: 7.5, color: _greyText),
            ),
            pw.Text('$count transaction(s)', style: pw.TextStyle(fontSize: 7.5, color: _greyText)),
          ],
        ),
      ],
    );
  }
}

class _KpiItem {
  final String label;
  final String value;
  final PdfColor color;

  const _KpiItem(this.label, this.value, this.color);
}
