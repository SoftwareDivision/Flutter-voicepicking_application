// lib/utils/pdf_slip_generator.dart
// ✅ FINAL - QR with detailed product info

import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart';
import 'dart:developer';

// ================================
// DATA MODELS
// ================================

class PackingSlipData {
  final String orderNumber;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String shippingAddress;
  final int boxNumber;
  final int totalBoxes;
  final String cartonBarcode;
  final String boxType;
  final double boxWeight;
  final List<SlipItem> items;
  final String shipperName;
  final String shipperAddress;
  final String shipperPhone;
  final DateTime packedDate;
  final String packedBy;
  final String uniqueSlipId;

  PackingSlipData({
    required this.orderNumber,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.shippingAddress,
    required this.boxNumber,
    required this.totalBoxes,
    required this.cartonBarcode,
    required this.boxType,
    required this.boxWeight,
    required this.items,
    required this.shipperName,
    required this.shipperAddress,
    required this.shipperPhone,
    required this.packedDate,
    required this.packedBy,
    required this.uniqueSlipId,
  });
}

class SlipItem {
  final String productName;
  final String sku;
  final int quantity;

  SlipItem({
    required this.productName,
    required this.sku,
    required this.quantity,
  });
}

// ================================
// PDF SLIP GENERATOR
// ================================

class PdfSlipGenerator {
  
  static Future<void> printAllSlips(List<PackingSlipData> allSlips, String orderNumber) async {
    log('📄 Generating PDF with ${allSlips.length} slips');
    
    final pdf = pw.Document();

    for (int i = 0; i < allSlips.length; i += 2) {
      final firstSlip = allSlips[i];
      final secondSlip = i + 1 < allSlips.length ? allSlips[i + 1] : null;

      log('📄 Adding page ${(i / 2).ceil() + 1}: Box ${firstSlip.boxNumber}${secondSlip != null ? ' and Box ${secondSlip.boxNumber}' : ''}');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  child: _buildSlipContent(firstSlip),
                ),
              ),
              _buildCutLine(),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  child: secondSlip != null
                      ? _buildSlipContent(secondSlip)
                      : _buildEmptySpace(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    log('📄 PDF generated with ${pdf.document.pdfPageList.pages.length} pages');

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Packing_Slips_$orderNumber.pdf',
    );
    
    log('✅ PDF printed successfully');
  }

  static Future<void> printSlip(PackingSlipData data) async {
    await printAllSlips([data], data.orderNumber);
  }

  static pw.Widget _buildCutLine() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        children: [
          pw.Icon(const pw.IconData(0xe14e), size: 10, color: PdfColors.grey),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              height: 1,
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(
                    color: PdfColors.grey400,
                    width: 1,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text('✂ CUT HERE ✂', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              height: 1,
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(
                    color: PdfColors.grey400,
                    width: 1,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Icon(const pw.IconData(0xe14e), size: 10, color: PdfColors.grey),
        ],
      ),
    );
  }

  static pw.Widget _buildEmptySpace() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 2, style: pw.BorderStyle.dashed),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Center(
        child: pw.Text(
          'No additional box',
          style: pw.TextStyle(fontSize: 11, color: PdfColors.grey400),
        ),
      ),
    );
  }

  static pw.Widget _buildSlipContent(PackingSlipData data) {
    int totalItemsInBox = 0;
    for (var item in data.items) {
      totalItemsInBox += item.quantity;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey800, width: 3),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeaderWithQR(data, totalItemsInBox),
            pw.SizedBox(height: 8),
            _buildShipToAndBoxInfo(data, totalItemsInBox),
            pw.SizedBox(height: 8),
            pw.Expanded(child: _buildItemsTable(data)),
            pw.SizedBox(height: 6),
            _buildFooter(data),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildHeaderWithQR(PackingSlipData data, int totalItems) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PACKAGING SLIP',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.purple900,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Order: ${data.orderNumber}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.purple,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'BOX ${data.boxNumber}/${data.totalBoxes}',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      '$totalItems Items',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildQRCodeWithDetails(data, totalItems),
      ],
    );
  }

  // ✅ QR CODE WITH DETAILED PRODUCT INFO - NO TEXT BELOW
  static pw.Widget _buildQRCodeWithDetails(PackingSlipData data, int totalItems) {
    // ✅ BUILD DETAILED JSON WITH PRODUCT LIST
    final qrData = {
      'order': data.orderNumber,
      'carton_no': data.cartonBarcode,
      'box': '${data.boxNumber}/${data.totalBoxes}',
      'total_items': totalItems,
      'items': data.items.map((item) => {
        'product': item.productName,
        'qty': item.quantity,
      }).toList(),
      'weight': '${data.boxWeight.toStringAsFixed(1)} kg',
      'packed_by': data.packedBy,
      'date': _formatDate(data.packedDate),
    };
    
    final encodedData = jsonEncode(qrData);
    
    pw.Widget qrWidget;
    
    try {
      final qr = Barcode.qrCode();
      qrWidget = pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey800, width: 2),
          borderRadius: pw.BorderRadius.circular(4),
          color: PdfColors.white,
        ),
        child: pw.BarcodeWidget(
          barcode: qr,
          data: encodedData,
          width: 85,  // ✅ Slightly bigger for more data
          height: 85,
        ),
      );
    } catch (e) {
      qrWidget = pw.Container(
        width: 85,
        height: 85,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Text(
          'QR Error',
          style: const pw.TextStyle(fontSize: 6),
          textAlign: pw.TextAlign.center,
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.grey50,
      ),
      child: qrWidget,  // ✅ NO TEXT BELOW - ONLY QR CODE
    );
  }

  static pw.Widget _buildShipToAndBoxInfo(PackingSlipData data, int totalItems) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blue300, width: 1.5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SHIP TO',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  data.customerName,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Email: ${data.customerEmail}',
                  style: const pw.TextStyle(fontSize: 7),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Phone: ${data.customerPhone}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  data.shippingAddress,
                  style: const pw.TextStyle(fontSize: 7),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip,
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Container(
          width: 90,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            border: pw.Border.all(color: PdfColors.amber400, width: 1.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'BOX DETAILS',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber900,
                ),
              ),
              pw.SizedBox(height: 3),
              _buildInfoRow('Type', _formatBoxType(data.boxType)),
              pw.SizedBox(height: 2),
              _buildInfoRow('Weight', '${data.boxWeight.toStringAsFixed(1)} kg'),
              pw.SizedBox(height: 2),
              _buildInfoRow('Products', '${data.items.length}'),
              pw.SizedBox(height: 2),
              _buildInfoRow('Total Qty', '$totalItems'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('$label:', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
      ],
    );
  }

  static pw.Widget _buildItemsTable(PackingSlipData data) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                topRight: pw.Radius.circular(5),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'PRODUCT',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(
                  width: 55,
                  child: pw.Text(
                    'SKU',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(
                  width: 30,
                  child: pw.Text(
                    'QTY',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          ...data.items.take(10).map((item) => _buildItemRow(item)),
          if (data.items.length > 10)
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(
                '+${data.items.length - 10} more items',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemRow(SlipItem item) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey200),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              item.productName,
              style: const pw.TextStyle(fontSize: 7),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          pw.SizedBox(
            width: 55,
            child: pw.Text(
              item.sku,
              style: const pw.TextStyle(fontSize: 7),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          pw.SizedBox(
            width: 30,
            child: pw.Text(
              '${item.quantity}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(PackingSlipData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Packed By: ${data.packedBy}',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Date: ${_formatDate(data.packedDate)}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Slip ID: ${data.uniqueSlipId}',
            style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static String _formatBoxType(String type) {
    switch (type) {
      case 'small':
        return 'Small';
      case 'medium':
        return 'Medium';
      case 'large':
        return 'Large';
      case 'extra_large':
        return 'XL';
      default:
        return type;
    }
  }

  static String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
