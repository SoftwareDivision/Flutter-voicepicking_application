// lib/services/single_shipment_service.dart
// ✅ SINGLE CUSTOMER SHIPMENT ORDER (SO) SERVICE
// Handles creation and management of single-customer shipments

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:async';
import '../services/shipment_service.dart';

class SingleShipmentService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const Duration _requestTimeout = Duration(seconds: 30);

  // ================================
  // CREATE SINGLE CUSTOMER SHIPMENT
  // ================================

  /// Creates a draft shipment order from a single packaging session
  /// This is for one customer, one destination
  static Future<Map<String, dynamic>> createFromPackaging({
    required String packagingSessionId,
    required String userName,
  }) async {
    try {
      log('🔄 [SINGLE SO] Creating from packaging: $packagingSessionId');

      // Validate inputs
      if (packagingSessionId.trim().isEmpty) {
        throw Exception('Packaging session ID cannot be empty');
      }

      if (userName.trim().isEmpty) {
        throw Exception('User name cannot be empty');
      }

      // ✅ STEP 1: Get packaging session with customer details
      final sessionResponse = await _supabase
          .from('packaging_sessions')
          .select('*, customer_orders!inner(*)')
          .eq('session_id', packagingSessionId)
          .eq('status', 'completed')
          .maybeSingle()
          .timeout(_requestTimeout);

      if (sessionResponse == null) {
        throw Exception('Packaging session not found or not completed');
      }

      log('📦 [SINGLE SO] Session: ${sessionResponse['order_number']}');

      // ✅ STEP 2: Check if shipment already created
      if (sessionResponse['shipment_order_created'] == true) {
        log('⚠️ [SINGLE SO] Shipment already exists for this session');
        return {
          'success': false,
          'error': 'ALREADY_CREATED',
          'message': 'Shipment order already created for this packaging session',
          'existing_shipment_id': sessionResponse['shipment_order_id'],
        };
      }

      // ✅ STEP 3: Get sealed cartons
      final cartonsResponse = await _supabase
          .from('package_cartons')
          .select('carton_barcode')
          .eq('packaging_session_id', packagingSessionId)
          .eq('status', 'sealed')
          .timeout(_requestTimeout);

      final cartons = cartonsResponse as List;

      if (cartons.isEmpty) {
        throw Exception('No sealed cartons found for this packaging session');
      }

      log('📦 [SINGLE SO] Found ${cartons.length} sealed cartons');

      // ✅ STEP 4: Generate unique shipment ID
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final shipmentId = 'SO-${timestamp.toString().substring(timestamp.toString().length - 8)}';

      // ✅ STEP 5: Extract customer details
      final customerOrders = sessionResponse['customer_orders'] as Map;
      final customerName = customerOrders['customer_name'] ?? 'Unknown Customer';
      final destination = customerOrders['ship_to_address'] ?? '';

      // ✅ STEP 6: Create shipment order (DRAFT status)
      final shipmentData = {
        'shipment_id': shipmentId,
        'order_type': 'single', // ✅ SINGLE customer
        'status': 'draft',
        'destination': destination,
        'total_cartons': cartons.length,
        'warehouse_id': sessionResponse['warehouse_id'],
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
      log('✅ [SINGLE SO] Created: $shipmentId (ID: $shipmentOrderId)');

      // ✅ STEP 7: Link packaging session to shipment
      await _supabase.from('wms_shipment_packaging_sessions').insert({
        'shipment_order_id': shipmentOrderId,
        'packaging_session_id': packagingSessionId,
        'customer_name': customerName,
        'order_number': sessionResponse['order_number'] ?? '',
        'carton_count': cartons.length,
        'created_at': DateTime.now().toIso8601String(),
      }).timeout(_requestTimeout);

      log('✅ [SINGLE SO] Linked packaging session');

      // ✅ STEP 8: Insert cartons into shipment
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

      log('✅ [SINGLE SO] Inserted ${cartonInserts.length} cartons');

      // ✅ STEP 9: Update packaging session to mark shipment created
      await _supabase
          .from('packaging_sessions')
          .update({
            'shipment_order_created': true,
            'shipment_order_id': shipmentOrderId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('session_id', packagingSessionId)
          .timeout(_requestTimeout);

      log('✅ [SINGLE SO] Updated packaging session');

      // ✅ STEP 10: Clear cache
      ShipmentService.clearAllCache();
      
      log('✅✅✅ [SINGLE SO] Creation complete: $shipmentId');
      log('📊 [SINGLE SO] Summary:');
      log('   - Customer: $customerName');
      log('   - Cartons: ${cartons.length}');
      log('   - Destination: $destination');

      return {
        'success': true,
        'shipment_id': shipmentId,
        'shipment_order_id': shipmentOrderId,
        'customer_name': customerName,
        'total_cartons': cartons.length,
        'destination': destination,
        'message': 'Single customer shipment order created successfully',
      };

    } on TimeoutException catch (e) {
      log('❌ [SINGLE SO] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out. Please check your internet connection and try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [SINGLE SO] Database error: ${e.message}');
      log('❌ [SINGLE SO] Error code: ${e.code}');
      log('❌ [SINGLE SO] Error details: ${e.details}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}',
        'details': e.details,
      };
    } catch (e, stackTrace) {
      log('❌ [SINGLE SO] Unexpected error: $e');
      log('❌ [SINGLE SO] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Failed to create single shipment: ${e.toString()}',
      };
    }
  }

  // ================================
  // CONFIGURE SINGLE SHIPMENT
  // ================================

  /// Configures a single customer shipment with delivery details
  /// Moves shipment from DRAFT to PENDING_DISPATCH status
  static Future<Map<String, dynamic>> configure({
    required String shipmentOrderId,
    required ShipmentType shipmentType,
    LoadingStrategy? loadingStrategy,
    Map<String, dynamic>? truckDetails,
    Map<String, dynamic>? courierDetails,
    Map<String, dynamic>? inPersonDetails,
    String? destination,
    String? specialInstructions,
    DateTime? expectedDispatchAt,
  }) async {
    try {
      log('🔄 [SINGLE SO CONFIG] Configuring: $shipmentOrderId');

      // ✅ Validate inputs
      if (shipmentOrderId.trim().isEmpty) {
        throw Exception('Shipment order ID cannot be empty');
      }

      // Validate type-specific details
      if (shipmentType == ShipmentType.truck && truckDetails == null) {
        throw Exception('Truck details are required for truck shipments');
      }

      if (shipmentType == ShipmentType.courier && courierDetails == null) {
        throw Exception('Courier details are required for courier shipments');
      }

      if (shipmentType == ShipmentType.inPerson && inPersonDetails == null) {
        throw Exception('In-person details are required for in-person pickups');
      }

      // ✅ Check if shipment exists and is single customer
      final existingShipment = await _supabase
          .from('wms_shipment_orders')
          .select('status, shipment_id, order_type')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (existingShipment == null) {
        log('❌ [SINGLE SO CONFIG] Shipment not found');
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Shipment not found. It may have been deleted.',
        };
      }

      // ✅ Verify it's a single customer shipment
      if (existingShipment['order_type'] != 'single') {
        throw Exception('This is not a single customer shipment. Use Multi-SO service instead.');
      }

      // ✅ Check status (allow draft or pending_dispatch for editing)
      final currentStatus = existingShipment['status'];
      if (currentStatus != 'draft' && currentStatus != 'pending_dispatch') {
        throw Exception('Only draft or pending shipments can be configured. Current status: $currentStatus');
      }

      log('📋 [SINGLE SO CONFIG] Current status: $currentStatus');

      // ✅ Prepare update data
      final updateData = {
        'status': 'pending_dispatch', // Move to pending after configuration
        'shipment_type': shipmentType.name,
        'loading_strategy': loadingStrategy != null 
            ? (loadingStrategy == LoadingStrategy.lifo ? 'lifo' : 'non_lifo')
            : null,
        'truck_details': truckDetails,
        'courier_details': courierDetails,
        'in_person_details': inPersonDetails,
        'destination': destination,
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
      
      log('✅ [SINGLE SO CONFIG] Configuration saved for: ${existingShipment['shipment_id']}');
      log('📊 [SINGLE SO CONFIG] Details:');
      log('   - Type: ${shipmentType.name}');
      log('   - Strategy: ${loadingStrategy?.name ?? "not set"}');
      log('   - Status: pending_dispatch');

      return {
        'success': true,
        'message': 'Single customer shipment configured successfully',
        'shipment_id': existingShipment['shipment_id'],
      };

    } on TimeoutException catch (e) {
      log('❌ [SINGLE SO CONFIG] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out. Please try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [SINGLE SO CONFIG] Database error: ${e.message}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}',
      };
    } catch (e, stackTrace) {
      log('❌ [SINGLE SO CONFIG] Error: $e');
      log('❌ [SINGLE SO CONFIG] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': e.toString(),
      };
    }
  }

  // ================================
  // GET SINGLE SHIPMENT DETAILS
  // ================================

  /// Gets detailed information about a single customer shipment
  static Future<Map<String, dynamic>> getDetails({
    required String shipmentOrderId,
  }) async {
    try {
      log('🔍 [SINGLE SO] Fetching details: $shipmentOrderId');

      // Get shipment with customer info
      final shipment = await _supabase
          .from('wms_shipment_orders_with_customers')
          .select('*')
          .eq('id', shipmentOrderId)
          .eq('order_type', 'single')
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipment == null) {
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Single customer shipment not found',
        };
      }

      // Get cartons
      final cartons = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      // Get packaging session
      final session = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      log('✅ [SINGLE SO] Details retrieved');

      return {
        'success': true,
        'shipment': shipment,
        'cartons': cartons,
        'session': session,
        'total_cartons': (cartons as List).length,
      };

    } catch (e) {
      log('❌ [SINGLE SO] Error fetching details: $e');
      return {
        'success': false,
        'error': 'FETCH_ERROR',
        'message': e.toString(),
      };
    }
  }
}
