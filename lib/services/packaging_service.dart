// lib/services/packaging_service.dart
// ✅ PRODUCTION READY - All Critical Issues Fixed

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:async';

// ================================
// DATA MODELS
// ================================

class CompletedOrder {
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? shipToAddress;
  final String? billToAddress;
  final int totalItems;
  final DateTime completedAt;
  final String? warehouseId;

  CompletedOrder({
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.shipToAddress,
    this.billToAddress,
    required this.totalItems,
    required this.completedAt,
    this.warehouseId,
  });

  factory CompletedOrder.fromJson(Map<String, dynamic> json) {
    return CompletedOrder(
      orderId: json['order_id'] ?? '',
      orderNumber: json['order_number'] ?? '',
      customerName: json['customer_name'] ?? '',
      customerEmail: json['customer_email'],
      customerPhone: json['customer_phone'],
      shipToAddress: json['ship_to_address'],
      billToAddress: json['bill_to_address'],
      totalItems: json['total_items'] ?? 0,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : DateTime.now(),
      warehouseId: json['warehouse_id'],
    );
  }
}

class PackagingSession {
  final String id;
  final String sessionId;
  final String orderId;
  final String customerName;
  final String packagedBy;
  final String status;
  final int totalItems;
  final int totalCartons;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool? shipmentOrderCreated; // ✅ NEW: Track if shipment created
  final String? shipmentOrderId; // ✅ NEW: Link to shipment

  PackagingSession({
    required this.id,
    required this.sessionId,
    required this.orderId,
    required this.customerName,
    required this.packagedBy,
    required this.status,
    required this.totalItems,
    required this.totalCartons,
    required this.startedAt,
    this.completedAt,
    this.shipmentOrderCreated,
    this.shipmentOrderId,
  });

  factory PackagingSession.fromJson(Map<String, dynamic> json) {
    return PackagingSession(
      id: json['id'] ?? '',
      sessionId: json['session_id'] ?? '',
      orderId: json['order_id'] ?? '',
      customerName: json['customer_name'] ?? '',
      packagedBy: json['packaged_by'] ?? '',
      status: json['status'] ?? 'in_progress',
      totalItems: json['total_items'] ?? 0,
      totalCartons: json['total_cartons'] ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      shipmentOrderCreated: json['shipment_order_created'] as bool?,
      shipmentOrderId: json['shipment_order_id'] as String?,
    );
  }
}

class BoxConfiguration {
  final String boxType;
  final int quantity;
  final double? estimatedWeight;

  BoxConfiguration({
    required this.boxType,
    required this.quantity,
    this.estimatedWeight,
  });
}

class PackageCarton {
  final String id;
  final String cartonBarcode;
  final String packagingSessionId;
  final int boxNumber;
  final String boxType;
  final double? estimatedWeight;
  final double? actualWeight;
  final String status;
  final int itemsCount;
  final DateTime createdAt;
  final DateTime? sealedAt;
  final String? sealedBy;

  PackageCarton({
    required this.id,
    required this.cartonBarcode,
    required this.packagingSessionId,
    required this.boxNumber,
    required this.boxType,
    this.estimatedWeight,
    this.actualWeight,
    required this.status,
    required this.itemsCount,
    required this.createdAt,
    this.sealedAt,
    this.sealedBy,
  });

  factory PackageCarton.fromJson(Map<String, dynamic> json) {
    return PackageCarton(
      id: json['id'] ?? '',
      cartonBarcode: json['carton_barcode'] ?? '',
      packagingSessionId: json['packaging_session_id'] ?? '',
      boxNumber: json['box_number'] ?? 1,
      boxType: json['box_type'] ?? 'medium',
      estimatedWeight: json['estimated_weight']?.toDouble(),
      actualWeight: json['actual_weight']?.toDouble(),
      status: json['status'] ?? 'pending',
      itemsCount: json['items_count'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      sealedAt: json['sealed_at'] != null
          ? DateTime.parse(json['sealed_at'])
          : null,
      sealedBy: json['sealed_by'],
    );
  }
}

class PicklistItemDetail {
  final String id;
  final String itemName;
  final String sku;
  final String productName;
  final int quantityPicked;
  final int quantityPacked;

  PicklistItemDetail({
    required this.id,
    required this.itemName,
    required this.sku,
    required this.productName,
    required this.quantityPicked,
    required this.quantityPacked,
  });
}

class CartonItemDetail {
  final String id;
  final String cartonId;
  final String picklistItemId;
  final String productName;
  final String sku;
  final int quantity;
  final DateTime addedAt;
  final String addedBy;

  CartonItemDetail({
    required this.id,
    required this.cartonId,
    required this.picklistItemId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.addedAt,
    required this.addedBy,
  });
}

// ================================
// SERVICE CLASS
// ================================

class PackagingService {
  static final _supabase = Supabase.instance.client;
  
  // ✅ FIX: Cache with session-specific keys
  static final Map<String, List<PicklistItemDetail>> _picklistCache = {};
  static DateTime? _lastCacheUpdate;
  static const int _maxCacheSize = 10; // Prevent memory leak

  // ================================
  // 1. GET COMPLETED ORDERS ✅ FIXED - PREVENT AUTO RE-GENERATION
  // ================================
  static Future<List<CompletedOrder>> getCompletedOrdersReadyForPackaging() async {
    try {
      log('📦 Fetching completed orders ready for packaging...');
      
      final ordersResponse = await _supabase
          .from('customer_orders')
          .select('''
            order_id,
            order_number,
            customer_name,
            customer_email,
            customer_phone,
            ship_to_address,
            bill_to_address,
            completed_at,
            packaging_deleted,
            order_items!inner(id)
          ''')
          .eq('order_status', 'completed')
          .eq('packaging_deleted', false)  // ✅ CRITICAL FIX: Exclude soft-deleted orders
          .order('completed_at', ascending: false);

      // ✅ FIX: Exclude orders with ANY packaging session (active OR completed)
      // This prevents deleted sessions from reappearing
      final existingSessions = await _supabase
          .from('packaging_sessions')
          .select('order_id, status')
          .inFilter('status', ['in_progress', 'completed']); // ✅ BOTH statuses

      final excludedOrderIds = (existingSessions as List)
          .map((s) => s['order_id'].toString())
          .toSet();

      log('📋 Excluding ${excludedOrderIds.length} orders with existing sessions');
      log('📋 Excluding orders with packaging_deleted = true');

      final orders = (ordersResponse as List)
          .where((json) => !excludedOrderIds.contains(json['order_id']))
          .map((json) {
        final items = json['order_items'] as List? ?? [];
        return CompletedOrder(
          orderId: json['order_id'] ?? '',
          orderNumber: json['order_number'] ?? '',
          customerName: json['customer_name'] ?? '',
          customerEmail: json['customer_email'],
          customerPhone: json['customer_phone'],
          shipToAddress: json['ship_to_address'],
          billToAddress: json['bill_to_address'],
          totalItems: items.length,
          completedAt: json['completed_at'] != null
              ? DateTime.parse(json['completed_at'])
              : DateTime.now(),
          warehouseId: null,
        );
      }).toList();

      log('✅ Found ${orders.length} orders ready for packaging (excluding deleted)');
      return orders;
    } catch (e) {
      log('❌ Error fetching completed orders: $e');
      return [];
    }
  }

  // ================================
  // 2. GET ACTIVE SESSIONS
  // ================================
  static Future<List<PackagingSession>> getActivePackagingSessions() async {
    try {
      log('📦 Fetching active packaging sessions...');
      
      final response = await _supabase
          .from('packaging_sessions')
          .select()
          .eq('status', 'in_progress')
          .order('started_at', ascending: false);

      final sessions = (response as List)
          .map((json) => PackagingSession.fromJson(json))
          .toList();

      log('✅ Found ${sessions.length} active sessions');
      return sessions;
    } catch (e) {
      log('❌ Error fetching active sessions: $e');
      return [];
    }
  }

  // ================================
  // 3. GET COMPLETED PACKAGING
  // ================================
  static Future<List<PackagingSession>> getCompletedPackaging() async {
    try {
      log('📦 Fetching completed packaging...');
      
      final response = await _supabase
          .from('packaging_sessions')
          .select()
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(50);

      final sessions = (response as List)
          .map((json) => PackagingSession.fromJson(json))
          .toList();

      log('✅ Found ${sessions.length} completed sessions');
      return sessions;
    } catch (e) {
      log('❌ Error fetching completed packaging: $e');
      return [];
    }
  }

  // ================================
  // 4. CREATE SESSION WITH BOXES ✅ FIXED
  // ================================
  static Future<PackagingSession> createSessionWithBoxes({
    required CompletedOrder order,
    required List<BoxConfiguration> boxes,
    required String operatorName,
  }) async {
    try {
      // ✅ FIX PROBLEM 4: Check if session already exists for this order
      final existingSession = await _supabase
          .from('packaging_sessions')
          .select()
          .eq('order_id', order.orderId)
          .eq('status', 'in_progress')
          .maybeSingle();

      if (existingSession != null) {
        // ✅ Return special error code for UI to handle
        throw Exception('RESUME_EXISTING_SESSION:${existingSession['session_id']}');
      }

      final sessionId = 'PKG-${DateTime.now().millisecondsSinceEpoch}';
      log('📦 Creating session: $sessionId with ${boxes.length} boxes');

      final sessionData = {
        'session_id': sessionId,
        'order_id': order.orderId,
        'customer_name': order.customerName,
        'packaged_by': operatorName,
        'status': 'in_progress',
        'total_items': order.totalItems,
        'total_cartons': boxes.length,
        'started_at': DateTime.now().toIso8601String(),
      };

      final sessionResponse = await _supabase
          .from('packaging_sessions')
          .insert(sessionData)
          .select()
          .single();

      // ✅ FIX PROBLEM 5: Create boxes with proper sequencing
      final baseTime = DateTime.now();
      for (int i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        final boxNumber = i + 1;
        final cartonBarcode = '$sessionId-BOX$boxNumber';
        
        // ✅ Add delay to ensure proper ordering
        await Future.delayed(const Duration(milliseconds: 50));
        
        await _supabase.from('package_cartons').insert({
          'carton_barcode': cartonBarcode,
          'packaging_session_id': sessionId,
          'box_number': boxNumber,
          'box_type': box.boxType,
          'estimated_weight': box.estimatedWeight,
          'status': i == 0 ? 'open' : 'pending',
          'items_count': 0,
          'created_at': baseTime.add(Duration(milliseconds: i * 100)).toIso8601String(),
        });
        
        log('✅ Created Box $boxNumber with status: ${i == 0 ? "open" : "pending"}');
      }

      log('✅ Session created successfully');
      return PackagingSession.fromJson(sessionResponse);
    } catch (e) {
      log('❌ Error creating session: $e');
      rethrow; // ✅ Preserve original error for UI handling
    }
  }

  // ================================
  // 5. GET PICKLIST ITEMS ✅ FIXED - SESSION-SPECIFIC
  // ================================
  static Future<List<PicklistItemDetail>> getPicklistItems(
    String orderId, 
    {bool useCache = false, bool forceRefresh = false, String? sessionId}
  ) async {
    try {
      final cacheKey = sessionId != null ? '$orderId-$sessionId' : orderId;
      
      if (!forceRefresh && useCache && _picklistCache.containsKey(cacheKey)) {
        final cacheAge = DateTime.now().difference(_lastCacheUpdate ?? DateTime.now());
        if (cacheAge.inSeconds < 5) {
          log('✅ Using cached picklist items');
          return _picklistCache[cacheKey]!;
        }
      }

      if (forceRefresh) {
        _picklistCache.remove(cacheKey);
        log('🔄 Force refreshing picklist items');
      }

      log('📦 Fetching picklist items with packed quantities...');
      
      final response = await _supabase
          .from('picklist')
          .select()
          .eq('order_id', orderId);

      // ✅ FIX: Calculate packed quantities ONLY for specified session
      Map<String, int> packedQuantities = {};
      
      if (sessionId != null) {
        // Get cartons for THIS session only
        final cartons = await _supabase
            .from('package_cartons')
            .select('id')
            .eq('packaging_session_id', sessionId);
        
        final cartonIds = (cartons as List)
            .map((c) => c['id'].toString())
            .toList();
        
        if (cartonIds.isNotEmpty) {
          final cartonItems = await _supabase
              .from('carton_items')
              .select('picklist_item_id, quantity')
              .inFilter('carton_id', cartonIds);
          
          for (var item in cartonItems as List) {
            final picklistId = item['picklist_item_id'].toString();
            final qty = item['quantity'] as int? ?? 0;
            packedQuantities[picklistId] = (packedQuantities[picklistId] ?? 0) + qty;
          }
        }
      }

      final items = (response as List).map((json) {
        final picklistId = json['id'] ?? '';
        final quantityPacked = packedQuantities[picklistId] ?? 0;
        
        return PicklistItemDetail(
          id: picklistId,
          itemName: json['item_name'] ?? '',
          sku: json['sku'] ?? '',
          productName: json['item_name'] ?? '',
          quantityPicked: json['quantity_picked'] ?? 0,
          quantityPacked: quantityPacked,
        );
      }).toList();

      // ✅ FIX: Limit cache size to prevent memory leak
      if (_picklistCache.length >= _maxCacheSize) {
        _picklistCache.clear();
      }
      _picklistCache[cacheKey] = items;
      _lastCacheUpdate = DateTime.now();

      log('✅ Fetched ${items.length} picklist items');
      return items;
    } catch (e) {
      log('❌ Error fetching picklist items: $e');
      return [];
    }
  }

  // ================================
  // 6. VALIDATE SCANNED ITEM ✅ FIXED - SESSION-SPECIFIC
  // ================================
  static Future<Map<String, dynamic>> validateScannedItem({
    required String orderId,
    required String barcode,
    required String sessionId, // ✅ NEW: Required parameter
  }) async {
    try {
      log('🔍 Validating barcode: $barcode for order: $orderId, session: $sessionId');
      
      final cleanBarcode = barcode.trim().toUpperCase();
      
      log('🔍 Searching for barcode: $cleanBarcode');
      
      final response = await _supabase
          .from('picklist')
          .select()
          .eq('order_id', orderId)
          .eq('barcode', cleanBarcode)
          .maybeSingle();

      if (response == null) {
        log('❌ Item not found - trying alternative search...');
        
        final altResponse = await _supabase
            .from('picklist')
            .select()
            .eq('order_id', orderId)
            .ilike('barcode', '%$cleanBarcode%')
            .maybeSingle();
        
        if (altResponse == null) {
          final errorMsg = '⚠️ ITEM NOT IN ORDER\n\n'
              'Barcode: $cleanBarcode\n'
              'This item is not part of this order';
          log('❌ $errorMsg');
          return {
            'isValid': false,
            'message': errorMsg,
          };
        }
        
        return _validateItemData(altResponse, orderId, sessionId);
      }

      return _validateItemData(response, orderId, sessionId);
    } catch (e) {
      log('❌ Validation error: $e');
      return {
        'isValid': false,
        'message': '❌ VALIDATION ERROR\n\n$e',
      };
    }
  }

  // ✅ FIXED: Validate with session-specific packed quantity
  static Future<Map<String, dynamic>> _validateItemData(
    Map<String, dynamic> response,
    String orderId,
    String sessionId,
  ) async {
    final itemName = response['item_name'] ?? 'Unknown Item';
    final sku = response['sku'] ?? 'N/A';
    final quantityPicked = response['quantity_picked'] as int? ?? 0;
    
    if (quantityPicked <= 0) {
      final errorMsg = '⚠️ ITEM NOT PICKED YET\n\n'
          'Item: $itemName\n'
          'SKU: $sku\n'
          'Picked Quantity: $quantityPicked\n\n'
          'Please pick this item first!';
      log('❌ $errorMsg');
      return {
        'isValid': false,
        'message': errorMsg,
      };
    }

    // ✅ FIX PROBLEM 6: Check packed quantity ONLY in current session
    final picklistItemId = response['id'];
    final alreadyPacked = await getPackedQuantityInSession(picklistItemId, sessionId);
    final remaining = quantityPicked - alreadyPacked;

    if (remaining <= 0) {
      final errorMsg = '⚠️ ALREADY FULLY PACKED IN THIS SESSION!\n\n'
          'Item: $itemName\n'
          'SKU: $sku\n'
          'Total Picked: $quantityPicked\n'
          'Already Packed: $alreadyPacked\n'
          'Remaining: 0\n\n'
          'This item is already in a box!';
      log('⚠️ $errorMsg');
      return {
        'isValid': false,
        'message': errorMsg,
      };
    }

    log('✅ Valid item. Picked: $quantityPicked, Packed: $alreadyPacked, Remaining: $remaining');
    return {
      'isValid': true,
      'item': response,
      'remainingQty': remaining,
      'alreadyPacked': alreadyPacked,
    };
  }

  // ✅ NEW: Get packed quantity for SPECIFIC SESSION only
  static Future<int> getPackedQuantityInSession(String picklistItemId, String sessionId) async {
    try {
      // Get cartons for THIS session
      final cartons = await _supabase
          .from('package_cartons')
          .select('id')
          .eq('packaging_session_id', sessionId);
      
      final cartonIds = (cartons as List).map((c) => c['id'].toString()).toList();
      
      if (cartonIds.isEmpty) return 0;
      
      final response = await _supabase
          .from('carton_items')
          .select('quantity')
          .eq('picklist_item_id', picklistItemId)
          .inFilter('carton_id', cartonIds);
      
      int total = 0;
      for (var item in response as List) {
        total += (item['quantity'] as int? ?? 0);
      }
      return total;
    } catch (e) {
      log('❌ Error getting packed quantity: $e');
      return 0;
    }
  }

  // ✅ DEPRECATED: Old function kept for compatibility
  static Future<int> getPackedQuantity(String picklistItemId) async {
    try {
      final response = await _supabase
          .from('carton_items')
          .select('quantity')
          .eq('picklist_item_id', picklistItemId);
      
      int total = 0;
      for (var item in response as List) {
        total += (item['quantity'] as int? ?? 0);
      }
      return total;
    } catch (e) {
      log('❌ Error getting packed quantity: $e');
      return 0;
    }
  }

  // ================================
  // 7. ADD ITEM TO CARTON ✅ FIXED
  // ================================
  static Future<void> addItemToCarton({
    required String cartonId,
    required String picklistItemId,
    required int quantity,
    required String operatorName,
    required String sessionId, // ✅ NEW: Required for validation
  }) async {
    try {
      log('📦 Adding $quantity items to carton...');

      // ✅ FIX PROBLEM 6: Validate using session-specific quantity
      final alreadyPacked = await getPackedQuantityInSession(picklistItemId, sessionId);
      
      final picklistItem = await _supabase
          .from('picklist')
          .select('quantity_picked, item_name')
          .eq('id', picklistItemId)
          .single();
      
      final totalPicked = picklistItem['quantity_picked'] as int? ?? 0;
      final remaining = totalPicked - alreadyPacked;
      
      if (quantity > remaining) {
        throw Exception('Cannot pack $quantity items. Only $remaining remaining in this session.');
      }

      // ✅ FIX PROBLEM 6: Check for duplicate within same carton
      final existingInCarton = await _supabase
          .from('carton_items')
          .select('quantity')
          .eq('carton_id', cartonId)
          .eq('picklist_item_id', picklistItemId)
          .maybeSingle();
      
      if (existingInCarton != null) {
        // Update existing entry instead of creating duplicate
        final newQty = (existingInCarton['quantity'] as int? ?? 0) + quantity;
        await _supabase
            .from('carton_items')
            .update({
              'quantity': newQty,
              'added_at': DateTime.now().toIso8601String(),
            })
            .eq('carton_id', cartonId)
            .eq('picklist_item_id', picklistItemId);
        log('✅ Updated existing item quantity to $newQty');
      } else {
        // Insert new entry
        await _supabase.from('carton_items').insert({
          'carton_id': cartonId,
          'picklist_item_id': picklistItemId,
          'quantity': quantity,
          'added_by': operatorName,
          'added_at': DateTime.now().toIso8601String(),
        });
        log('✅ Added new item to carton');
      }

      final count = await _getCartonItemsCount(cartonId);
      await _supabase
          .from('package_cartons')
          .update({'items_count': count})
          .eq('id', cartonId);

      // ✅ FIX PROBLEM 11: Clear cache after adding item
      clearCache();

      log('✅ Item added to carton successfully');
    } catch (e) {
      log('❌ Error adding item: $e');
      throw Exception('Failed to add item: $e');
    }
  }

  // ================================
  // 8. GET CARTON ITEMS
  // ================================
  static Future<List<CartonItemDetail>> getCartonItems(String cartonId) async {
    try {
      final response = await _supabase
          .from('carton_items')
          .select('''
            id,
            carton_id,
            picklist_item_id,
            quantity,
            added_at,
            added_by,
            picklist:picklist_item_id (
              item_name,
              sku
            )
          ''')
          .eq('carton_id', cartonId)
          .order('added_at');

      return (response as List).map((json) {
        final picklistData = json['picklist'];
        return CartonItemDetail(
          id: json['id'] ?? '',
          cartonId: json['carton_id'] ?? '',
          picklistItemId: json['picklist_item_id'] ?? '',
          productName: picklistData?['item_name'] ?? 'Unknown Product',
          sku: picklistData?['sku'] ?? 'N/A',
          quantity: json['quantity'] ?? 0,
          addedAt: json['added_at'] != null
              ? DateTime.parse(json['added_at'])
              : DateTime.now(),
          addedBy: json['added_by'] ?? 'Unknown',
        );
      }).toList();
    } catch (e) {
      log('❌ Error fetching carton items: $e');
      return [];
    }
  }

  // ================================
  // 9. GET SESSION CARTONS
  // ================================
  static Future<List<PackageCarton>> getSessionCartons(String sessionId) async {
    try {
      final response = await _supabase
          .from('package_cartons')
          .select()
          .eq('packaging_session_id', sessionId)
          .order('box_number');

      return (response as List)
          .map((json) => PackageCarton.fromJson(json))
          .toList();
    } catch (e) {
      log('❌ Error fetching cartons: $e');
      return [];
    }
  }

  // ================================
  // 10. GET CURRENT OPEN CARTON ✅ FIXED
  // ================================
  static Future<PackageCarton?> getCurrentOpenCarton(String sessionId) async {
    try {
      final response = await _supabase
          .from('package_cartons')
          .select()
          .eq('packaging_session_id', sessionId)
          .eq('status', 'open')
          .order('box_number', ascending: true) // ✅ FIX: Explicit ascending order
          .limit(1)
          .maybeSingle();

      if (response != null) {
        log('✅ Found open carton: Box ${response['box_number']}');
      }
      return response != null ? PackageCarton.fromJson(response) : null;
    } catch (e) {
      log('❌ Error fetching open carton: $e');
      return null;
    }
  }

  // ================================
  // 11. SEAL CARTON
  // ================================
  static Future<void> sealCarton({
    required String cartonId,
    required double weight,
    required String operatorName,
  }) async {
    try {
      // ✅ FIX PROBLEM 7: Validate box has items before sealing
      final carton = await _supabase
          .from('package_cartons')
          .select('items_count')
          .eq('id', cartonId)
          .single();
      
      final itemsCount = carton['items_count'] as int? ?? 0;
      if (itemsCount == 0) {
        throw Exception('Cannot seal empty box. Please add items first.');
      }

      await _supabase.from('package_cartons').update({
        'status': 'sealed',
        'actual_weight': weight,
        'current_weight': weight,  // ✅ FIX: Also set current_weight
        'sealed_at': DateTime.now().toIso8601String(),
        'sealed_by': operatorName,
      }).eq('id', cartonId);

      // ✅ FIX PROBLEM 11: Clear cache after seal
      clearCache();

      log('✅ Carton sealed with $itemsCount items, Weight: $weight kg');
    } catch (e) {
      log('❌ Error sealing carton: $e');
      throw Exception('Failed to seal carton: $e');
    }
  }

  // ================================
  // 12. OPEN NEXT CARTON
  // ================================
  static Future<PackageCarton?> openNextCarton(String sessionId) async {
    try {
      final nextCarton = await _supabase
          .from('package_cartons')
          .select()
          .eq('packaging_session_id', sessionId)
          .eq('status', 'pending')
          .order('box_number')
          .limit(1)
          .maybeSingle();

      if (nextCarton != null) {
        await _supabase
            .from('package_cartons')
            .update({'status': 'open'})
            .eq('id', nextCarton['id']);
        
        // ✅ FIX PROBLEM 11: Clear cache after opening next box
        clearCache();
        
        log('✅ Opened Box ${nextCarton['box_number']}');
        return PackageCarton.fromJson({...nextCarton, 'status': 'open'});
      }

      log('✅ No more boxes to open');
      return null;
    } catch (e) {
      log('❌ Error opening next carton: $e');
      return null;
    }
  }

  // ================================
  // 13. COMPLETE SESSION
  // ================================
  static Future<void> completeSession(String sessionId) async {
    try {
      await _supabase.from('packaging_sessions').update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('session_id', sessionId);

      _picklistCache.clear();

      log('✅ Session completed');
    } catch (e) {
      log('❌ Error completing session: $e');
      throw Exception('Failed to complete session: $e');
    }
  }

  // ================================
  // 14. DELETE SESSION ✅ FIXED - Prevents reappearance in Ready tab
  // ================================
  static Future<void> deleteSession(String sessionId) async {
    try {
      log('🗑️ Deleting session: $sessionId');

      // ✅ FIX: Get order_id and status BEFORE deleting session
      final session = await _supabase
          .from('packaging_sessions')
          .select('order_id, status')
          .eq('session_id', sessionId)
          .single();

      final orderId = session['order_id'];
      final sessionStatus = session['status'];
      
      log('📋 Session details - Order: $orderId, Status: $sessionStatus');

      // Delete carton items
      final cartons = await _supabase
          .from('package_cartons')
          .select('id')
          .eq('packaging_session_id', sessionId);

      for (var carton in cartons as List) {
        await _supabase
            .from('carton_items')
            .delete()
            .eq('carton_id', carton['id']);
      }

      // Delete cartons
      await _supabase
          .from('package_cartons')
          .delete()
          .eq('packaging_session_id', sessionId);

      // Delete session
      await _supabase
          .from('packaging_sessions')
          .delete()
          .eq('session_id', sessionId);

      // ✅ CRITICAL FIX: Mark order as packaging_deleted
      // This prevents the order from reappearing in Ready tab
      await _supabase
          .from('customer_orders')
          .update({
            'packaging_deleted': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);

      _picklistCache.clear();

      log('✅ Session deleted - Order $orderId marked as packaging_deleted');
      log('✅ Order will NOT reappear in Ready tab');
    } catch (e) {
      log('❌ Delete error: $e');
      throw Exception('Failed to delete session: $e');
    }
  }

  // ================================
  // 14B. RESTORE DELETED ORDER (OPTIONAL) ✅ NEW
  // ================================
  static Future<void> restoreDeletedOrder(String orderId) async {
    try {
      log('🔄 Restoring deleted order: $orderId');

      // Check if order was actually deleted
      final order = await _supabase
          .from('customer_orders')
          .select('order_id, order_number, packaging_deleted')
          .eq('order_id', orderId)
          .single();

      if (order['packaging_deleted'] != true) {
        throw Exception('Order was not deleted');
      }

      // Restore the order
      await _supabase
          .from('customer_orders')
          .update({
            'packaging_deleted': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);

      _picklistCache.clear();

      log('✅ Order ${order['order_number']} restored to Ready tab');
    } catch (e) {
      log('❌ Restore error: $e');
      throw Exception('Failed to restore order: $e');
    }
  }

  // ================================
  // 15. DELETE ORDER
  // ================================
  static Future<void> deleteOrder(String orderId) async {
    try {
      log('🗑️ Deleting order: $orderId');

      final activeSession = await _supabase
          .from('packaging_sessions')
          .select()
          .eq('order_id', orderId)
          .eq('status', 'in_progress')
          .maybeSingle();

      if (activeSession != null) {
        throw Exception('Cannot delete order with active packaging session');
      }

      await _supabase
          .from('customer_orders')
          .update({'order_status': 'cancelled'})
          .eq('order_id', orderId);

      log('✅ Order marked as cancelled');
    } catch (e) {
      log('❌ Delete order error: $e');
      throw Exception('Failed to delete order: $e');
    }
  }

  // ================================
  // HELPER METHODS
  // ================================
  static Future<int> _getCartonItemsCount(String cartonId) async {
    try {
      final response = await _supabase
          .from('carton_items')
          .select('quantity')
          .eq('carton_id', cartonId);

      int total = 0;
      for (var item in response as List) {
        total += (item['quantity'] as int? ?? 0);
      }

      return total;
    } catch (e) {
      return 0;
    }
  }

  static void clearCache() {
    _picklistCache.clear();
    _lastCacheUpdate = null;
    log('✅ Cache cleared');
  }

  // ================================
  // 16. REOPEN CARTON ✅ NEW (FIX PROBLEM 14)
  // ================================
  static Future<void> reopenCarton(String cartonId) async {
    try {
      log('🔓 Reopening carton: $cartonId');

      // Close any other open cartons in the same session first
      final carton = await _supabase
          .from('package_cartons')
          .select('packaging_session_id')
          .eq('id', cartonId)
          .single();

      final sessionId = carton['packaging_session_id'];

      // Close all open cartons in this session
      await _supabase
          .from('package_cartons')
          .update({'status': 'sealed'})
          .eq('packaging_session_id', sessionId)
          .eq('status', 'open');

      // Reopen the target carton
      await _supabase
          .from('package_cartons')
          .update({
            'status': 'open',
            'sealed_at': null,
            'sealed_by': null,
          })
          .eq('id', cartonId);

      clearCache();
      log('✅ Carton reopened');
    } catch (e) {
      log('❌ Error reopening carton: $e');
      throw Exception('Failed to reopen carton: $e');
    }
  }

  // ================================
  // 17. DELETE CARTON ✅ NEW (FIX PROBLEM 1)
  // ================================
  static Future<void> deleteCarton(String cartonId, String sessionId) async {
    try {
      log('🗑️ Deleting carton: $cartonId');

      // Delete all items in the carton first
      await _supabase
          .from('carton_items')
          .delete()
          .eq('carton_id', cartonId);

      // Delete the carton
      await _supabase
          .from('package_cartons')
          .delete()
          .eq('id', cartonId);

      // Update session total cartons count
      final remainingCartons = await _supabase
          .from('package_cartons')
          .select('id')
          .eq('packaging_session_id', sessionId);

      await _supabase
          .from('packaging_sessions')
          .update({'total_cartons': (remainingCartons as List).length})
          .eq('session_id', sessionId);

      clearCache();
      log('✅ Carton deleted');
    } catch (e) {
      log('❌ Error deleting carton: $e');
      throw Exception('Failed to delete carton: $e');
    }
  }

  // ================================
  // 18. REMOVE ITEM FROM CARTON ✅ NEW (FIX PROBLEM 18)
  // ================================
  static Future<void> removeItemFromCarton(String cartonItemId, String cartonId) async {
    try {
      log('🗑️ Removing item from carton: $cartonItemId');

      // Delete the item
      await _supabase
          .from('carton_items')
          .delete()
          .eq('id', cartonItemId);

      // Update carton items count
      final count = await _getCartonItemsCount(cartonId);
      await _supabase
          .from('package_cartons')
          .update({'items_count': count})
          .eq('id', cartonId);

      clearCache();
      log('✅ Item removed from carton');
    } catch (e) {
      log('❌ Error removing item: $e');
      throw Exception('Failed to remove item: $e');
    }
  }
}
