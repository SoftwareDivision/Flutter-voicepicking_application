// lib/services/multi_shipment_service.dart
// ✅ MULTI-CUSTOMER SHIPMENT ORDER (MSO) SERVICE
// Handles creation and management of consolidated multi-customer shipments

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:async';
import '../services/shipment_service.dart';

class MultiShipmentService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const Duration _requestTimeout = Duration(seconds: 30);

  // ================================
  // CREATE MULTI-CUSTOMER SHIPMENT
  // ================================

  /// Creates a consolidated shipment order from multiple packaging sessions
  /// This is for multiple customers sharing one truck/delivery
  static Future<Map<String, dynamic>> createFromPackagingSessions({
    required List<String> packagingSessionIds,
    required String userName,
  }) async {
    try {
      log('🔄 [MULTI SO] Creating MSO with ${packagingSessionIds.length} sessions');

      // ✅ STEP 1: Validate inputs
      if (packagingSessionIds.isEmpty) {
        throw Exception('At least one packaging session is required');
      }

      if (packagingSessionIds.length < 2) {
        throw Exception('Multi-customer shipment requires at least 2 packaging sessions. Use Single SO service for one customer.');
      }

      if (userName.trim().isEmpty) {
        throw Exception('User name cannot be empty');
      }

      // ✅ STEP 2: Get all packaging sessions with customer details
      final sessionsResponse = await _supabase
          .from('packaging_sessions')
          .select('*, customer_orders!inner(*)')
          .inFilter('session_id', packagingSessionIds)
          .eq('status', 'completed')
          .timeout(_requestTimeout);

      final sessions = sessionsResponse as List;

      if (sessions.isEmpty) {
        throw Exception('No completed packaging sessions found');
      }

      if (sessions.length != packagingSessionIds.length) {
        throw Exception('Some packaging sessions not found or not completed. Expected ${packagingSessionIds.length}, found ${sessions.length}');
      }

      log('📦 [MULTI SO] Found ${sessions.length} packaging sessions');

      // ✅ STEP 3: Validate all sessions are available (not already in a shipment)
      for (var session in sessions) {
        if (session['shipment_order_created'] == true) {
          final sessionId = session['session_id'];
          final orderNumber = session['order_number'];
          throw Exception('Session $orderNumber ($sessionId) already has a shipment order');
        }
      }

      log('✅ [MULTI SO] All sessions available');

      // ✅ STEP 4: Count total cartons across all sessions
      int totalCartons = 0;
      final Map<String, int> cartonsBySession = {};
      
      for (var session in sessions) {
        final sessionId = session['session_id'];
        final cartonsResponse = await _supabase
            .from('package_cartons')
            .select('carton_barcode')
            .eq('packaging_session_id', sessionId)
            .eq('status', 'sealed')
            .timeout(_requestTimeout);
        
        final cartonCount = (cartonsResponse as List).length;
        totalCartons += cartonCount;
        cartonsBySession[sessionId] = cartonCount;
      }

      if (totalCartons == 0) {
        throw Exception('No sealed cartons found in any packaging session');
      }

      log('📦 [MULTI SO] Total cartons: $totalCartons across ${sessions.length} customers');

      // ✅ STEP 5: Generate unique MSO shipment ID
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final shipmentId = 'MSO-${timestamp.toString().substring(timestamp.toString().length - 8)}';

      // ✅ STEP 6: Collect all destinations for reference
      final destinations = sessions
          .map((s) => (s['customer_orders'] as Map)['ship_to_address'] ?? 'Unknown')
          .toSet()
          .join('; ');

      // ✅ STEP 7: Create multi-customer shipment order (DRAFT status)
      final shipmentData = {
        'shipment_id': shipmentId,
        'order_type': 'multi', // ✅ MULTI customer
        'status': 'draft',
        'destination': 'Multiple Destinations', // MSO has multiple destinations
        'total_cartons': totalCartons,
        'warehouse_id': sessions.first['warehouse_id'],
        'created_by': userName,
        'slip_generated': false,
        'created_at': DateTime.now().toIso8601String(),
      };

      final shipmentResponse = await _supabase
          .from('wms_shipment_orders')
          .insert(shipmentData)
          .select()
          .single()
          .timeout(_requestTimeout);

      final shipmentOrderId = shipmentResponse['id'];
      log('✅ [MULTI SO] Created: $shipmentId (ID: $shipmentOrderId)');

      // ✅ STEP 8: Link all packaging sessions to the MSO
      int sessionIndex = 0;
      for (var session in sessions) {
        sessionIndex++;
        final sessionId = session['session_id'];
        final customerOrders = session['customer_orders'] as Map;
        final customerName = customerOrders['customer_name'] ?? 'Unknown Customer';
        final orderNumber = session['order_number'] ?? '';
        final cartonCount = cartonsBySession[sessionId] ?? 0;

        await _supabase.from('wms_shipment_packaging_sessions').insert({
          'shipment_order_id': shipmentOrderId,
          'packaging_session_id': sessionId,
          'customer_name': customerName,
          'order_number': orderNumber,
          'carton_count': cartonCount,
          'created_at': DateTime.now().toIso8601String(),
        }).timeout(_requestTimeout);

        log('✅ [MULTI SO] Linked session $sessionIndex: $customerName ($cartonCount cartons)');
      }

      // ✅ STEP 9: Insert all cartons from all sessions
      int totalInserted = 0;
      for (var session in sessions) {
        final sessionId = session['session_id'];
        final customerOrders = session['customer_orders'] as Map;
        final customerName = customerOrders['customer_name'] ?? 'Unknown Customer';

        // Get cartons for this session
        final cartonsResponse = await _supabase
            .from('package_cartons')
            .select('carton_barcode')
            .eq('packaging_session_id', sessionId)
            .eq('status', 'sealed')
            .timeout(_requestTimeout);

        final cartons = cartonsResponse as List;

        if (cartons.isNotEmpty) {
          final cartonInserts = cartons.map((c) => {
            'shipment_order_id': shipmentOrderId,
            'carton_barcode': c['carton_barcode'],
            'customer_name': customerName,
            'is_loaded': false,
            'created_at': DateTime.now().toIso8601String(),
          }).toList();

          await _supabase
              .from('wms_shipment_cartons')
              .insert(cartonInserts)
              .timeout(_requestTimeout);

          totalInserted += cartonInserts.length;
          log('✅ [MULTI SO] Inserted ${cartonInserts.length} cartons for $customerName');
        }
      }

      log('✅ [MULTI SO] Total cartons inserted: $totalInserted');

      // ✅ STEP 10: Update all packaging sessions to mark shipment created
      for (var session in sessions) {
        await _supabase
            .from('packaging_sessions')
            .update({
              'shipment_order_created': true,
              'shipment_order_id': shipmentOrderId,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('session_id', session['session_id'])
            .timeout(_requestTimeout);
      }

      log('✅ [MULTI SO] Updated all packaging sessions');

      // ✅ STEP 11: Clear cache
      ShipmentService.clearAllCache();
      
      log('✅✅✅ [MULTI SO] Creation complete: $shipmentId');
      log('📊 [MULTI SO] Summary:');
      log('   - Customers: ${sessions.length}');
      log('   - Total Cartons: $totalCartons');
      log('   - Sessions: ${packagingSessionIds.join(", ")}');

      return {
        'success': true,
        'shipment_id': shipmentId,
        'shipment_order_id': shipmentOrderId,
        'customer_count': sessions.length,
        'total_cartons': totalCartons,
        'sessions': sessions.map((s) => {
          'session_id': s['session_id'],
          'customer_name': (s['customer_orders'] as Map)['customer_name'],
          'order_number': s['order_number'],
          'carton_count': cartonsBySession[s['session_id']],
        }).toList(),
        'message': 'Multi-customer shipment order created successfully',
      };

    } on TimeoutException catch (e) {
      log('❌ [MULTI SO] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out. Please check your internet connection and try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [MULTI SO] Database error: ${e.message}');
      log('❌ [MULTI SO] Error code: ${e.code}');
      log('❌ [MULTI SO] Error details: ${e.details}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}',
        'details': e.details,
      };
    } catch (e, stackTrace) {
      log('❌ [MULTI SO] Unexpected error: $e');
      log('❌ [MULTI SO] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Failed to create multi-customer shipment: ${e.toString()}',
      };
    }
  }

  // ================================
  // CONFIGURE MULTI-CUSTOMER SHIPMENT
  // ================================

  /// Configures a multi-customer shipment with delivery details
  /// Moves shipment from DRAFT to PENDING_DISPATCH status
  static Future<Map<String, dynamic>> configure({
    required String shipmentOrderId,
    required ShipmentType shipmentType,
    LoadingStrategy? loadingStrategy,
    Map<String, dynamic>? truckDetails,
    Map<String, dynamic>? courierDetails,
    String? specialInstructions,
    DateTime? expectedDispatchAt,
  }) async {
    try {
      log('🔄 [MULTI SO CONFIG] Configuring: $shipmentOrderId');

      // ✅ Validate inputs
      if (shipmentOrderId.trim().isEmpty) {
        throw Exception('Shipment order ID cannot be empty');
      }

      // MSO typically uses trucks (not in-person pickup)
      if (shipmentType == ShipmentType.truck && truckDetails == null) {
        throw Exception('Truck details are required for truck shipments');
      }

      if (shipmentType == ShipmentType.courier && courierDetails == null) {
        throw Exception('Courier details are required for courier shipments');
      }

      // ✅ Check if shipment exists and is multi-customer
      final existingShipment = await _supabase
          .from('wms_shipment_orders')
          .select('status, shipment_id, order_type, total_cartons')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (existingShipment == null) {
        log('❌ [MULTI SO CONFIG] Shipment not found');
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Shipment not found. It may have been deleted.',
        };
      }

      // ✅ Verify it's a multi-customer shipment
      if (existingShipment['order_type'] != 'multi') {
        throw Exception('This is not a multi-customer shipment. Use Single SO service instead.');
      }

      // ✅ Check status
      final currentStatus = existingShipment['status'];
      if (currentStatus != 'draft' && currentStatus != 'pending_dispatch') {
        throw Exception('Only draft or pending shipments can be configured. Current status: $currentStatus');
      }

      log('📋 [MULTI SO CONFIG] Current status: $currentStatus');

      // ✅ Get customer count
      final sessionsCount = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('id')
          .eq('shipment_order_id', shipmentOrderId)
          .count();

      log('📊 [MULTI SO CONFIG] Customers: ${sessionsCount.count}, Cartons: ${existingShipment['total_cartons']}');

      // ✅ Prepare update data
      final updateData = {
        'status': 'pending_dispatch',
        'shipment_type': shipmentType.name,
        'loading_strategy': loadingStrategy != null 
            ? (loadingStrategy == LoadingStrategy.lifo ? 'lifo' : 'non_lifo')
            : 'non_lifo', // Default for MSO
        'truck_details': truckDetails,
        'courier_details': courierDetails,
        'special_instructions': specialInstructions,
        'expected_dispatch_at': expectedDispatchAt?.toIso8601String(),
        'configured_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // ✅ Update shipment
      await _supabase
          .from('wms_shipment_orders')
          .update(updateData)
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);

      // ✅ Clear cache
      ShipmentService.clearAllCache();
      
      log('✅ [MULTI SO CONFIG] Configuration saved for: ${existingShipment['shipment_id']}');
      log('📊 [MULTI SO CONFIG] Details:');
      log('   - Type: ${shipmentType.name}');
      log('   - Strategy: ${loadingStrategy?.name ?? "non_lifo"}');
      log('   - Customers: ${sessionsCount.count}');
      log('   - Status: pending_dispatch');

      return {
        'success': true,
        'message': 'Multi-customer shipment configured successfully',
        'shipment_id': existingShipment['shipment_id'],
        'customer_count': sessionsCount.count,
      };

    } on TimeoutException catch (e) {
      log('❌ [MULTI SO CONFIG] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out. Please try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [MULTI SO CONFIG] Database error: ${e.message}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}',
      };
    } catch (e, stackTrace) {
      log('❌ [MULTI SO CONFIG] Error: $e');
      log('❌ [MULTI SO CONFIG] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': e.toString(),
      };
    }
  }

  // ================================
  // GET MULTI-CUSTOMER SHIPMENT DETAILS
  // ================================

  /// Gets detailed information about a multi-customer shipment
  static Future<Map<String, dynamic>> getDetails({
    required String shipmentOrderId,
  }) async {
    try {
      log('🔍 [MULTI SO] Fetching details: $shipmentOrderId');

      // Get shipment
      final shipment = await _supabase
          .from('wms_shipment_orders')
          .select('*')
          .eq('id', shipmentOrderId)
          .eq('order_type', 'multi')
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipment == null) {
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Multi-customer shipment not found',
        };
      }

      // Get all packaging sessions (customers)
      final sessions = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      // Get all cartons grouped by customer
      final cartons = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .order('customer_name')
          .timeout(_requestTimeout);

      // Group cartons by customer
      final Map<String, List<Map>> cartonsByCustomer = {};
      for (var carton in cartons as List) {
        final customerName = carton['customer_name'] as String;
        cartonsByCustomer[customerName] ??= [];
        cartonsByCustomer[customerName]!.add(carton as Map);
      }

      log('✅ [MULTI SO] Details retrieved');
      log('📊 [MULTI SO] ${sessions.length} customers, ${cartons.length} total cartons');

      return {
        'success': true,
        'shipment': shipment,
        'sessions': sessions,
        'cartons': cartons,
        'cartons_by_customer': cartonsByCustomer,
        'customer_count': (sessions as List).length,
        'total_cartons': cartons.length,
      };

    } catch (e) {
      log('❌ [MULTI SO] Error fetching details: $e');
      return {
        'success': false,
        'error': 'FETCH_ERROR',
        'message': e.toString(),
      };
    }
  }

  // ================================
  // GET AVAILABLE SESSIONS FOR MSO
  // ================================

  /// Gets all completed packaging sessions that are available for MSO consolidation
  /// Excludes sessions that already have shipment orders
  static Future<List<Map<String, dynamic>>> getAvailableSessions() async {
    try {
      log('🔍 [MULTI SO] Fetching available packaging sessions');

      final sessions = await _supabase
          .from('packaging_sessions')
          .select('*, customer_orders!inner(*)')
          .eq('status', 'completed')
          .eq('shipment_order_created', false)
          .order('completed_at', ascending: false)
          .timeout(_requestTimeout);

      log('✅ [MULTI SO] Found ${(sessions as List).length} available sessions');

      return (sessions as List).map((s) => s as Map<String, dynamic>).toList();

    } catch (e) {
      log('❌ [MULTI SO] Error fetching available sessions: $e');
      return [];
    }
  }
}
