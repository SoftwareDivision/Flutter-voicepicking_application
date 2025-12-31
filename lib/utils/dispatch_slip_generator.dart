// lib/utils/dispatch_slip_generator.dart
// ✅ DISPATCH SLIP GENERATOR v6.1 - PROFESSIONAL
// - Combined Delivery Addresses Section
// - Customer + Driver Signatures
// - Professional Design

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:developer';
import '../services/shipment_service.dart';

class DispatchSlipGenerator {
  /// Generate Complete Dispatch Slip PDF
  static Future<Uint8List> generateDispatchSlip({
    required String shipmentOrderId,
  }) async {
    try {
      log('📄 Generating dispatch slip for: $shipmentOrderId');

      final dispatchData = await ShipmentService.getDispatchSlipData(
        shipmentOrderId: shipmentOrderId,
      );

      if (!(dispatchData['success'] ?? false)) {
        throw Exception(dispatchData['error'] ?? 'Unknown error');
      }

      log('✅ Data fetched successfully');

      final shipment = dispatchData['shipment'] as Map? ?? {};
      final driver = dispatchData['driver'] as Map? ?? {};
      final routes = dispatchData['routes'] as List? ?? [];
      final cartonsByStop = dispatchData['cartons_by_stop'] as Map? ?? {};

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
        ),
      );

      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(15),
          build: (context) {
            return [
              _buildDispatchHeader(shipment, dateStr, timeStr),
              pw.SizedBox(height: 8),

              _buildShipmentInfoSection(shipment, routes.length, cartonsByStop),
              pw.SizedBox(height: 6),

              _buildDriverInfoSection(driver),
              pw.SizedBox(height: 8),

              // COMBINED ADDRESSES SECTION
              _buildCombinedAddressesSection(routes),
              pw.SizedBox(height: 8),

              _buildRouteAndCartons(routes, cartonsByStop.cast<int, List<Map>>()),
            ];
          },
          footer: (context) {
            return _buildSignatureSection();
          },
        ),
      );

      log('✅ Dispatch slip generated successfully');
      return pdf.save();
    } catch (e) {
      log('❌ Error generating dispatch slip: $e');
      rethrow;
    }
  }

  /// 1. Header
  static pw.Widget _buildDispatchHeader(Map shipment, String dateStr, String timeStr) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey900, width: 2),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DISPATCH SLIP',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
              pw.Text(
                'Warehouse Management System',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Date: $dateStr', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Time: $timeStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. Shipment Info
  static pw.Widget _buildShipmentInfoSection(Map shipment, int totalStops, Map cartonsByStop) {
    int totalCartons = 0;
    for (var cartons in cartonsByStop.values) {
      if (cartons is List) totalCartons += cartons.length;
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SHIPMENT DETAILS',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: _buildCompactInfo('Shipment ID', shipment['id']?.toString() ?? 'N/A')),
              pw.Expanded(child: _buildCompactInfo('Truck No.', shipment['truck_number']?.toString() ?? 'N/A')),
              pw.Expanded(child: _buildCompactInfo('Total Stops', '$totalStops')),
              pw.Expanded(child: _buildCompactInfo('Total Cartons', '$totalCartons')),
            ],
          ),
        ],
      ),
    );
  }

  /// 3. Driver Info
  static pw.Widget _buildDriverInfoSection(Map driver) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 1),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DRIVER DETAILS',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: _buildCompactInfo('Driver Name', driver['driver_name'] ?? 'N/A')),
              pw.Expanded(child: _buildCompactInfo('Phone', driver['phone_number'] ?? 'N/A')),
              pw.Expanded(child: _buildCompactInfo('License ID', driver['license_id'] ?? 'N/A')),
              pw.Expanded(child: _buildCompactInfo('Vehicle', driver['vehicle_registration'] ?? 'N/A')),
            ],
          ),
        ],
      ),
    );
  }

  /// 4. COMBINED ADDRESSES SECTION - Professional Structure
  static pw.Widget _buildCombinedAddressesSection(List routes) {
    final firstRoute = routes.isNotEmpty ? routes[0] as Map : {};

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue600, width: 1.5),
        color: PdfColors.blue50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DELIVERY & BILLING INFORMATION',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 8),

          // Customer & Billing Info Row
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // BILL TO
              pw.Expanded(
                flex: 1,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue300, width: 1),
                    color: PdfColors.white,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BILL TO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        firstRoute['customer_name'] ?? 'N/A',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        firstRoute['customer_email'] ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        firstRoute['phone'] ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Address:',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue700,
                        ),
                      ),
                      pw.Text(
                        firstRoute['bill_to_address'] ?? 'N/A',
                        style: const pw.TextStyle(fontSize: 7),
                        maxLines: 3,
                        overflow: pw.TextOverflow.span,
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(width: 6),

              // SHIP TO - Same structure as BILL TO
              pw.Expanded(
                flex: 1,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue300, width: 1),
                    color: PdfColors.white,
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
                      pw.SizedBox(height: 5),
                      // List all stops
                      ...routes.asMap().entries.map((entry) {
                        int stopNum = entry.key + 1;
                        Map route = entry.value as Map;
                        bool isFirst = stopNum == 1;

                        return pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (!isFirst) pw.SizedBox(height: 4),
                            if (!isFirst) pw.Divider(height: 1, color: PdfColors.blue200),
                            if (!isFirst) pw.SizedBox(height: 4),
                            pw.Text(
                              'Stop $stopNum: ${route['customer_name'] ?? 'N/A'}',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              route['customer_email'] ?? 'N/A',
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                            pw.Text(
                              route['phone'] ?? 'N/A',
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'Address:',
                              style: pw.TextStyle(
                                fontSize: 7,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue700,
                              ),
                            ),
                            pw.Text(
                              route['address'] ?? route['ship_to_address'] ?? 'N/A',
                              style: const pw.TextStyle(fontSize: 7),
                              maxLines: 3,
                              overflow: pw.TextOverflow.span,
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Helper: Compact info
  static pw.Widget _buildCompactInfo(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 8),
          overflow: pw.TextOverflow.span,
          maxLines: 2,
        ),
      ],
    );
  }

  /// 5. Route & Cartons Table - Professional Clean Layout
  static pw.Widget _buildRouteAndCartons(List routes, Map<int, List<Map>> cartonsByStop) {
    // Collect all cartons from all stops
    final allCartons = <Map>[];
    int totalQty = 0;
    
    for (var stopNum in cartonsByStop.keys) {
      final cartons = cartonsByStop[stopNum] as List<Map>? ?? [];
      for (var carton in cartons) {
        allCartons.add(carton);
        totalQty += (carton['quantity'] as int? ?? 0);
      }
    }

    // Calculate rows needed for professional spacing (minimum 30 rows for long table)
    final minRows = 30;
    final actualRows = allCartons.length;
    final emptyRows = minRows > actualRows ? minRows - actualRows : 0;

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(color: PdfColors.grey900),
            child: pw.Text(
              'CARTON DETAILS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            ),
          ),
          
          // Main Table
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
              left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              right: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(40),
            },
            children: [
              // Table Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableHeader('Carton ID'),
                  _tableHeader('Product'),
                  _tableHeader('Qty'),
                ],
              ),
              
              // Actual Data Rows (with horizontal lines)
              ...allCartons.asMap().entries.map((entry) {
                int idx = entry.key;
                Map carton = entry.value;
                final product = carton['products'] as Map? ?? {};

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.white : PdfColors.grey50,
                  ),
                  children: [
                    _tableCell(carton['carton_barcode']?.toString() ?? 'N/A'),
                    _tableCell(product['product_name']?.toString() ?? 'Unknown'),
                    _tableCell((carton['quantity'] ?? 0).toString()),
                  ],
                );
              }).toList(),
            ],
          ),
          
          // Empty Rows WITHOUT horizontal lines
          ...List.generate(emptyRows, (index) {
            return pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              decoration: pw.BoxDecoration(
                color: (actualRows + index) % 2 == 0 ? PdfColors.white : PdfColors.grey50,
              ),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 80, child: pw.Text('')),
                  pw.Expanded(child: pw.Text('')),
                  pw.SizedBox(width: 40, child: pw.Text('')),
                ],
              ),
            );
          }),
          
          // Total Footer - Joined to table
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey900,
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      'TOTAL CARTONS: ',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      '${allCartons.length}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange300,
                      ),
                    ),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Text(
                      'TOTAL QTY: ',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      '$totalQty',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange300,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
    );
  }

  /// 6. SIGNATURE SECTION (FOOTER) - Driver + Customer ✅
  static pw.Widget _buildSignatureSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 1)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'AUTHORIZATION & ACKNOWLEDGMENT',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 6),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSignatureBox('Driver Signature'),
              _buildSignatureBox('Customer Signature'),
            ],
          ),

          pw.SizedBox(height: 4),
          pw.Text(
            'All parties acknowledge receipt and verification of shipment details and carton contents.',
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureBox(String label) {
    return pw.Container(
      width: 145,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 2),
          pw.Container(height: 1, width: 140, color: PdfColors.grey800),
          pw.SizedBox(height: 2),
          pw.Text('Date: __________', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  /// Show Dialog
  static Future<void> showDispatchSlipDialog({
    required BuildContext context,
    required String shipmentOrderId,
    required String shipmentId,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final pdfBytes = await generateDispatchSlip(shipmentOrderId: shipmentOrderId);

      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Dispatch Slip Ready!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_shipping, color: Colors.green.shade700, size: 18),
                            const SizedBox(width: 8),
                            const Text('Ready for dispatch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _infoRow('Shipment ID', shipmentId),
                        _infoRow('Generated', '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await Printing.sharePdf(bytes: pdfBytes, filename: 'dispatch_$shipmentId.pdf');
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: 'Dispatch - $shipmentId');
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                icon: const Icon(Icons.print),
                label: const Text('Print'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}
