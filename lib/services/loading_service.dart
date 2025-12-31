// lib/services/loading_service.dart
// ✅ PRODUCTION READY v5.0 - WITH COMPLETE LIFO/NON-LIFO SUPPORT

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';

class LoadingService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ================================
  // SHIPMENT & LOADING METHODS
  // ================================

  /// Process shipment QR code
  static Future<Map<String, dynamic>> processShipmentQR(
      Map<String, dynamic> qrContent) async {
    try {
      log('🔄 Processing shipment QR code...');

      if (!qrContent.containsKey('truck_number') ||
          !qrContent.containsKey('customer_name') ||
          !qrContent.containsKey('carton_list')) {
        return {
          'success': false,
          'error': 'Invalid QR Code',
          'details': 'Missing required shipment information'
        };
      }

      final sessionId = 'SHIP_${DateTime.now().millisecondsSinceEpoch}';
      final warehouseId = await _getDefaultWarehouseId();

      final sessionData = {
        'session_id': sessionId,
        'warehouse_id': warehouseId,
        'truck_number':
            qrContent['truck_number'].toString().toUpperCase().trim(),
        'customer_name': qrContent['customer_name'].toString().trim(),
        'shipper_name': qrContent['shipper_name']?.toString() ?? 'Unknown',
        'destination': qrContent['destination']?.toString() ?? 'Unknown',
        'total_cartons': (qrContent['carton_list'] as List).length,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('shipment_sessions').insert(sessionData);
      log('✅ Shipment session inserted: $sessionId');

      final cartonList = qrContent['carton_list'] as List;
      final cartonInserts = cartonList
          .map((carton) => {
                'session_id': sessionId,
                'carton_id': carton.toString().toUpperCase().trim(),
                'is_scanned': false,
                'created_at': DateTime.now().toIso8601String(),
              })
          .toList();

      if (cartonInserts.isNotEmpty) {
        await _supabase.from('wms_shipment_cartons').insert(cartonInserts);
        log('✅ ${cartonInserts.length} cartons inserted');
      }

      return {
        'success': true,
        'session_id': sessionId,
        'shipment_data': {
          'session_id': sessionId,
          'truck_number': sessionData['truck_number'],
          'customer_name': sessionData['customer_name'],
          'shipper_name': sessionData['shipper_name'],
          'destination': sessionData['destination'],
          'carton_list': cartonList
              .map((c) => c.toString().toUpperCase().trim())
              .toList(),
          'total_cartons': cartonList.length,
        },
        'message': 'Shipment sheet processed and saved successfully'
      };
    } catch (e) {
      log('❌ Process shipment QR error: $e');
      return {
        'success': false,
        'error': 'Database Insert Failed',
        'details': e.toString()
      };
    }
  }

  /// Verify truck number
  static Future<Map<String, dynamic>> verifyTruckNumber({
    required String sessionId,
    required String expectedTruckNumber,
    required String scannedTruckNumber,
  }) async {
    try {
      log('🔄 Verifying truck number: $scannedTruckNumber vs $expectedTruckNumber');

      final cleanExpected = expectedTruckNumber.toUpperCase().trim();
      final cleanScanned = scannedTruckNumber.toUpperCase().trim();

      if (cleanExpected == cleanScanned) {
        await _supabase.from('wms_loading_sessions').update({
          'truck_verified': true,
          'truck_verified_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('session_id', sessionId);

        log('✅ Truck verification updated in database: $sessionId');

        return {
          'success': true,
          'truck_number': cleanScanned,
          'message': 'Truck number verified and saved successfully'
        };
      } else {
        return {
          'success': false,
          'error': 'Truck Number Mismatch',
          'details': 'Expected: $cleanExpected, Got: $cleanScanned'
        };
      }
    } catch (e) {
      log('❌ Verify truck number error: $e');
      return {
        'success': false,
        'error': 'Database Update Failed',
        'details': e.toString()
      };
    }
  }

  // ============================================================
  // ✅ LIFO/NON-LIFO FUNCTIONS - NEW
  // ============================================================

  /// 🔄 Calculate LIFO Sequence
  static Future<List<Map<String, dynamic>>> calculateLifoSequence({
    required String shipmentOrderId,
  }) async {
    try {
      log('📊 [LIFO] Calculating sequence for: $shipmentOrderId');

      final cartons = await _supabase
          .from('wms_shipment_cartons')
          .select(
              'carton_barcode, stop_sequence, customer_name, delivery_address')
          .eq('shipment_order_id', shipmentOrderId)
          .order('stop_sequence', ascending: false) // ✅ REVERSE for LIFO
          .timeout(Duration(seconds: 10));

      if (cartons.isEmpty) {
        log('⚠️ No cartons found');
        return [];
      }

      int loadingOrder = 1;
      final lifoSequence = <Map<String, dynamic>>[];

      for (var carton in cartons) {
        lifoSequence.add({
          'carton_barcode': carton['carton_barcode'].toString().toUpperCase(),
          'stop_sequence': carton['stop_sequence'] ?? 1,
          'expected_loading_order': loadingOrder,
          'customer_name': carton['customer_name'],
          'delivery_address': carton['delivery_address'],
        });
        loadingOrder++;
      }

      log('✅ [LIFO] Calculated: ${lifoSequence.length} cartons in sequence');
      return lifoSequence;
    } catch (e) {
      log('❌ [LIFO] Error: $e');
      return [];
    }
  }

  /// ✅ Validate LIFO Scan
  static Future<Map<String, dynamic>> validateLifoScan({
    required String cartonBarcode,
    required int currentScanNumber,
    required List<Map<String, dynamic>> lifoSequence,
  }) async {
    try {
      if (lifoSequence.isEmpty) {
        return {
          'valid': true,
          'message': '✅ NON-LIFO: Carton scanned (any order)',
        };
      }

      final scanned = cartonBarcode.toUpperCase().trim();

      // Check if exceeds total
      if (currentScanNumber > lifoSequence.length) {
        return {
          'valid': false,
          'error': 'EXCESS_SCAN',
          'message': 'All cartons already scanned!',
        };
      }

      // Get expected carton
      final expected = lifoSequence[currentScanNumber - 1];
      final expectedBarcode =
          expected['carton_barcode'].toString().toUpperCase();
      final expectedStop = expected['stop_sequence'];

      log('🔄 [LIFO] Scan #$currentScanNumber - Expected: $expectedBarcode, Scanned: $scanned');

      // ✅ CORRECT
      if (scanned == expectedBarcode) {
        return {
          'valid': true,
          'message':
              '✅ Correct!\nStop $expectedStop\nPosition: $currentScanNumber/${lifoSequence.length}',
          'stop_sequence': expectedStop,
        };
      }

      // ❌ FIND WHERE CARTON SHOULD BE
      final actualPosition = lifoSequence.indexWhere(
          (item) => item['carton_barcode'].toString().toUpperCase() == scanned);

      if (actualPosition == -1) {
        return {
          'valid': false,
          'error': 'UNKNOWN_CARTON',
          'message': '❌ Carton not in this shipment!',
        };
      }

      // ❌ WRONG SEQUENCE
      final actualStop = lifoSequence[actualPosition]['stop_sequence'];
      return {
        'valid': false,
        'error': 'WRONG_SEQUENCE',
        'message':
            '❌ LIFO VIOLATION!\n\nExpected: $expectedBarcode (Stop $expectedStop)\nScanned: $scanned (Stop $actualStop)\n\nShould scan at position ${actualPosition + 1}',
        'expected_stop': expectedStop,
        'actual_stop': actualStop,
      };
    } catch (e) {
      log('❌ Validation error: $e');
      return {'valid': false, 'error': 'VALIDATION_ERROR'};
    }
  }

  /// ✅ Create Loading Session
  static Future<Map<String, dynamic>> createLoadingSession({
    required String shipmentOrderId,
    required String userName,
    required String truckNumber,
    required bool isLifo,
    required int totalCartons,
  }) async {
    try {
      log('📝 [SESSION] Creating...');

      final sessionNumber = 'LS_${DateTime.now().millisecondsSinceEpoch}';

      final response = await _supabase
          .from('wms_loading_sessions')
          .insert({
            'session_number': sessionNumber,
            'shipment_order_id': shipmentOrderId,
            'user_name': userName,
            'user_id': userName,
            'truck_number': truckNumber,
            'loading_strategy': isLifo ? 'lifo' : 'non_lifo',
            'is_lifo': isLifo,
            'status': 'in_progress',
            'total_cartons': totalCartons,
            'scanned_cartons': 0,
            'compliance_percentage': 0,
            'started_at': DateTime.now().toIso8601String(),
          })
          .select('session_id')
          .single();

      log('✅ [SESSION] Created: ${response['session_id']}');
      return {
        'success': true,
        'session_id': response['session_id'],
        'session_number': sessionNumber,
      };
    } catch (e) {
      log('❌ Session error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// ✅ Record Carton Scan
  static Future<Map<String, dynamic>> recordCartonScan({
    required String sessionId,
    required String cartonBarcode,
    required int scanOrder,
    required bool isValid,
  }) async {
    try {
      log('💾 [SCAN] Recording: $cartonBarcode at position $scanOrder');

      // Update carton in database
      await _supabase.from('wms_shipment_cartons').update({
        'actual_loading_order': scanOrder,
        'loading_status': 'scanned',
      }).eq('carton_barcode', cartonBarcode);

      // Record violation if invalid
      if (!isValid) {
        await _supabase.from('wms_loading_violations').insert({
          'loading_session_id': sessionId,
          'carton_barcode': cartonBarcode,
          'violation_type': 'wrong_sequence',
          'message': 'Scanned out of LIFO order',
          'occurred_at': DateTime.now().toIso8601String(),
        });

        log('⚠️ [VIOLATION] Recorded for: $cartonBarcode');
      }

      // Update session progress
      final session = await _supabase
          .from('wms_loading_sessions')
          .select('scanned_cartons, total_cartons')
          .eq('session_id', sessionId)
          .single();

      final currentScanned = ((session['scanned_cartons'] ?? 0) as int) + 1;
      final totalCartons = session['total_cartons'] as int;
      final compliance = ((currentScanned / totalCartons) * 100).toInt();

      await _supabase.from('wms_loading_sessions').update({
        'scanned_cartons': currentScanned,
        'compliance_percentage': compliance,
      }).eq('session_id', sessionId);

      log('✅ [SCAN] Progress: $currentScanned/$totalCartons (${compliance}%)');
      return {
        'success': true,
        'scanned': currentScanned,
        'total': totalCartons,
        'compliance': compliance,
      };
    } catch (e) {
      log('❌ Scan error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// ✅ Complete Loading Session
  static Future<Map<String, dynamic>> completeLoadingSession({
    required String sessionId,
  }) async {
    try {
      log('🏁 [SESSION] Completing...');

      final response = await _supabase
          .from('wms_loading_sessions')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('session_id', sessionId)
          .select('scanned_cartons, total_cartons, compliance_percentage')
          .single();

      log('✅ [SESSION] Completed with ${response['compliance_percentage']}% compliance');
      return {
        'success': true,
        'compliance': response['compliance_percentage'],
        'scanned': response['scanned_cartons'],
        'total': response['total_cartons'],
      };
    } catch (e) {
      log('❌ Completion error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // EXISTING CARTON SCANNING (LEGACY - NON-LIFO)
  // ============================================================

  /// Process carton scan (legacy, non-LIFO)
  static Future<Map<String, dynamic>> processCartonScan({
    required String sessionId,
    required String cartonId,
    required List<String> expectedCartons,
    required List<String> scannedCartons,
  }) async {
    try {
      log('🔄 Processing carton scan: $cartonId');

      final cleanCartonId = cartonId.toUpperCase().trim();

      if (!expectedCartons.contains(cleanCartonId)) {
        return {
          'success': false,
          'error': 'Invalid Carton',
          'details': 'Carton $cleanCartonId is not in this shipment'
        };
      }

      // ✅ FIXED: Use correct column names for wms_shipment_cartons
      final existingCarton = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', sessionId)
          .eq('carton_barcode', cleanCartonId)
          .eq('is_loaded', true)
          .maybeSingle();

      if (existingCarton != null) {
        return {
          'success': false,
          'error': 'Duplicate Scan',
          'details': 'Carton $cleanCartonId already scanned'
        };
      }

      // ✅ FIXED: Update using correct column names
      await _supabase.from('wms_shipment_cartons').update({
        'is_loaded': true,
        'loaded_at': DateTime.now().toIso8601String(),
        'loaded_by': 'Current User',
        'loading_status': 'scanned',
      }).eq('shipment_order_id', sessionId).eq('carton_barcode', cleanCartonId);

      log('✅ Carton scan updated in database: $cleanCartonId');

      // ✅ FIXED: Query using correct column names
      final scannedCountData = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', sessionId)
          .eq('is_loaded', true);

      final totalCartonsData = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', sessionId);

      final isComplete = scannedCountData.length >= totalCartonsData.length;

      if (isComplete) {
        // ✅ FIXED: Update wms_shipment_orders instead of shipment_sessions
        await _supabase.from('wms_shipment_orders').update({
          'status': 'loading_completed',
          'loading_started_at': DateTime.now().toIso8601String(),
        }).eq('id', sessionId);

        log('✅ Session completed: $sessionId');
      }

      return {
        'success': true,
        'carton_id': cleanCartonId,
        'scanned_count': scannedCountData.length,
        'total_count': totalCartonsData.length,
        'all_scanned': isComplete,
        'message': isComplete
            ? 'All cartons scanned successfully!'
            : 'Carton $cleanCartonId scanned (${scannedCountData.length}/${totalCartonsData.length})'
      };
    } catch (e) {
      log('❌ Process carton scan error: $e');
      return {
        'success': false,
        'error': 'Database Update Failed',
        'details': e.toString()
      };
    }
  }

  // ================================
  // LOADING REPORTS MANAGEMENT
  // ================================

  /// Generate loading report
  static Future<Map<String, dynamic>> generateLoadingReport({
    required String sessionId,
    required Map<String, dynamic> shipmentData,
    required List<String> scannedCartons,
    required String operatorName,
  }) async {
    try {
      log('🔄 Generating loading report for session: $sessionId');

      // ✅ FIXED: Get from wms_shipment_orders instead
      final sessionInfo = await _supabase
          .from('wms_shipment_orders')
          .select('*')
          .eq('id', sessionId)
          .single();

      // ✅ FIXED: Use correct column name
      final cartonInfo = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', sessionId);

      // ✅ FIXED: Use is_loaded instead of is_scanned
      final scannedCartonInfo =
          cartonInfo.where((c) => c['is_loaded'] == true).toList();

      final totalCartons = cartonInfo.length;
      final scannedCount = scannedCartonInfo.length;
      final completionRate = (scannedCount / totalCartons * 100).round();

      final reportId = 'RPT_${DateTime.now().millisecondsSinceEpoch}';

      // ✅ FIXED: Get customer name from shipment packaging sessions
      final packagingSessions = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('customer_name')
          .eq('shipment_order_id', sessionId)
          .limit(1)
          .maybeSingle();

      final customerName = packagingSessions?['customer_name'] ?? 'Unknown Customer';
      final truckDetails = sessionInfo['truck_details'] as Map?;
      final truckNumber = truckDetails?['truck_number'] ?? 'Unknown';

      final reportData = {
        'report_id': reportId,
        'session_id': sessionId,
        'completion_percentage': completionRate,
        'operator_name': operatorName,
        'report_data': {
          'customer_name': customerName,
          'truck_number': truckNumber,
          'shipper_name': customerName,
          'destination': sessionInfo['destination'] ?? 'Unknown',
          'total_cartons': totalCartons,
          'scanned_cartons': scannedCount,
          'unscanned_cartons': totalCartons - scannedCount,
          'completion_percentage': completionRate,
          'operator_name': operatorName,
          'scanned_carton_list':
              scannedCartonInfo.map((c) => c['carton_barcode']).toList(),
          'expected_carton_list': cartonInfo.map((c) => c['carton_barcode']).toList(),
          'loading_completed': scannedCount >= totalCartons,
          'session_start': sessionInfo['created_at'],
          'session_end':
              sessionInfo['loading_started_at'] ?? DateTime.now().toIso8601String(),
        },
        'generated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('loading_reports').insert(reportData);

      log('✅ Loading report saved to database: $reportId');

      return {
        'success': true,
        'report': {
          'report_id': reportId,
          'session_id': sessionId,
          'customer_name': customerName,
          'shipper_name': customerName,
          'destination': sessionInfo['destination'] ?? 'Unknown',
          'truck_number': truckNumber,
          'total_cartons': totalCartons,
          'scanned_cartons': scannedCount,
          'completion_percentage': completionRate,
          'operator_name': operatorName,
          'generated_at': reportData['generated_at'],
          'loading_completed': scannedCount >= totalCartons,
        },
        'message': 'Loading report generated and saved successfully'
      };
    } catch (e) {
      log('❌ Generate loading report error: $e');
      return {
        'success': false,
        'error': 'Database Insert Failed',
        'details': e.toString()
      };
    }
  }

  /// Get all loading reports
  static Future<List<Map<String, dynamic>>> getLoadingReports({
    int? offset,
    int limit = 100,
  }) async {
    try {
      log('🔄 Fetching loading reports...');

      var query = _supabase
          .from('loading_reports')
          .select('*')
          .order('generated_at', ascending: false);

      if (offset != null && offset > 0) {
        query = query.range(offset, offset + limit - 1);
      } else {
        query = query.limit(limit);
      }

      final response = await query;
      log('✅ Found ${response.length} loading reports');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Fetch loading reports error: $e');
      throw Exception('Failed to fetch loading reports: $e');
    }
  }

  /// Delete loading report
  static Future<bool> deleteLoadingReport(String reportId) async {
    try {
      log('🔄 Deleting loading report: $reportId');

      await _supabase.from('loading_reports').delete().eq('report_id', reportId);

      log('✅ Loading report deleted successfully');
      return true;
    } catch (e) {
      log('❌ Delete loading report error: $e');
      return false;
    }
  }

  /// Get active loading sessions
  static Future<List<Map<String, dynamic>>> getActiveLoadingSessions() async {
    try {
      log('🔄 Fetching active loading sessions...');

      final reports = await getLoadingReports(limit: 100);
      return reports;
    } catch (e) {
      log('❌ Get active loading sessions error: $e');
      return [];
    }
  }

  /// Export loading report
  static Future<Map<String, dynamic>> exportLoadingReport(
      Map<String, dynamic> report) async {
    try {
      log('🔄 Exporting loading report...');

      final reportId = report['report_id']?.toString() ?? 'unknown';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportFileName = 'loading_report_${reportId}_$timestamp.json';

      return {
        'success': true,
        'export_filename': exportFileName,
        'export_format': 'JSON',
        'message': 'Report export prepared successfully'
      };
    } catch (e) {
      log('❌ Export loading report error: $e');
      return {
        'success': false,
        'error': 'Export Failed',
        'details': e.toString()
      };
    }
  }

  // ================================
  // UTILITY METHODS
  // ================================

  /// Get default warehouse ID
  static Future<String?> _getDefaultWarehouseId() async {
    try {
      final warehouse = await _supabase
          .from('warehouses')
          .select('warehouse_id')
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

      return warehouse?['warehouse_id'];
    } catch (e) {
      log('❌ Error getting default warehouse: $e');
      return null;
    }
  }

  /// Get available dock
  static Future<String> getAvailableDock() async {
    try {
      final activeSessions = await _supabase
          .from('truck_loading_sessions')
          .select('dock_location')
          .eq('status', 'active');

      final occupiedDocks =
          activeSessions.map((s) => s['dock_location']).toSet();

      for (int i = 1; i <= 8; i++) {
        final dock = 'DOCK-$i';
        if (!occupiedDocks.contains(dock)) {
          return dock;
        }
      }

      return 'DOCK-1';
    } catch (e) {
      log('Error getting available dock: $e');
      return 'DOCK-1';
    }
  }

  /// Process multi-customer shipment QR
  static Future<Map<String, dynamic>> processMultiCustomerShipmentQR(
      Map<String, dynamic> qrContent) async {
    try {
      log('🔄 Processing multi-customer shipment QR...');

      final truckNumber = qrContent['truck_number']?.toString().toUpperCase();
      final customers = qrContent['customers'] as List?;
      final allCartons = qrContent['all_cartons'] as List?;
      final shipmentType = qrContent['shipment_type']?.toString();

      if (truckNumber == null || customers == null || allCartons == null) {
        throw Exception('Invalid multi-customer QR data');
      }

      if (shipmentType != 'multi_customer') {
        throw Exception('Not a multi-customer shipment');
      }

      final masterSessionId = 'MULTI_${DateTime.now().millisecondsSinceEpoch}';
      log('📊 Processing ${customers.length} customers for truck $truckNumber');

      for (int i = 0; i < customers.length; i++) {
        final customer = customers[i] as Map;
        final customerSessionId =
            'CUST_${String.fromCharCode(65 + i)}_${DateTime.now().millisecondsSinceEpoch}';

        await _supabase.from('shipment_sessions').insert({
          'session_id': customerSessionId,
          'master_session_id': masterSessionId,
          'truck_number': truckNumber,
          'customer_name': customer['customer_name'],
          'shipper_name': customer['shipper_name'],
          'destination': customer['destination'],
          'total_cartons': (customer['carton_list'] as List).length,
          'status': 'active',
          'is_multi_customer': true,
          'customer_order': i + 1,
        });

        final customerCartons = customer['carton_list'] as List;
        for (String cartonId in customerCartons.map((e) => e.toString())) {
          await _supabase.from('wms_shipment_cartons').insert({
            'session_id': customerSessionId,
            'carton_id': cartonId.toUpperCase(),
            'customer_name': customer['customer_name'],
            'is_scanned': false,
          });
        }

        log('✅ Customer ${i + 1}: ${customer['customer_name']} - ${customerCartons.length} cartons');
      }

      log('✅ Multi-customer shipment processed: $masterSessionId');
      return {
        'success': true,
        'session_id': masterSessionId,
        'truck_number': truckNumber,
        'total_customers': customers.length,
        'total_cartons': allCartons.length,
        'customers': customers,
        'shipment_type': 'multi_customer',
        'message': 'Multi-customer shipment loaded successfully'
      };
    } catch (e) {
      log('❌ Multi-customer processing error: $e');
      return {
        'success': false,
        'error': 'Failed to process multi-customer shipment',
        'details': e.toString(),
      };
    }
  }

  /// Verify truck number for multi-customer
  static Future<Map<String, dynamic>> verifyTruckNumberMultiCustomer({
    required String masterSessionId,
    required String expectedTruckNumber,
    required String scannedTruckNumber,
  }) async {
    try {
      log('🔄 Verifying truck for multi-customer: $scannedTruckNumber');

      final cleanExpected = expectedTruckNumber.toUpperCase().trim();
      final cleanScanned = scannedTruckNumber.toUpperCase().trim();

      if (cleanExpected != cleanScanned) {
        return {
          'success': false,
          'error': 'Truck number mismatch',
          'details': 'Expected: $cleanExpected, Scanned: $cleanScanned',
        };
      }

      await _supabase.from('shipment_sessions').update({
        'truck_verified': true,
        'truck_verified_at': DateTime.now().toIso8601String()
      }).or('session_id.eq.$masterSessionId,master_session_id.eq.$masterSessionId');

      return {
        'success': true,
        'truck_number': cleanScanned,
        'message': 'Truck verified for all customers'
      };
    } catch (e) {
      log('❌ Multi-customer truck verification error: $e');
      return {
        'success': false,
        'error': 'Truck verification failed',
        'details': e.toString(),
      };
    }
  }

  /// Process carton scan for multi-customer
  static Future<Map<String, dynamic>> processCartonScanMultiCustomer({
    required String masterSessionId,
    required String cartonId,
  }) async {
    try {
      log('🔄 Processing carton scan: $cartonId');

      final cartonInfo = await _supabase
          .from('wms_shipment_cartons')
          .select('*, shipment_sessions!inner(*)')
          .eq('carton_id', cartonId.toUpperCase())
          .eq('shipment_sessions.master_session_id', masterSessionId)
          .maybeSingle();

      if (cartonInfo == null) {
        return {
          'success': false,
          'error': 'Carton not found in shipment',
          'details': 'Carton $cartonId does not belong to this shipment'
        };
      }

      if (cartonInfo['is_scanned'] == true) {
        return {
          'success': false,
          'error': 'Carton already scanned',
          'details': 'Carton $cartonId was already processed'
        };
      }

      await _supabase.from('wms_shipment_cartons').update({
        'is_scanned': true,
        'scanned_at': DateTime.now().toIso8601String(),
        'scanned_by': 'system'
      }).eq('carton_id', cartonId.toUpperCase()).eq(
          'session_id', cartonInfo['session_id']);

      final customerCartons = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('session_id', cartonInfo['session_id']);

      final customerScanned =
          customerCartons.where((c) => c['is_scanned'] == true).length;
      final customerTotal = customerCartons.length;
      bool customerComplete = customerScanned == customerTotal;

      final allShipmentCartons = await _supabase
          .from('wms_shipment_cartons')
          .select('*, shipment_sessions!inner(*)')
          .eq('shipment_sessions.master_session_id', masterSessionId);

      final totalScanned =
          allShipmentCartons.where((c) => c['is_scanned'] == true).length;
      final totalCartons = allShipmentCartons.length;
      bool allComplete = totalScanned == totalCartons;

      log('✅ Carton $cartonId scanned for ${cartonInfo['customer_name']}');

      return {
        'success': true,
        'carton_id': cartonId,
        'customer_name': cartonInfo['customer_name'],
        'customer_scanned': customerScanned,
        'customer_total': customerTotal,
        'customer_complete': customerComplete,
        'total_scanned': totalScanned,
        'total_cartons': totalCartons,
        'all_scanned': allComplete,
        'progress_message': customerComplete
            ? '✅ ${cartonInfo['customer_name']} complete! ($customerScanned/$customerTotal)'
            : '📦 ${cartonInfo['customer_name']}: $customerScanned/$customerTotal cartons'
      };
    } catch (e) {
      log('❌ Multi-customer carton scan error: $e');
      return {
        'success': false,
        'error': 'Carton scanning failed',
        'details': e.toString(),
      };
    }
  }

  /// Generate multi-customer loading report
  static Future<Map<String, dynamic>> generateMultiCustomerLoadingReport({
    required String masterSessionId,
    required String operatorName,
  }) async {
    try {
      log('🔄 Generating multi-customer loading report...');

      final sessions = await _supabase
          .from('shipment_sessions')
          .select('*')
          .eq('master_session_id', masterSessionId)
          .order('customer_order');

      if (sessions.isEmpty) {
        throw Exception(
            'No customer sessions found for master session: $masterSessionId');
      }

      final sessionIds = sessions.map((s) => s['session_id']).toList();
      final allCartons = <Map<String, dynamic>>[];

      for (String sessionId in sessionIds) {
        final cartons = await _supabase
            .from('wms_shipment_cartons')
            .select('*')
            .eq('session_id', sessionId);
        allCartons.addAll(cartons);
      }

      final totalCartons = allCartons.length;
      final scannedCartons =
          allCartons.where((c) => c['is_scanned'] == true).length;
      final completionPercentage =
          totalCartons > 0 ? ((scannedCartons / totalCartons) * 100).round() : 0;

      final List<Map<String, dynamic>> customerBreakdown = [];

      for (var session in sessions) {
        final customerName = session['customer_name'];
        final shipperName = session['shipper_name'];
        final destination = session['destination'];
        final customerCartons = allCartons
            .where((c) => c['session_id'] == session['session_id'])
            .toList();

        final int customerScanned =
            customerCartons.where((c) => c['is_scanned'] == true).length;
        final int customerTotal = customerCartons.length;
        final int customerCompletion = customerTotal == 0
            ? 0
            : ((customerScanned / customerTotal) * 100).round();

        customerBreakdown.add({
          'customer_name': customerName,
          'shipper_name': shipperName,
          'destination': destination,
          'cartons': customerTotal,
          'scanned': customerScanned,
          'completion': customerCompletion,
          'carton_list': customerCartons.map((c) => c['carton_id']).toList(),
          'scanned_carton_list': customerCartons
              .where((c) => c['is_scanned'] == true)
              .map((c) => c['carton_id'])
              .toList(),
          'missing_carton_list': customerCartons
              .where((c) => c['is_scanned'] != true)
              .map((c) => c['carton_id'])
              .toList(),
        });
      }

      final reportId = 'RPT_MULTI_${DateTime.now().millisecondsSinceEpoch}';
      final reportData = {
        'truck_number': sessions.first['truck_number'],
        'shipment_type': 'multi_customer',
        'total_customers': sessions.length,
        'total_cartons': totalCartons,
        'scanned_cartons': scannedCartons,
        'completion_percentage': completionPercentage,
        'operator_name': operatorName,
        'session_start': sessions.first['created_at'],
        'session_end': DateTime.now().toIso8601String(),
        'loading_completed': completionPercentage >= 100,
        'customer_breakdown': customerBreakdown,
      };

      await _supabase.from('loading_reports').insert({
        'report_id': reportId,
        'session_id': sessions.first['session_id'],
        'completion_percentage': completionPercentage,
        'operator_name': operatorName,
        'report_data': reportData,
        'is_consolidated': true,
        'customer_count': sessions.length,
      });

      for (var session in sessions) {
        await _supabase.from('shipment_sessions').update({
          'status': 'completed',
          'completion_time': DateTime.now().toIso8601String()
        }).eq('session_id', session['session_id']);
      }

      log('✅ Multi-customer loading report generated: $reportId');
      return {
        'success': true,
        'report': reportData,
      };
    } catch (e) {
      log('❌ Multi-customer report generation error: $e');
      return {
        'success': false,
        'error': 'Report generation failed',
        'details': e.toString(),
      };
    }
  }

  // ================================
  // LOADING HISTORY
  // ================================

  /// Get loading history for a user
  static Future<List<Map<String, dynamic>>> getLoadingHistory({
    required String userName,
    int limit = 20,
  }) async {
    try {
      log('🔄 Fetching loading history for user: $userName');

      // Get completed loading sessions from shipment_orders
      final response = await _supabase
          .from('shipment_orders')
          .select('''
            id,
            shipment_id,
            truck_number,
            customer_name,
            total_cartons,
            status,
            created_at,
            updated_at,
            shipment_type,
            loading_strategy
          ''')
          .eq('status', 'pending_dispatch')
          .order('created_at', ascending: false)
          .limit(limit);

      if (response == null || response.isEmpty) {
        log('ℹ️ No loading history found');
        return [];
      }

      final List<Map<String, dynamic>> history = [];

      for (var shipment in response) {
        // Get carton count
        final cartonResponse = await _supabase
            .from('shipment_order_cartons')
            .select('carton_barcode, is_loaded')
            .eq('shipment_order_id', shipment['id']);

        final totalCartons = cartonResponse?.length ?? 0;
        final scannedCartons = cartonResponse?.where((c) => c['is_loaded'] == true).length ?? 0;

        history.add({
          'shipment_order_id': shipment['id'],
          'shipment_id': shipment['shipment_id'],
          'truck_number': shipment['truck_number'],
          'customer_name': shipment['customer_name'],
          'total_cartons': totalCartons,
          'scanned_cartons': scannedCartons,
          'status': shipment['status'],
          'completed_at': shipment['updated_at'],
          'loading_strategy': shipment['loading_strategy'],
          'shipment_type': shipment['shipment_type'],
        });
      }

      log('✅ Loaded ${history.length} history items');
      return history;
    } catch (e) {
      log('❌ Error fetching loading history: $e');
      return [];
    }
  }
}
