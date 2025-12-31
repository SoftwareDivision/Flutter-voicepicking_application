// lib/utils/shipment_slip_generator.dart

// ✅ PRODUCTION READY v5.0 - DYNAMIC SINGLE/MULTI WITH DIFFERENT LAYOUTS
// Single Order: Bill To / Ship To side-by-side
// Multi Order: Customer delivery details table with both addresses

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'dart:developer';
import '../services/shipment_service.dart';

class ShipmentSlipGenerator {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Generate professional LOADING SHEET
  /// Single: Original layout with Bill To / Ship To
  /// Multi: New delivery details table approach
  static Future<Uint8List> generateShipmentSlip({
    required ShipmentOrder shipment,
    required Map<String, dynamic> qrData,
    required List<String> cartonBarcodes,
  }) async {
    // ✅ Step 1: Detect order type
    final isMultiCustomer = shipment.orderType == 'multi';
    log('📋 Generating ${isMultiCustomer ? "MULTI-CUSTOMER" : "SINGLE"} shipment slip');
    
    // ✅ Step 2: Fetch appropriate data
    final customerData = isMultiCustomer 
      ? null 
      : await _fetchCustomerOrderData(shipment.id);
    
    final multiCustomers = isMultiCustomer 
      ? await _fetchMultipleCustomers(shipment.id) 
      : null;
    
    final productDetails = await _fetchProductDetailsFromCartons(
      cartonBarcodes, 
      isMultiCustomer ? multiCustomers : null,
    );
    
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header (dynamic title)
              _buildDynamicHeader(shipment, isMultiCustomer),
              pw.SizedBox(height: 10),
              
              // ✅ CONDITIONAL: Show multi-customer table OR single address section
              if (isMultiCustomer && multiCustomers != null)
                _buildMultiCustomerSection(multiCustomers)
              else if (customerData != null)
                _buildAddressSection(customerData),
              
              pw.SizedBox(height: 10),
              
              // Transport details + QR (same for both)
              _buildDynamicTransportSection(shipment),
              pw.SizedBox(height: 10),
              
              // ✅ CONDITIONAL: Product table with customer grouping
              if (isMultiCustomer && multiCustomers != null)
                _buildMultiCustomerProductTable(productDetails, multiCustomers)
              else
                _buildProductDetailsTable(productDetails, shipment.customerName ?? 'N/A'),
              
              pw.Spacer(),
              
              // Signatures (same for both)
              _buildDynamicSignatureSection(shipment.shipmentType!),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ================================
  // FETCH SINGLE CUSTOMER DATA
  // ================================
  static Future<Map<String, dynamic>> _fetchCustomerOrderData(String shipmentOrderId) async {
    try {
      final sessionLinks = await _supabase
        .from('wms_shipment_packaging_sessions')
        .select('packaging_session_id, customer_name')
        .eq('shipment_order_id', shipmentOrderId)
        .limit(1)
        .maybeSingle();

      if (sessionLinks == null) return _getDefaultCustomerData();

      final packagingSession = await _supabase
        .from('packaging_sessions')
        .select('order_id')
        .eq('session_id', sessionLinks['packaging_session_id'])
        .maybeSingle();

      if (packagingSession == null) {
        return {
          'customer_name': sessionLinks['customer_name'] ?? 'Unknown',
          'bill_to_address': 'N/A',
          'ship_to_address': 'N/A',
          'customer_email': '',
          'customer_phone': '',
        };
      }

      final customerOrder = await _supabase
        .from('customer_orders')
        .select('customer_name, customer_email, customer_phone, bill_to_address, ship_to_address')
        .eq('order_id', packagingSession['order_id'])
        .maybeSingle();

      if (customerOrder != null) {
        return {
          'customer_name': customerOrder['customer_name'] ?? 'Unknown',
          'bill_to_address': customerOrder['bill_to_address'] ?? 'N/A',
          'ship_to_address': customerOrder['ship_to_address'] ?? 'N/A',
          'customer_email': customerOrder['customer_email'] ?? '',
          'customer_phone': customerOrder['customer_phone'] ?? '',
        };
      }

      return {
        'customer_name': sessionLinks['customer_name'] ?? 'Unknown',
        'bill_to_address': 'N/A',
        'ship_to_address': 'N/A',
        'customer_email': '',
        'customer_phone': '',
      };
    } catch (e) {
      log('❌ Error fetching customer data: $e');
      return _getDefaultCustomerData();
    }
  }

  static Map<String, dynamic> _getDefaultCustomerData() {
    return {
      'customer_name': 'Unknown Customer',
      'bill_to_address': 'N/A',
      'ship_to_address': 'N/A',
      'customer_email': '',
      'customer_phone': '',
    };
  }

  // ================================
  // ✅ FETCH MULTIPLE CUSTOMERS (MSO) WITH BOTH ADDRESSES
  // ================================
  static Future<List<Map<String, dynamic>>> _fetchMultipleCustomers(String shipmentOrderId) async {
    try {
      log('🔍 Fetching multiple customers for MSO');
      
      final sessionLinks = await _supabase
        .from('wms_shipment_packaging_sessions')
        .select('packaging_session_id, customer_name, order_number, carton_count')
        .eq('shipment_order_id', shipmentOrderId);
      
      final customers = <Map<String, dynamic>>[];
      
      for (var link in (sessionLinks as List)) {
        final packagingSession = await _supabase
          .from('packaging_sessions')
          .select('order_id')
          .eq('session_id', link['packaging_session_id'])
          .maybeSingle();
        
        if (packagingSession != null) {
          final customerOrder = await _supabase
            .from('customer_orders')
            .select('customer_name, bill_to_address, ship_to_address, customer_phone')
            .eq('order_id', packagingSession['order_id'])
            .maybeSingle();
          
          if (customerOrder != null) {
            customers.add({
              'customer_name': customerOrder['customer_name'] ?? link['customer_name'],
              'bill_to_address': customerOrder['bill_to_address'] ?? 'N/A',
              'ship_to_address': customerOrder['ship_to_address'] ?? 'N/A',
              'customer_phone': customerOrder['customer_phone'] ?? '',
              'order_number': link['order_number'] ?? '',
              'carton_count': link['carton_count'] ?? 0,
            });
          }
        }
      }
      
      log('✅ Found ${customers.length} customers in MSO');
      return customers;
    } catch (e) {
      log('❌ Error fetching multi customers: $e');
      return [];
    }
  }

  // ================================
  // FETCH PRODUCT DETAILS
  // ================================
  static Future<List<Map<String, dynamic>>> _fetchProductDetailsFromCartons(
    List<String> cartonBarcodes,
    List<Map<String, dynamic>>? multiCustomers,
  ) async {
    try {
      final productMap = <String, Map<String, dynamic>>{};
      
      log('🔍 Fetching products for ${cartonBarcodes.length} cartons');
      
      for (var cartonBarcode in cartonBarcodes) {
        final cartonResponse = await _supabase
          .from('package_cartons')
          .select('id, packaging_session_id')
          .eq('carton_barcode', cartonBarcode)
          .maybeSingle();
        
        if (cartonResponse == null) continue;
        
        final cartonId = cartonResponse['id'];
        
        // Get customer name from packaging session (for multi-customer)
        String? customerName;
        if (multiCustomers != null) {
          final sessionId = cartonResponse['packaging_session_id'];
          final sessionLink = await _supabase
            .from('wms_shipment_packaging_sessions')
            .select('customer_name')
            .eq('packaging_session_id', sessionId)
            .maybeSingle();
          customerName = sessionLink?['customer_name'];
        }
        
        final itemsResponse = await _supabase
          .from('carton_items')
          .select('quantity, picklist_item_id')
          .eq('carton_id', cartonId);
        
        for (var item in (itemsResponse as List)) {
          final picklistId = item['picklist_item_id'];
          final quantity = item['quantity'] ?? 0;
          
          if (picklistId == null) continue;
          
          final picklistItem = await _supabase
            .from('picklist')
            .select('item_name, sku')
            .eq('id', picklistId)
            .maybeSingle();
          
          if (picklistItem != null) {
            final productName = picklistItem['item_name'] ?? 'Unknown Product';
            final sku = picklistItem['sku'] ?? 'N/A';
            
            final key = '$sku-$productName-${customerName ?? ""}';
            if (productMap.containsKey(key)) {
              productMap[key]!['quantity'] += quantity;
            } else {
              productMap[key] = {
                'product_name': productName,
                'sku': sku,
                'quantity': quantity,
                'customer_name': customerName ?? 'N/A',
              };
            }
          }
        }
      }
      
      final result = productMap.values.toList();
      log('📊 Total unique products: ${result.length}');
      
      if (result.isEmpty) {
        return [{'product_name': 'No products found', 'sku': 'N/A', 'quantity': 0, 'customer_name': 'N/A'}];
      }
      
      return result;
      
    } catch (e) {
      log('❌ Error fetching products: $e');
      return [{'product_name': 'Error loading products', 'sku': 'N/A', 'quantity': 0, 'customer_name': 'N/A'}];
    }
  }

  // ================================
  // DYNAMIC HEADER
  // ================================
  static pw.Widget _buildDynamicHeader(ShipmentOrder shipment, bool isMultiCustomer) {
    final headerColor = _getHeaderColor(shipment.shipmentType!);
    final headerTitle = isMultiCustomer 
      ? 'MULTI-CUSTOMER ${_getHeaderTitle(shipment.shipmentType!)}' 
      : _getHeaderTitle(shipment.shipmentType!);
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: headerColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                headerTitle,
                style: pw.TextStyle(
                  fontSize: isMultiCustomer ? 16 : 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _getShipmentTypeLabel(shipment.shipmentType!),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                shipment.shipmentId,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Date: ${_formatDate(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
              pw.Text(
                'Cartons: ${shipment.totalCartons}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static PdfColor _getHeaderColor(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return PdfColors.blue900;
      case ShipmentType.courier:
        return PdfColors.purple900;
      case ShipmentType.inPerson:
        return PdfColors.green900;
    }
  }

  static String _getHeaderTitle(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return 'LOADING SHEET';
      case ShipmentType.courier:
        return 'COURIER DISPATCH';
      case ShipmentType.inPerson:
        return 'PICKUP SLIP';
    }
  }

  // ================================
  // ✅ MULTI-CUSTOMER SECTION - NEW APPROACH
  // ================================
  static pw.Widget _buildMultiCustomerSection(List<Map<String, dynamic>> customers) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue400, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        color: PdfColors.blue50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CUSTOMER DELIVERY DETAILS (${customers.length} Customers)',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.Divider(color: PdfColors.blue400, thickness: 1),
          pw.SizedBox(height: 5),
          
          // ✅ Detailed table with both addresses
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(20),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FixedColumnWidth(35),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _buildTableHeader('No'),
                  _buildTableHeader('Customer'),
                  _buildTableHeader('Bill To'),
                  _buildTableHeader('Ship To'),
                  _buildTableHeader('Crtn'),
                ],
              ),
              
              // Data rows
              ...customers.asMap().entries.map((entry) {
                final customer = entry.value;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: entry.key % 2 == 0 ? PdfColors.white : PdfColors.grey100,
                  ),
                  children: [
                    _buildTableCell('${entry.key + 1}'),
                    _buildTableCell(customer['customer_name'], fontSize: 7),
                    _buildTableCell(
                      _truncateAddress(customer['bill_to_address']), 
                      fontSize: 6,
                    ),
                    _buildTableCell(
                      _truncateAddress(customer['ship_to_address']), 
                      fontSize: 6,
                    ),
                    _buildTableCell('${customer['carton_count']}', fontSize: 7),
                  ],
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  static String _truncateAddress(String address) {
    if (address.length <= 40) return address;
    return '${address.substring(0, 37)}...';
  }

  // ================================
  // SINGLE CUSTOMER ADDRESS SECTION - ORIGINAL LAYOUT
  // ================================
  static pw.Widget _buildAddressSection(Map<String, dynamic> customerData) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.orange400, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BILL TO',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange900,
                  ),
                ),
                pw.Divider(color: PdfColors.orange400, thickness: 1),
                pw.SizedBox(height: 3),
                pw.Text(
                  customerData['customer_name'],
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  customerData['bill_to_address'],
                  style: const pw.TextStyle(fontSize: 8),
                  maxLines: 2,
                ),
                if (customerData['customer_phone'].isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Ph: ${customerData['customer_phone']}', style: const pw.TextStyle(fontSize: 7)),
                ],
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.green400, width: 1.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SHIP TO',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green900,
                  ),
                ),
                pw.Divider(color: PdfColors.green400, thickness: 1),
                pw.SizedBox(height: 3),
                pw.Text(
                  customerData['customer_name'],
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  customerData['ship_to_address'],
                  style: const pw.TextStyle(fontSize: 8),
                  maxLines: 2,
                ),
                if (customerData['customer_phone'].isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Ph: ${customerData['customer_phone']}', style: const pw.TextStyle(fontSize: 7)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================================
  // TRANSPORT + QR (SAME FOR BOTH)
  // ================================
  static pw.Widget _buildDynamicTransportSection(ShipmentOrder shipment) {
    final qrString = shipment.shipmentId;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: _buildTransportDetailsBox(shipment),
        ),
        pw.SizedBox(width: 10),
        pw.Container(
          width: 100,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.deepOrange, width: 2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              pw.BarcodeWidget(
                data: qrString,
                barcode: pw.Barcode.qrCode(),
                width: 85,
                height: 85,
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _getQRLabel(shipment.shipmentType!),
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.deepOrange,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTransportDetailsBox(ShipmentOrder shipment) {
    final borderColor = _getBorderColor(shipment.shipmentType!);
    final bgColor = _getBgColor(shipment.shipmentType!);
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        border: pw.Border.all(color: borderColor),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _getSectionTitle(shipment.shipmentType!),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: borderColor,
            ),
          ),
          pw.Divider(color: borderColor),
          
          if (shipment.shipmentType == ShipmentType.truck && shipment.truckDetails != null) ...[
            _buildDetailLine('Truck No', shipment.truckDetails!['truckNumber'] ?? 'N/A', true),
            _buildDetailLine('Transporter', shipment.truckDetails!['transporterName'] ?? 'N/A'),
            _buildDetailLine('Driver Name', shipment.truckDetails!['driverName'] ?? 'N/A'),
            _buildDetailLine('Driver Phone', shipment.truckDetails!['driverPhone'] ?? 'N/A'),
          ],
          
          if (shipment.shipmentType == ShipmentType.courier && shipment.courierDetails != null) ...[
            _buildDetailLine('Courier Service', shipment.courierDetails!['courierName'] ?? 'N/A', true),
            _buildDetailLine('AWB Number', shipment.courierDetails!['awbNumber'] ?? 'N/A', true),
            if (shipment.courierDetails!['expectedPickup'] != null)
              _buildDetailLine('Expected Pickup', shipment.courierDetails!['expectedPickup']),
          ],
          
          if (shipment.shipmentType == ShipmentType.inPerson && shipment.inPersonDetails != null) ...[
            _buildDetailLine('Pickup By', shipment.inPersonDetails!['contactPerson'] ?? 'N/A', true),
            _buildDetailLine('ID Proof Type', shipment.inPersonDetails!['idProof'] ?? 'N/A'),
            _buildDetailLine('Phone Number', shipment.inPersonDetails!['phoneNumber'] ?? 'N/A'),
          ],
        ],
      ),
    );
  }

  static PdfColor _getBorderColor(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return PdfColors.blue900;
      case ShipmentType.courier:
        return PdfColors.purple600;
      case ShipmentType.inPerson:
        return PdfColors.green700;
    }
  }

  static PdfColor _getBgColor(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return PdfColors.blue50;
      case ShipmentType.courier:
        return PdfColors.purple50;
      case ShipmentType.inPerson:
        return PdfColors.green50;
    }
  }

  static String _getSectionTitle(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return 'TRUCK DETAILS';
      case ShipmentType.courier:
        return 'COURIER DETAILS';
      case ShipmentType.inPerson:
        return 'PICKUP DETAILS';
    }
  }

  static String _getQRLabel(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return 'SCAN TO LOAD';
      case ShipmentType.courier:
        return 'SCAN TO DISPATCH';
      case ShipmentType.inPerson:
        return 'SCAN TO RELEASE';
    }
  }

  // ================================
  // ✅ MULTI-CUSTOMER PRODUCT TABLE
  // ================================
  static pw.Widget _buildMultiCustomerProductTable(
    List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> customers,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'PRODUCT DETAILS (${products.length} items)',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FixedColumnWidth(25),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FixedColumnWidth(40),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableHeader('No.'),
                _buildTableHeader('Product Name'),
                _buildTableHeader('Customer'),
                _buildTableHeader('Qty'),
              ],
            ),
            ...products.take(10).toList().asMap().entries.map((entry) {
              final product = entry.value;
              
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: entry.key % 2 == 0 ? PdfColors.white : PdfColors.grey100,
                ),
                children: [
                  _buildTableCell('${entry.key + 1}'),
                  _buildTableCell('${product['product_name']}\n(${product['sku']})', fontSize: 7),
                  _buildTableCell(product['customer_name'], fontSize: 7),
                  _buildTableCell('${product['quantity']}'),
                ],
              );
            }).toList(),
          ],
        ),
        
        if (products.length > 10)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '+ ${products.length - 10} more products',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.red),
            ),
          ),
      ],
    );
  }

  // ================================
  // SINGLE CUSTOMER PRODUCT TABLE
  // ================================
  static pw.Widget _buildProductDetailsTable(List<Map<String, dynamic>> products, String customerName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'PRODUCT DETAILS (${products.length} items)',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FixedColumnWidth(40),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableHeader('No.'),
                _buildTableHeader('Product Name'),
                _buildTableHeader('Customer'),
                _buildTableHeader('Qty'),
              ],
            ),
            ...products.take(12).toList().asMap().entries.map((entry) {
              final product = entry.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: entry.key % 2 == 0 ? PdfColors.white : PdfColors.grey100,
                ),
                children: [
                  _buildTableCell('${entry.key + 1}'),
                  _buildTableCell('${product['product_name']}\n(${product['sku']})', fontSize: 7),
                  _buildTableCell(customerName, fontSize: 7),
                  _buildTableCell('${product['quantity']}'),
                ],
              );
            }).toList(),
          ],
        ),
        
        if (products.length > 12)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '+ ${products.length - 12} more products',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.red),
            ),
          ),
      ],
    );
  }

  // ================================
  // DYNAMIC SIGNATURE SECTION
  // ================================
  static pw.Widget _buildDynamicSignatureSection(ShipmentType type) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: _getSignatureBoxes(type),
      ),
    );
  }

  static List<pw.Widget> _getSignatureBoxes(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return [
          _buildSignatureBox('Checked By', 'Warehouse Supervisor'),
          _buildSignatureBox('Driver Signature', 'Driver Name'),
          _buildSignatureBox('Loaded By', 'Loader Name'),
        ];
      case ShipmentType.courier:
        return [
          _buildSignatureBox('Packed By', 'Warehouse Staff'),
          _buildSignatureBox('Courier Agent', 'Agent Name & Sign'),
          _buildSignatureBox('Verified By', 'Supervisor'),
        ];
      case ShipmentType.inPerson:
        return [
          _buildSignatureBox('Prepared By', 'Warehouse Staff'),
          _buildSignatureBox('Recipient Sign', 'Name & Signature'),
          _buildSignatureBox('Released By', 'Supervisor'),
        ];
    }
  }

  static pw.Widget _buildSignatureBox(String label, String subtitle) {
    return pw.Container(
      width: 150,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            height: 35,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey50,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '$subtitle / Date: _____',
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ================================
  // HELPER FUNCTIONS
  // ================================
  
  static pw.Widget _buildDetailLine(String label, String value, [bool bold = false]) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Container(
            width: 85,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: bold ? 9 : 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildTableCell(String text, {double fontSize = 8}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize),
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  static String _getShipmentTypeLabel(ShipmentType type) {
    switch (type) {
      case ShipmentType.truck:
        return 'Truck Shipment';
      case ShipmentType.courier:
        return 'Courier Dispatch';
      case ShipmentType.inPerson:
        return 'In-Person Pickup';
    }
  }
}
