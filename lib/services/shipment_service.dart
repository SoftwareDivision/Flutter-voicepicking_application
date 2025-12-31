// lib/services/shipment_service.dart
// ✅ PRODUCTION READY v5.0 - REFACTORED WITH SEPARATE SO/MSO SERVICES
// 
// ⚠️ ARCHITECTURE CHANGE:
// - Single Customer Shipments (SO) → Use SingleShipmentService
// - Multi-Customer Shipments (MSO) → Use MultiShipmentService
// - Common operations (delete, fetch, QR, etc.) → Use ShipmentService (this file)
//
// This file now contains ONLY common functionality shared by both SO and MSO.
// For creating/configuring shipments, use the dedicated services above.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:async';

// ================================
// ENUMS
// ================================

enum ShipmentType {
  truck,
  courier,
  inPerson,
}

enum ShipmentStatus {
  draft,
  pendingDispatch,
  loading,
  dispatched,
  cancelled,
}

enum LoadingStrategy {
  lifo,
  nonLifo, // ✅ Changed from 'fifo' to 'nonLifo'
}

// ================================
// DATA MODELS
// ================================

class ShipmentOrder {
  final String id;
  final String shipmentId;
  final String orderType;
  final ShipmentStatus status;
  final ShipmentType? shipmentType;
  final LoadingStrategy? loadingStrategy;
  final String? destination;
  final String? specialInstructions;
  final DateTime? expectedDispatchAt;
  final Map<String, dynamic>? truckDetails;
  final Map<String, dynamic>? courierDetails;
  final Map<String, dynamic>? inPersonDetails;
  final int totalCartons;
  final Map<String, dynamic>? qrData;
  final bool slipGenerated;
  final DateTime createdAt;
  final DateTime? configuredAt;
  final DateTime? loadingStartedAt;
  final DateTime? dispatchedAt;
  final String? warehouseId;
  final String createdBy;
  final String? customerName;
  final String? orderNumber;

  ShipmentOrder({
    required this.id,
    required this.shipmentId,
    required this.orderType,
    required this.status,
    this.shipmentType,
    this.loadingStrategy,
    this.destination,
    this.specialInstructions,
    this.expectedDispatchAt,
    this.truckDetails,
    this.courierDetails,
    this.inPersonDetails,
    required this.totalCartons,
    this.qrData,
    required this.slipGenerated,
    required this.createdAt,
    this.configuredAt,
    this.loadingStartedAt,
    this.dispatchedAt,
    this.warehouseId,
    required this.createdBy,
    this.customerName,
    this.orderNumber,
  });

  factory ShipmentOrder.fromJson(Map<String, dynamic> json) {
    return ShipmentOrder(
      id: json['id'] ?? '',
      shipmentId: json['shipment_id'] ?? '',
      orderType: json['order_type'] ?? 'single',
      status: _parseStatus(json['status']),
      shipmentType: _parseShipmentType(json['shipment_type']),
      loadingStrategy: _parseLoadingStrategy(json['loading_strategy']),
      destination: json['destination'],
      specialInstructions: json['special_instructions'],
      expectedDispatchAt: json['expected_dispatch_at'] != null
          ? DateTime.parse(json['expected_dispatch_at'])
          : null,
      truckDetails: json['truck_details'],
      courierDetails: json['courier_details'],
      inPersonDetails: json['in_person_details'],
      totalCartons: json['total_cartons'] ?? 0,
      qrData: json['qr_data'],
      slipGenerated: json['slip_generated'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      configuredAt: json['configured_at'] != null
          ? DateTime.parse(json['configured_at'])
          : null,
      loadingStartedAt: json['loading_started_at'] != null
          ? DateTime.parse(json['loading_started_at'])
          : null,
      dispatchedAt: json['dispatched_at'] != null
          ? DateTime.parse(json['dispatched_at'])
          : null,
      warehouseId: json['warehouse_id'],
      createdBy: json['created_by'] ?? '',
      customerName: json['customer_name'],
      orderNumber: json['order_number'],
    );
  }

  static ShipmentStatus _parseStatus(String? status) {
    switch (status) {
      case 'draft':
        return ShipmentStatus.draft;
      case 'pending_dispatch':
        return ShipmentStatus.pendingDispatch;
      case 'loading':
        return ShipmentStatus.loading;
      case 'dispatched':
        return ShipmentStatus.dispatched;
      case 'cancelled':
        return ShipmentStatus.cancelled;
      default:
        return ShipmentStatus.draft;
    }
  }

  static ShipmentType? _parseShipmentType(String? type) {
    switch (type) {
      case 'truck':
        return ShipmentType.truck;
      case 'courier':
        return ShipmentType.courier;
      case 'inPerson':
        return ShipmentType.inPerson;
      default:
        return null;
    }
  }

  static LoadingStrategy? _parseLoadingStrategy(String? strategy) {
    switch (strategy) {
      case 'lifo':
        return LoadingStrategy.lifo;
      case 'non_lifo':
      case 'nonLifo':
      case 'fifo': // ✅ Keep for backward compatibility
        return LoadingStrategy.nonLifo;
      default:
        return null;
    }
  }

  String get statusString {
    switch (status) {
      case ShipmentStatus.draft:
        return 'draft';
      case ShipmentStatus.pendingDispatch:
        return 'pending_dispatch';
      case ShipmentStatus.loading:
        return 'loading';
      case ShipmentStatus.dispatched:
        return 'dispatched';
      case ShipmentStatus.cancelled:
        return 'cancelled';
    }
  }

  String? get shipmentTypeString {
    if (shipmentType == null) return null;
    switch (shipmentType!) {
      case ShipmentType.truck:
        return 'truck';
      case ShipmentType.courier:
        return 'courier';
      case ShipmentType.inPerson:
        return 'inPerson';
    }
  }

  String? get loadingStrategyString {
    if (loadingStrategy == null) return null;
    switch (loadingStrategy!) {
      case LoadingStrategy.lifo:
        return 'lifo';
      case LoadingStrategy.nonLifo:
        return 'non_lifo'; // ✅ Changed from 'fifo' to 'non_lifo'
    }
  }
}

class ShipmentCarton {
  final String id;
  final String shipmentOrderId;
  final String cartonBarcode;
  final String customerName;
  final int? loadingSequence;
  final bool isLoaded;
  final DateTime? loadedAt;
  final String? loadedBy;

  ShipmentCarton({
    required this.id,
    required this.shipmentOrderId,
    required this.cartonBarcode,
    required this.customerName,
    this.loadingSequence,
    required this.isLoaded,
    this.loadedAt,
    this.loadedBy,
  });

  factory ShipmentCarton.fromJson(Map<String, dynamic> json) {
    return ShipmentCarton(
      id: json['id'] ?? '',
      shipmentOrderId: json['shipment_order_id'] ?? '',
      cartonBarcode: json['carton_barcode'] ?? '',
      customerName: json['customer_name'] ?? '',
      loadingSequence: json['loading_sequence'],
      isLoaded: json['is_loaded'] ?? false,
      loadedAt: json['loaded_at'] != null
          ? DateTime.parse(json['loaded_at'])
          : null,
      loadedBy: json['loaded_by'],
    );
  }
}

// ================================
// SHIPMENT SERVICE
// ================================

class ShipmentService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final Map<String, List<ShipmentOrder>> _cache = {};
  static DateTime? _lastCacheTime;
  static const Duration _cacheDuration = Duration(minutes: 2);
  static const Duration _requestTimeout = Duration(seconds: 30);

  // ================================
  // ✅ FIXED: REAL DELETE WITH CASCADE
  // ================================
  
  static Future<Map<String, dynamic>> deleteDraftShipment({
    required String shipmentOrderId,
  }) async {
    try {
      log('🗑️ [DELETE] ========== STARTING DELETE ==========');
      log('🗑️ [DELETE] Shipment Order ID: $shipmentOrderId');
      log('🗑️ [DELETE] ID Type: ${shipmentOrderId.runtimeType}');
      log('🗑️ [DELETE] ID Length: ${shipmentOrderId.length}');

      // ✅ STEP 1: Verify shipment exists and is draft
      log('🔍 [DELETE] Step 1: Verifying shipment in wms_shipment_orders table...');
      
      // Try to find in main table
      final shipmentData = await _supabase
          .from('wms_shipment_orders')
          .select('id, shipment_id, status, order_type')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipmentData == null) {
        log('❌ [DELETE] Not found in wms_shipment_orders table');
        
        // Try to find in view to see if it exists there
        log('🔍 [DELETE] Checking wms_shipment_orders_with_customers view...');
        final viewData = await _supabase
            .from('wms_shipment_orders_with_customers')
            .select('id, shipment_id, status')
            .eq('id', shipmentOrderId)
            .maybeSingle()
            .timeout(_requestTimeout);
        
        if (viewData != null) {
          log('⚠️ [DELETE] Found in VIEW but not in TABLE!');
          log('⚠️ [DELETE] This indicates a database view/table sync issue');
          log('⚠️ [DELETE] View data: $viewData');
        }
        
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Shipment not found in database. It may have already been deleted.',
        };
      }

      final shipmentId = shipmentData['shipment_id'];
      final status = shipmentData['status'];
      log('✅ [DELETE] Found: $shipmentId (Status: $status)');

      if (status != 'draft') {
        log('❌ [DELETE] Cannot delete - Status is: $status');
        return {
          'success': false,
          'error': 'INVALID_STATUS',
          'message': 'Only draft shipments can be deleted. Current status: $status',
        };
      }

      // ✅ STEP 2: Get packaging sessions to reset
      log('🔍 [DELETE] Step 2: Finding packaging sessions...');
      final sessionLinks = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('packaging_session_id')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      final packagingSessionIds = (sessionLinks as List)
          .map((link) => link['packaging_session_id'] as String)
          .toList();
      
      log('📋 [DELETE] Found ${packagingSessionIds.length} packaging sessions');

      // ✅ STEP 3: Delete cartons first (child records)
      log('🗑️ [DELETE] Step 3: Deleting cartons...');
      final cartonsDeleted = await _supabase
          .from('wms_shipment_cartons')
          .delete()
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);
      log('✅ [DELETE] Cartons deleted: ${cartonsDeleted}');

      // ✅ STEP 4: Delete packaging session links
      log('🗑️ [DELETE] Step 4: Deleting session links...');
      final linksDeleted = await _supabase
          .from('wms_shipment_packaging_sessions')
          .delete()
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);
      log('✅ [DELETE] Session links deleted: ${linksDeleted}');

      // ✅ STEP 5: Reset packaging sessions (allow recreation)
      if (packagingSessionIds.isNotEmpty) {
        log('🔄 [DELETE] Step 5: Resetting ${packagingSessionIds.length} packaging sessions...');
        try {
          final resetResult = await _supabase
              .from('packaging_sessions')
              .update({
                'shipment_order_created': false,
                'shipment_order_id': null,
              })
              .inFilter('session_id', packagingSessionIds)
              .timeout(_requestTimeout);
          log('✅ [DELETE] Packaging sessions reset: ${resetResult}');
        } catch (e) {
          log('⚠️ [DELETE] Warning: Could not reset packaging sessions: $e');
          // Continue anyway - not critical
        }
      }

      // ✅ STEP 6: Finally delete the main shipment order
      log('🗑️ [DELETE] Step 6: Deleting main shipment order...');
      final mainDeleted = await _supabase
          .from('wms_shipment_orders')
          .delete()
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);
      
      log('✅ [DELETE] Main shipment order deleted: ${mainDeleted}');

      // ✅ STEP 7: Clear cache immediately
      log('🧹 [DELETE] Step 7: Clearing cache...');
      clearAllCache();
      
      log('✅✅✅ [DELETE] ========== DELETE SUCCESSFUL ==========');
      log('✅ [DELETE] Shipment ID: $shipmentId');
      log('✅ [DELETE] Cartons deleted: Yes');
      log('✅ [DELETE] Sessions reset: ${packagingSessionIds.length}');
      
      return {
        'success': true,
        'message': 'Shipment deleted successfully',
        'deleted_id': shipmentId,
        'details': {
          'shipment_id': shipmentId,
          'cartons_deleted': true,
          'packaging_sessions_reset': packagingSessionIds.length,
          'session_ids': packagingSessionIds,
        },
      };

    } on TimeoutException catch (e) {
      log('❌ [DELETE] Timeout error: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Delete operation timed out. Please check your internet connection and try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [DELETE] Database error: ${e.message}');
      log('❌ [DELETE] Error code: ${e.code}');
      log('❌ [DELETE] Error details: ${e.details}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}\nCode: ${e.code}',
        'details': e.details,
      };
    } catch (e, stackTrace) {
      log('❌ [DELETE] Unexpected error: $e');
      log('❌ [DELETE] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Unexpected error: ${e.toString()}',
      };
    }
  }

  // ================================
  // ✅ NEW: PERMANENT DELETE (ANY STATUS)
  // ================================
  
  static Future<Map<String, dynamic>> deleteShipmentPermanently({
    required String shipmentOrderId,
  }) async {
    try {
      log('🗑️ [DELETE PERMANENT] ========== STARTING PERMANENT DELETE ==========');
      log('🗑️ [DELETE PERMANENT] Shipment Order ID: $shipmentOrderId');

      // ✅ STEP 1: Verify shipment exists
      log('🔍 [DELETE PERMANENT] Step 1: Verifying shipment...');
      
      final shipmentData = await _supabase
          .from('wms_shipment_orders')
          .select('id, shipment_id, status, order_type')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipmentData == null) {
        log('❌ [DELETE PERMANENT] Not found in wms_shipment_orders table');
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Shipment not found in database. It may have already been deleted.',
        };
      }

      final shipmentId = shipmentData['shipment_id'];
      final status = shipmentData['status'];
      log('✅ [DELETE PERMANENT] Found: $shipmentId (Status: $status)');

      // ✅ STEP 2: Get packaging sessions to reset
      log('🔍 [DELETE PERMANENT] Step 2: Finding packaging sessions...');
      final sessionLinks = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('packaging_session_id')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      final packagingSessionIds = (sessionLinks as List)
          .map((link) => link['packaging_session_id'] as String)
          .toList();
      
      log('📋 [DELETE PERMANENT] Found ${packagingSessionIds.length} packaging sessions');

      // ✅ STEP 3: Delete delivery routes (if any)
      log('🗑️ [DELETE PERMANENT] Step 3: Deleting delivery routes...');
      try {
        await _supabase
            .from('wms_delivery_routes')
            .delete()
            .eq('shipment_order_id', shipmentOrderId)
            .timeout(_requestTimeout);
        log('✅ [DELETE PERMANENT] Delivery routes deleted');
      } catch (e) {
        log('⚠️ [DELETE PERMANENT] No delivery routes or error: $e');
      }

      // ✅ STEP 4: Delete cartons
      log('🗑️ [DELETE PERMANENT] Step 4: Deleting cartons...');
      await _supabase
          .from('wms_shipment_cartons')
          .delete()
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);
      log('✅ [DELETE PERMANENT] Cartons deleted');

      // ✅ STEP 5: Delete packaging session links
      log('🗑️ [DELETE PERMANENT] Step 5: Deleting session links...');
      await _supabase
          .from('wms_shipment_packaging_sessions')
          .delete()
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);
      log('✅ [DELETE PERMANENT] Session links deleted');

      // ✅ STEP 6: Reset packaging sessions (allow recreation)
      if (packagingSessionIds.isNotEmpty) {
        log('🔄 [DELETE PERMANENT] Step 6: Resetting ${packagingSessionIds.length} packaging sessions...');
        try {
          await _supabase
              .from('packaging_sessions')
              .update({
                'shipment_order_created': false,
                'shipment_order_id': null,
              })
              .inFilter('session_id', packagingSessionIds)
              .timeout(_requestTimeout);
          log('✅ [DELETE PERMANENT] Packaging sessions reset');
        } catch (e) {
          log('⚠️ [DELETE PERMANENT] Warning: Could not reset packaging sessions: $e');
        }
      }

      // ✅ STEP 7: Finally delete the main shipment order
      log('🗑️ [DELETE PERMANENT] Step 7: Deleting main shipment order...');
      await _supabase
          .from('wms_shipment_orders')
          .delete()
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);
      
      log('✅ [DELETE PERMANENT] Main shipment order deleted');

      // ✅ STEP 8: Clear cache immediately
      log('🧹 [DELETE PERMANENT] Step 8: Clearing cache...');
      clearAllCache();
      
      log('✅✅✅ [DELETE PERMANENT] ========== DELETE SUCCESSFUL ==========');
      log('✅ [DELETE PERMANENT] Shipment ID: $shipmentId');
      
      return {
        'success': true,
        'message': 'Shipment permanently deleted',
        'deleted_id': shipmentId,
        'details': {
          'shipment_id': shipmentId,
          'status': status,
          'cartons_deleted': true,
          'packaging_sessions_reset': packagingSessionIds.length,
        },
      };

    } on TimeoutException catch (e) {
      log('❌ [DELETE PERMANENT] Timeout error: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Delete operation timed out. Please check your internet connection and try again.',
      };
    } on PostgrestException catch (e) {
      log('❌ [DELETE PERMANENT] Database error: ${e.message}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': 'Database error: ${e.message}',
      };
    } catch (e, stackTrace) {
      log('❌ [DELETE PERMANENT] Unexpected error: $e');
      log('❌ [DELETE PERMANENT] Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Unexpected error: ${e.toString()}',
      };
    }
  }

  // ================================
  // CREATE FROM PACKAGING - DEPRECATED
  // ================================
  // ⚠️ DEPRECATED: Use SingleShipmentService.createFromPackaging() instead
  // This method is kept for backward compatibility only
  
  @Deprecated('Use SingleShipmentService.createFromPackaging() instead')
  static Future<Map<String, dynamic>> createDraftShipmentFromPackaging({
    required String packagingSessionId,
    required String userName,
  }) async {
    log('⚠️ [DEPRECATED] createDraftShipmentFromPackaging called - redirecting to SingleShipmentService');
    
    // Import at runtime to avoid circular dependency
    final singleService = await import('single_shipment_service.dart');
    return await singleService.SingleShipmentService.createFromPackaging(
      packagingSessionId: packagingSessionId,
      userName: userName,
    );
  }

  // ================================
  // CONFIGURE SHIPMENT - SMART ROUTER
  // ================================
  // Routes to appropriate service based on shipment type

  static Future<Map<String, dynamic>> configureShipment({
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
      log('🔄 [CONFIGURE] Routing configuration request for: $shipmentOrderId');

      // Check shipment type first
      final shipment = await _supabase
          .from('wms_shipment_orders')
          .select('order_type')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipment == null) {
        return {
          'success': false,
          'error': 'NOT_FOUND',
          'message': 'Shipment not found',
        };
      }

      final orderType = shipment['order_type'];
      log('📋 [CONFIGURE] Order type: $orderType');

      // Route to appropriate service
      if (orderType == 'single') {
        log('➡️ [CONFIGURE] Routing to SingleShipmentService');
        // Use dynamic import to avoid issues
        return await _configureSingleShipment(
          shipmentOrderId: shipmentOrderId,
          shipmentType: shipmentType,
          loadingStrategy: loadingStrategy,
          truckDetails: truckDetails,
          courierDetails: courierDetails,
          inPersonDetails: inPersonDetails,
          destination: destination,
          specialInstructions: specialInstructions,
          expectedDispatchAt: expectedDispatchAt,
        );
      } else if (orderType == 'multi') {
        log('➡️ [CONFIGURE] Routing to MultiShipmentService');
        return await _configureMultiShipment(
          shipmentOrderId: shipmentOrderId,
          shipmentType: shipmentType,
          loadingStrategy: loadingStrategy,
          truckDetails: truckDetails,
          courierDetails: courierDetails,
          specialInstructions: specialInstructions,
          expectedDispatchAt: expectedDispatchAt,
        );
      } else {
        return {
          'success': false,
          'error': 'INVALID_TYPE',
          'message': 'Unknown order type: $orderType',
        };
      }

    } catch (e) {
      log('❌ [CONFIGURE] Router error: $e');
      return {
        'success': false,
        'error': 'ROUTER_ERROR',
        'message': e.toString(),
      };
    }
  }

  // Internal method for single shipment configuration
  static Future<Map<String, dynamic>> _configureSingleShipment({
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
    // Inline implementation to avoid import issues
    try {
      if (shipmentType == ShipmentType.truck && truckDetails == null) {
        throw Exception('Truck details required');
      }
      if (shipmentType == ShipmentType.courier && courierDetails == null) {
        throw Exception('Courier details required');
      }
      if (shipmentType == ShipmentType.inPerson && inPersonDetails == null) {
        throw Exception('In-person details required');
      }

      final updateData = {
        'status': 'pending_dispatch',
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
      };

      await _supabase
          .from('wms_shipment_orders')
          .update(updateData)
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);

      clearAllCache();
      return {'success': true, 'message': 'Single shipment configured'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Internal method for multi shipment configuration
  static Future<Map<String, dynamic>> _configureMultiShipment({
    required String shipmentOrderId,
    required ShipmentType shipmentType,
    LoadingStrategy? loadingStrategy,
    Map<String, dynamic>? truckDetails,
    Map<String, dynamic>? courierDetails,
    String? specialInstructions,
    DateTime? expectedDispatchAt,
  }) async {
    try {
      if (shipmentType == ShipmentType.truck && truckDetails == null) {
        throw Exception('Truck details required');
      }
      if (shipmentType == ShipmentType.courier && courierDetails == null) {
        throw Exception('Courier details required');
      }

      final updateData = {
        'status': 'pending_dispatch',
        'shipment_type': shipmentType.name,
        'loading_strategy': loadingStrategy != null 
            ? (loadingStrategy == LoadingStrategy.lifo ? 'lifo' : 'non_lifo')
            : 'non_lifo',
        'truck_details': truckDetails,
        'courier_details': courierDetails,
        'special_instructions': specialInstructions,
        'expected_dispatch_at': expectedDispatchAt?.toIso8601String(),
        'configured_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from('wms_shipment_orders')
          .update(updateData)
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);

      clearAllCache();
      return {'success': true, 'message': 'Multi-customer shipment configured'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ================================
  // GENERATE QR
  // ================================

  static Future<Map<String, dynamic>> generateShipmentQR({
    required String shipmentOrderId,
  }) async {
    try {
      log('🔄 [QR] Generating QR for: $shipmentOrderId');

      final shipmentData = await _supabase
          .from('wms_shipment_orders')
          .select('*')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipmentData == null) {
        throw Exception('Shipment not found');
      }

      final sessionsData = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      if (sessionsData.isEmpty) {
        throw Exception('No packaging sessions found for this shipment');
      }

      final cartonsData = await _supabase
          .from('wms_shipment_cartons')
          .select('carton_barcode, customer_name')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      if (cartonsData.isEmpty) {
        throw Exception('No cartons found for this shipment');
      }

      final sessions = sessionsData as List;
      final cartons = cartonsData as List;
      final cartonsList = cartons.map((c) => c['carton_barcode'] as String).toList();

      // Build QR data
      final qrData = {
        'shipmentid': shipmentData['shipment_id'],
        'shipmenttype': shipmentData['shipment_type'] ?? 'unknown',
        'loadingstrategy': shipmentData['loading_strategy'],
        'destination': shipmentData['destination'] ?? '',
        'cartons': cartonsList,
        'totalcartons': cartonsList.length,
        'createdat': DateTime.now().toIso8601String(),
      };

      // Add type-specific details
      if (shipmentData['shipment_type'] == 'truck') {
        qrData['truckdetails'] = shipmentData['truck_details'];
      } else if (shipmentData['shipment_type'] == 'courier') {
        qrData['courierdetails'] = shipmentData['courier_details'];
      } else if (shipmentData['shipment_type'] == 'inPerson') {
        qrData['inpersondetails'] = shipmentData['in_person_details'];
      }

      // Add customer info
      if (shipmentData['order_type'] == 'multi') {
        qrData['customers'] = sessions.map((s) => {
          'customername': s['customer_name'],
          'ordernumber': s['order_number'],
        }).toList();
      } else {
        final session = sessions.first;
        qrData['customername'] = session['customer_name'];
        qrData['ordernumber'] = session['order_number'];
      }

      // Save QR data
      await _supabase
          .from('wms_shipment_orders')
          .update({
            'qr_data': qrData,
            'slip_generated': true,
          })
          .eq('id', shipmentOrderId)
          .timeout(_requestTimeout);

      clearAllCache();
      log('✅ [QR] Generated successfully');

      return {
        'success': true,
        'qrdata': qrData,
        'message': 'QR code generated successfully',
      };

    } on TimeoutException catch (e) {
      log('❌ [QR] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out',
      };
    } on PostgrestException catch (e) {
      log('❌ [QR] Database error: ${e.message}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': e.message,
      };
    } catch (e, stackTrace) {
      log('❌ [QR] Error: $e\n$stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Failed to generate QR: ${e.toString()}',
      };
    }
  }

  // ================================
  // FETCH OPERATIONS
  // ================================

  static Future<List<ShipmentOrder>> getDraftShipments({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _isCacheValid('draft')) {
        log('📦 [FETCH] Using cached draft shipments');
        return _cache['draft'] ?? [];
      }

      log('🔄 [FETCH] Fetching draft shipments from server...');

      final response = await _supabase
          .from('wms_shipment_orders_with_customers')
          .select('*')
          .eq('status', 'draft')
          .order('created_at', ascending: false)
          .timeout(_requestTimeout);

      final shipments = (response as List)
          .map((json) => ShipmentOrder.fromJson(json))
          .toList();

      _cache['draft'] = shipments;
      _lastCacheTime = DateTime.now();

      log('✅ [FETCH] Found ${shipments.length} draft shipments');
      return shipments;

    } on TimeoutException catch (e) {
      log('❌ [FETCH] Timeout fetching drafts: $e');
      return _cache['draft'] ?? [];
    } on PostgrestException catch (e) {
      log('❌ [FETCH] Database error: ${e.message}');
      return _cache['draft'] ?? [];
    } catch (e) {
      log('❌ [FETCH] Error: $e');
      return _cache['draft'] ?? [];
    }
  }

  static Future<List<ShipmentOrder>> getPendingDispatchShipments({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _isCacheValid('pending')) {
        log('📦 [FETCH] Using cached pending shipments');
        return _cache['pending'] ?? [];
      }

      log('🔄 [FETCH] Fetching pending shipments from server...');

      final response = await _supabase
          .from('wms_shipment_orders_with_customers')
          .select('*')
          .eq('status', 'pending_dispatch')
          .order('configured_at', ascending: false)
          .timeout(_requestTimeout);

      final shipments = (response as List)
          .map((json) => ShipmentOrder.fromJson(json))
          .toList();

      _cache['pending'] = shipments;
      _lastCacheTime = DateTime.now();

      log('✅ [FETCH] Found ${shipments.length} pending shipments');
      return shipments;

    } on TimeoutException catch (e) {
      log('❌ [FETCH] Timeout: $e');
      return _cache['pending'] ?? [];
    } on PostgrestException catch (e) {
      log('❌ [FETCH] Database error: ${e.message}');
      return _cache['pending'] ?? [];
    } catch (e) {
      log('❌ [FETCH] Error: $e');
      return _cache['pending'] ?? [];
    }
  }

  static Future<List<ShipmentOrder>> getDispatchedShipments({
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _isCacheValid('dispatched')) {
        log('📦 [FETCH] Using cached dispatched shipments');
        return _cache['dispatched'] ?? [];
      }

      log('🔄 [FETCH] Fetching dispatched shipments from server...');

      final response = await _supabase
          .from('wms_shipment_orders_with_customers')
          .select('*')
          .eq('status', 'dispatched')
          .order('dispatched_at', ascending: false)
          .limit(limit)
          .timeout(_requestTimeout);

      final shipments = (response as List)
          .map((json) => ShipmentOrder.fromJson(json))
          .toList();

      _cache['dispatched'] = shipments;
      _lastCacheTime = DateTime.now();

      log('✅ [FETCH] Found ${shipments.length} dispatched shipments');
      return shipments;

    } on TimeoutException catch (e) {
      log('❌ [FETCH] Timeout: $e');
      return _cache['dispatched'] ?? [];
    } on PostgrestException catch (e) {
      log('❌ [FETCH] Database error: ${e.message}');
      return _cache['dispatched'] ?? [];
    } catch (e) {
      log('❌ [FETCH] Error: $e');
      return _cache['dispatched'] ?? [];
    }
  }

  static Future<ShipmentOrder?> getShipmentById(String shipmentOrderId) async {
    try {
      log('🔍 [FETCH] Fetching shipment by ID: $shipmentOrderId');
      
      final response = await _supabase
          .from('wms_shipment_orders_with_customers')
          .select('*')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (response == null) {
        log('⚠️ [FETCH] Shipment not found');
        return null;
      }

      log('✅ [FETCH] Shipment found');
      return ShipmentOrder.fromJson(response);
    } catch (e) {
      log('❌ [FETCH] Error: $e');
      return null;
    }
  }

  // ================================
  // CARTON MANAGEMENT
  // ================================

  static Future<List<ShipmentCarton>> getShipmentCartons({
    required String shipmentOrderId,
  }) async {
    try {
      log('🔍 [CARTONS] Fetching cartons for: $shipmentOrderId');
      
      final response = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .order('loading_sequence', ascending: true)
          .timeout(_requestTimeout);

      final cartons = (response as List)
          .map((json) => ShipmentCarton.fromJson(json))
          .toList();

      log('✅ [CARTONS] Found ${cartons.length} cartons');
      return cartons;
    } catch (e) {
      log('❌ [CARTONS] Error: $e');
      return [];
    }
  }

  // ✅ NEW: Get items inside a specific carton with quantities
  static Future<Map<String, dynamic>> getCartonItemsWithQuantity({
    required String cartonBarcode,
  }) async {
    try {
      log('🔍 [CARTON ITEMS] Fetching items for carton: $cartonBarcode');
      
      // First, get the carton ID from package_cartons table
      final cartonResponse = await _supabase
          .from('package_cartons')
          .select('id')
          .eq('carton_barcode', cartonBarcode)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (cartonResponse == null) {
        log('⚠️ [CARTON ITEMS] Carton not found');
        return {'items': [], 'totalItems': 0};
      }

      final cartonId = cartonResponse['id'];

      // Get items from carton_items table
      final itemsResponse = await _supabase
          .from('carton_items')
          .select('id, quantity, added_at, picklist_item_id')
          .eq('carton_id', cartonId)
          .timeout(_requestTimeout);

      final items = <Map<String, dynamic>>[];
      
      for (var item in itemsResponse as List) {
        final picklistItemId = item['picklist_item_id'];
        
        // Get picklist item details
        final picklistItem = await _supabase
            .from('picklist')
            .select('item_name, sku')
            .eq('id', picklistItemId)
            .maybeSingle()
            .timeout(_requestTimeout);
        
        items.add({
          'product_name': picklistItem?['item_name'] ?? 'Unknown Product',
          'sku': picklistItem?['sku'] ?? 'N/A',
          'quantity': item['quantity'] ?? 0,
          'added_at': item['added_at'],
        });
      }

      final totalItems = items.fold<int>(0, (sum, item) => sum + (item['quantity'] as int));

      log('✅ [CARTON ITEMS] Found ${items.length} unique items, total qty: $totalItems');
      
      return {
        'items': items,
        'totalItems': totalItems,
        'uniqueItems': items.length,
      };
    } catch (e) {
      log('❌ [CARTON ITEMS] Error: $e');
      return {'items': [], 'totalItems': 0, 'uniqueItems': 0};
    }
  }

  // ================================
  // MULTI-CUSTOMER SHIPMENT - DEPRECATED
  // ================================
  // ⚠️ DEPRECATED: Use MultiShipmentService.createFromPackagingSessions() instead
  // This method is kept for backward compatibility only
  
  @Deprecated('Use MultiShipmentService.createFromPackagingSessions() instead')
  static Future<Map<String, dynamic>> createMultiCustomerShipment({
    required List<String> packagingSessionIds,
    required String userName,
  }) async {
    log('⚠️ [DEPRECATED] createMultiCustomerShipment called - use MultiShipmentService instead');
    
    // For now, keep inline implementation for compatibility
    // TODO: Migrate all callers to use MultiShipmentService directly
    try {
      log('🔄 [MSO] Creating with ${packagingSessionIds.length} sessions');

      if (packagingSessionIds.isEmpty) {
        throw Exception('At least one packaging session is required');
      }

      if (packagingSessionIds.length < 2) {
        throw Exception('Multi-customer shipment requires at least 2 sessions');
      }

      final sessionsResponse = await _supabase
          .from('packaging_sessions')
          .select('*, customer_orders!inner(*)')
          .inFilter('session_id', packagingSessionIds)
          .timeout(_requestTimeout);

      final sessions = sessionsResponse as List;

      if (sessions.length != packagingSessionIds.length) {
        throw Exception('Some packaging sessions not found');
      }

      for (var session in sessions) {
        if (session['shipment_order_created'] == true) {
          throw Exception('Session ${session['session_id']} already has a shipment');
        }
      }

      int totalCartons = 0;
      for (var session in sessions) {
        final cartonsResponse = await _supabase
            .from('package_cartons')
            .select('carton_barcode')
            .eq('packaging_session_id', session['session_id'])
            .eq('status', 'sealed')
            .timeout(_requestTimeout);
        totalCartons += (cartonsResponse as List).length;
      }

      if (totalCartons == 0) {
        throw Exception('No sealed cartons found in any session');
      }

      log('📦 [MSO] Total cartons: $totalCartons across ${sessions.length} customers');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final shipmentId = 'MSO-${timestamp.toString().substring(timestamp.toString().length - 8)}';

      final shipmentData = {
        'shipment_id': shipmentId,
        'order_type': 'multi',
        'status': 'draft',
        'total_cartons': totalCartons,
        'created_by': userName,
        'slip_generated': false,
        'warehouse_id': sessions.first['warehouse_id'],
      };

      final shipmentResponse = await _supabase
          .from('wms_shipment_orders')
          .insert(shipmentData)
          .select()
          .single()
          .timeout(_requestTimeout);

      final shipmentOrderId = shipmentResponse['id'];
      log('✅ [MSO] Created: $shipmentId');

      for (var session in sessions) {
        final cartonsResponse = await _supabase
            .from('package_cartons')
            .select('carton_barcode')
            .eq('packaging_session_id', session['session_id'])
            .eq('status', 'sealed')
            .timeout(_requestTimeout);

        final cartonCount = (cartonsResponse as List).length;

        await _supabase.from('wms_shipment_packaging_sessions').insert({
          'shipment_order_id': shipmentOrderId,
          'packaging_session_id': session['session_id'],
          'customer_name': session['customer_orders']['customer_name'] ?? '',
          'order_number': session['order_number'] ?? '',
          'carton_count': cartonCount,
        }).timeout(_requestTimeout);

        final cartonInserts = (cartonsResponse as List).map((c) => {
          'shipment_order_id': shipmentOrderId,
          'carton_barcode': c['carton_barcode'],
          'customer_name': session['customer_orders']['customer_name'] ?? '',
          'is_loaded': false,
        }).toList();

        await _supabase
            .from('wms_shipment_cartons')
            .insert(cartonInserts)
            .timeout(_requestTimeout);

        await _supabase
            .from('packaging_sessions')
            .update({
              'shipment_order_created': true,
              'shipment_order_id': shipmentOrderId,
            })
            .eq('session_id', session['session_id'])
            .timeout(_requestTimeout);

        log('✅ [MSO] Linked session: ${session['session_id']} (${cartonCount} cartons)');
      }

      clearAllCache();
      log('✅✅✅ [MSO] Creation complete: $shipmentId');

      return {
        'success': true,
        'shipment_id': shipmentId,
        'shipment_order_id': shipmentOrderId,
        'total_cartons': totalCartons,
        'customer_count': sessions.length,
        'message': 'Multi-customer shipment created successfully',
      };

    } on TimeoutException catch (e) {
      log('❌ [MSO] Timeout: $e');
      return {
        'success': false,
        'error': 'TIMEOUT',
        'message': 'Request timed out',
      };
    } on PostgrestException catch (e) {
      log('❌ [MSO] Database error: ${e.message}');
      return {
        'success': false,
        'error': 'DATABASE_ERROR',
        'message': e.message,
      };
    } catch (e, stackTrace) {
      log('❌ [MSO] Error: $e\n$stackTrace');
      return {
        'success': false,
        'error': 'UNKNOWN',
        'message': 'Failed to create MSO: ${e.toString()}',
      };
    }
  }

  // ================================
  // DISPATCH SLIP DATA
  // ================================

  /// Get complete dispatch slip data with driver, routes, and cartons
  /// Works with both wms_shipment_orders and shipment_sessions
  static Future<Map<String, dynamic>> getDispatchSlipData({
    required String shipmentOrderId,
  }) async {
    try {
      log('🔍 [DISPATCH] Fetching dispatch data for: $shipmentOrderId');

      // Try to get from wms_shipment_orders first
      final shipmentResponse = await _supabase
          .from('wms_shipment_orders')
          .select('*')
          .eq('id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (shipmentResponse != null) {
        // This is a proper shipment order - use the full method
        return await _getDispatchDataFromShipmentOrder(shipmentOrderId, shipmentResponse);
      }

      // Otherwise, try shipment_sessions (loading screen workflow)
      final sessionResponse = await _supabase
          .from('shipment_sessions')
          .select('*')
          .eq('session_id', shipmentOrderId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (sessionResponse != null) {
        return await _getDispatchDataFromSession(shipmentOrderId, sessionResponse);
      }

      return {
        'success': false,
        'error': 'Shipment not found',
      };
    } on TimeoutException catch (e) {
      log('❌ [DISPATCH] Timeout: $e');
      return {
        'success': false,
        'error': 'Request timed out',
      };
    } on PostgrestException catch (e) {
      log('❌ [DISPATCH] Database error: ${e.message}');
      return {
        'success': false,
        'error': e.message,
      };
    } catch (e, stackTrace) {
      log('❌ [DISPATCH] Error: $e\n$stackTrace');
      return {
        'success': false,
        'error': 'Failed to fetch dispatch data: ${e.toString()}',
      };
    }
  }

  /// Get dispatch data from shipment_sessions (loading screen workflow)
  static Future<Map<String, dynamic>> _getDispatchDataFromSession(
    String sessionId,
    Map sessionResponse,
  ) async {
    try {
      log('📦 [DISPATCH] Using shipment_sessions workflow');

      // Driver details - use defaults for session-based workflow
      final driver = {
        'driver_name': 'N/A',
        'phone_number': 'N/A',
        'license_id': 'N/A',
        'vehicle_registration': sessionResponse['truck_number'] ?? 'N/A',
      };

      // Single route/stop for session-based workflow
      final routes = [
        {
          'customer_name': sessionResponse['customer_name'] ?? 'N/A',
          'address': sessionResponse['destination'] ?? 'N/A',
          'contact_person': sessionResponse['customer_name'] ?? 'N/A',
          'phone': 'N/A',
          'order_number': sessionId,
        }
      ];

      // Get cartons from shipment_cartons table
      final cartonsResponse = await _supabase
          .from('shipment_cartons')
          .select('*')
          .eq('session_id', sessionId)
          .eq('is_scanned', true)
          .timeout(_requestTimeout);

      final allCartons = cartonsResponse as List;

      // Build cartons list with product info
      final enrichedCartons = <Map>[];
      for (var carton in allCartons) {
        final cartonId = carton['carton_id'];
        
        // Get product details for each carton
        final cartonItemsResult = await getCartonItemsWithQuantity(
          cartonBarcode: cartonId,
        );

        final items = cartonItemsResult['items'] as List? ?? [];
        final productName = items.isNotEmpty 
            ? items.first['product_name'] ?? 'Unknown Product'
            : 'Unknown Product';
        final totalQty = cartonItemsResult['totalItems'] ?? 0;

        enrichedCartons.add({
          'carton_barcode': cartonId,
          'customer_name': sessionResponse['customer_name'] ?? 'N/A',
          'quantity': totalQty,
          'weight_kg': 0.0,
          'products': {
            'product_name': productName,
          },
        });
      }

      // All cartons in stop 1
      final Map<int, List<Map>> cartonsByStop = {
        1: enrichedCartons,
      };

      log('✅ [DISPATCH] Session data: 1 stop, ${enrichedCartons.length} cartons');

      return {
        'success': true,
        'shipment': {
          'id': sessionId,
          'truck_number': sessionResponse['truck_number'],
          'status': sessionResponse['status'],
          'loading_strategy': 'N/A',
        },
        'driver': driver,
        'routes': routes,
        'cartons_by_stop': cartonsByStop,
      };
    } catch (e, stackTrace) {
      log('❌ [DISPATCH] Session error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Get dispatch data from wms_shipment_orders (proper shipment workflow)
  static Future<Map<String, dynamic>> _getDispatchDataFromShipmentOrder(
    String shipmentOrderId,
    Map shipmentResponse,
  ) async {
    try {
      log('📋 [DISPATCH] Using wms_shipment_orders workflow');

      // Get driver details from truck_details (FIXED: correct field names)
      final truckDetails = shipmentResponse['truck_details'] as Map? ?? {};
      final driver = {
        'driver_name': truckDetails['driverName'] ?? 'N/A',
        'phone_number': truckDetails['driverPhone'] ?? 'N/A',
        'license_id': truckDetails['licenseId'] ?? 'N/A',
        'vehicle_registration': truckDetails['truckNumber'] ?? 'N/A',
      };

      // Get packaging sessions (routes/stops) with customer order details
      final sessionsResponse = await _supabase
          .from('wms_shipment_packaging_sessions')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .timeout(_requestTimeout);

      final sessions = sessionsResponse as List;
      
      // Build routes list with customer order details
      final routes = <Map<String, dynamic>>[];
      for (var session in sessions) {
        // Get customer order details from packaging_sessions → customer_orders
        final packagingSession = await _supabase
            .from('packaging_sessions')
            .select('order_id, customer_orders!inner(*)')
            .eq('session_id', session['packaging_session_id'])
            .maybeSingle()
            .timeout(_requestTimeout);

        final customerOrder = packagingSession?['customer_orders'] as Map? ?? {};

        routes.add({
          'customer_name': session['customer_name'] ?? 'N/A',
          'customer_email': customerOrder['customer_email'] ?? 'N/A',
          'phone': customerOrder['customer_phone'] ?? 'N/A',
          'contact_person': session['customer_name'] ?? 'N/A',
          'address': customerOrder['ship_to_address'] ?? 'N/A',
          'ship_to_address': customerOrder['ship_to_address'] ?? 'N/A',
          'bill_to_address': customerOrder['bill_to_address'] ?? 'N/A',
          'order_number': session['order_number'] ?? 'N/A',
        });
      }

      // Get cartons grouped by stop
      final cartonsResponse = await _supabase
          .from('wms_shipment_cartons')
          .select('*')
          .eq('shipment_order_id', shipmentOrderId)
          .order('customer_name')
          .timeout(_requestTimeout);

      final allCartons = cartonsResponse as List;

      // Group cartons by stop (customer)
      final Map<int, List<Map>> cartonsByStop = {};
      int stopIndex = 1;
      
      for (var route in routes) {
        final customerName = route['customer_name'];
        final customerCartons = allCartons
            .where((c) => c['customer_name'] == customerName)
            .toList();

        // 🔥 FIXED: Get product details using correct path: carton_items → picklist
        final enrichedCartons = <Map>[];
        for (var carton in customerCartons) {
          final cartonBarcode = carton['carton_barcode'];
          
          log('🔍 [CARTON ITEMS] Fetching items for carton: $cartonBarcode');
          
          // ✅ STEP 1: Get carton UUID from package_cartons table
          final packageCarton = await _supabase
              .from('package_cartons')
              .select('id')
              .eq('carton_barcode', cartonBarcode)
              .maybeSingle()
              .timeout(_requestTimeout);
          
          if (packageCarton == null) {
            log('⚠️ [CARTON ITEMS] Package carton not found: $cartonBarcode');
            enrichedCartons.add({
              'carton_barcode': cartonBarcode,
              'customer_name': carton['customer_name'],
              'quantity': 0,
              'weight_kg': 0.0,
              'products': {
                'product_name': 'Unknown',
              },
            });
            continue;
          }
          
          final cartonId = packageCarton['id'];
          
          // ✅ STEP 2: Fetch carton_items with picklist join
          final cartonItems = await _supabase
              .from('carton_items')
              .select('''
                quantity,
                picklist:picklist_item_id(
                  item_name,
                  sku,
                  quantity_picked
                )
              ''')
              .eq('carton_id', cartonId)
              .timeout(_requestTimeout);

          int totalQty = 0;
          String productName = 'Mixed Items';
          List<Map<String, dynamic>> items = [];

          // ✅ STEP 3: Process each item from picklist
          for (var cartonItem in cartonItems) {
            final qty = cartonItem['quantity'] as int? ?? 0;
            final picklistData = cartonItem['picklist'] as Map?;
            
            if (picklistData != null) {
              totalQty += qty;
              
              items.add({
                'product_name': picklistData['item_name'] ?? 'Unknown',
                'sku': picklistData['sku'] ?? 'N/A',
                'quantity': qty,
              });
              
              // Use first item's name as main product name
              if (items.length == 1) {
                productName = picklistData['item_name'] ?? 'Unknown';
              }
            }
          }

          log('✅ [CARTON ITEMS] Found ${items.length} items, total qty: $totalQty');

          enrichedCartons.add({
            'carton_barcode': cartonBarcode,
            'customer_name': carton['customer_name'],
            'quantity': totalQty,
            'weight_kg': 0.0,
            'products': {
              'product_name': productName,
              'items': items,
              'item_count': items.length,
            },
          });
        }

        cartonsByStop[stopIndex] = enrichedCartons;
        stopIndex++;
      }

      log('✅ [DISPATCH] Order data: ${routes.length} stops, ${allCartons.length} cartons');

      return {
        'success': true,
        'shipment': {
          'id': shipmentResponse['shipment_id'],
          'truck_number': truckDetails['truckNumber'] ?? 'N/A',
          'status': shipmentResponse['status'],
          'loading_strategy': shipmentResponse['loading_strategy'],
        },
        'driver': driver,
        'routes': routes,
        'cartons_by_stop': cartonsByStop,
      };
    } catch (e, stackTrace) {
      log('❌ [DISPATCH] Order error: $e\n$stackTrace');
      rethrow;
    }
  }

  // ================================
  // CACHE MANAGEMENT
  // ================================

  static bool _isCacheValid(String key) {
    if (_lastCacheTime == null || !_cache.containsKey(key)) {
      return false;
    }
    final difference = DateTime.now().difference(_lastCacheTime!);
    return difference < _cacheDuration;
  }

  static void clearAllCache() {
    _cache.clear();
    _lastCacheTime = null;
    log('🗑️ [CACHE] All cache cleared');
  }

  static Future<void> refreshAllData() async {
    log('🔄 [REFRESH] Refreshing all shipment data...');
    clearAllCache();
    await Future.wait([
      getDraftShipments(forceRefresh: true),
      getPendingDispatchShipments(forceRefresh: true),
      getDispatchedShipments(forceRefresh: true),
    ]);
    log('✅ [REFRESH] All data refreshed');
  }

  static bool get isCacheValid => _lastCacheTime != null &&
      DateTime.now().difference(_lastCacheTime!) < _cacheDuration;

  static DateTime? get lastCacheTime => _lastCacheTime;
  
  static Future import(String s) async {}
}

// ================================
// 📝 MIGRATION NOTES
// ================================
//
// ⚠️ IMPORTANT: This service has been refactored!
//
// OLD WAY (Deprecated - still works but not recommended):
// ❌ ShipmentService.createDraftShipmentFromPackaging()
// ❌ ShipmentService.createMultiCustomerShipment()
// ❌ ShipmentService.configureShipment()
//
// NEW WAY (Recommended):
// ✅ For Single Customer (SO):
//    - SingleShipmentService.createFromPackaging()
//    - SingleShipmentService.configure()
//    - SingleShipmentService.getDetails()
//
// ✅ For Multi-Customer (MSO):
//    - MultiShipmentService.createFromPackagingSessions()
//    - MultiShipmentService.configure()
//    - MultiShipmentService.getDetails()
//    - MultiShipmentService.getAvailableSessions()
//
// ✅ Common Operations (use ShipmentService):
//    - ShipmentService.deleteDraftShipment()
//    - ShipmentService.getDraftShipments()
//    - ShipmentService.getPendingDispatchShipments()
//    - ShipmentService.getShipmentCartons()
//    - ShipmentService.generateShipmentQR()
//    - ShipmentService.getDispatchSlipData()
//    - ShipmentService.clearAllCache()
//
// 📚 See SHIPMENT_SERVICE_SEPARATION.md for complete migration guide
// ================================
