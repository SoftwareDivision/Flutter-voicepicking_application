// lib/services/picklist_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'warehouse_service.dart';

class PicklistService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ================================
  // 1. CUSTOMER ORDER UPLOAD (FROM CSV)
  // ================================

  static Future<Map<String, dynamic>> receiveCustomerOrder({
    required String orderNumber,
    required String customerName,
    required String customerEmail,
    required String customerPhone,
    required String billToAddress,
    required String shipToAddress,
    required List<Map<String, dynamic>> orderItems,
    String? notes,
  }) async {
    try {
      log('🔄 Receiving customer order: $orderNumber');

      if (orderItems.isEmpty) {
        log('❌ Order validation failed: No items');
        return {'success': false, 'error': 'Order must contain at least one item'};
      }

      final orderData = {
        'order_number': orderNumber.toUpperCase().trim(),
        'customer_name': customerName.trim(),
        'customer_email': customerEmail.trim(),
        'customer_phone': customerPhone.trim(),
        'bill_to_address': billToAddress.trim(),
        'ship_to_address': shipToAddress.trim(),
        'order_status': 'pending',
        'order_date': DateTime.now().toIso8601String(),
        'notes': notes,
      };

      log('📝 Inserting order into customer_orders table...');
      final orderResult = await _supabase
          .from('customer_orders')
          .insert(orderData)
          .select('order_id')
          .single();

      final orderId = orderResult['order_id'];
      log('✅ Order created with ID: $orderId');

      log('📝 Inserting ${orderItems.length} order items...');
      final itemsData = orderItems.map((item) => {
        'order_id': orderId,
        'product_sku': item['sku'].toString().trim().toUpperCase(),
        'product_name': item['name']?.toString().trim(),
        'quantity_requested': item['quantity'] as int,
        'item_status': 'pending',
      }).toList();

      await _supabase.from('order_items').insert(itemsData);
      log('✅ ${itemsData.length} order items inserted');

      log('🔄 Starting order processing for automatic picklist generation...');
      final processResult = await _processOrderAndGeneratePicklist(orderId);

      log('📊 Processing result: ${processResult.toString()}');

      return {
        'success': true,
        'order_id': orderId,
        'order_number': orderNumber,
        'items_count': itemsData.length,
        'processing_result': processResult,
        'message': processResult['success'] 
            ? 'Order received and picklist generated successfully'
            : 'Order received but picklist generation failed',
      };
    } catch (e, stackTrace) {
      log('❌ Receive order error: $e');
      log('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'Failed to receive customer order',
        'details': e.toString(),
      };
    }
  }

  // ================================
  // 2. STOCK CHECK ACROSS ALL WAREHOUSES
  // ================================

  static Future<Map<String, dynamic>> _checkStockAvailability(
    String productSku,
    int quantityRequested
  ) async {
    try {
      log('🔍 Checking stock for SKU: $productSku, Requested Qty: $quantityRequested');

      final warehouses = await WarehouseService.getActiveWarehouses();
      log('📦 Found ${warehouses.length} active warehouses to check');

      List<Map<String, dynamic>> availableStock = [];
      int totalAvailable = 0;

      for (var warehouse in warehouses) {
        final warehouseId = warehouse['warehouse_id'];
        final warehouseName = warehouse['name'];

        log('🏢 Checking warehouse: $warehouseName ($warehouseId)');

        try {
          final inventoryItems = await _supabase
              .from('inventory')
              .select('id, name, sku, barcode, quantity, location, location_id, warehouse_id')
              .eq('sku', productSku.toUpperCase())
              .eq('warehouse_id', warehouseId)
              .eq('is_active', true)
              .gt('quantity', 0);

          log('📊 Found ${inventoryItems.length} inventory items for SKU $productSku in $warehouseName');

          for (var item in inventoryItems) {
            final availableQty = item['quantity'] as int;
            log('  ✓ Item: ${item['name']}, Available: $availableQty, Location: ${item['location']}');
            
            if (availableQty > 0) {
              availableStock.add({
                'warehouse_id': warehouseId,
                'warehouse_name': warehouseName,
                'inventory_id': item['id'],
                'product_name': item['name'],
                'barcode': item['barcode'],
                'location': item['location'] ?? 'Unknown',
                'location_id': item['location_id'],
                'available_quantity': availableQty,
              });
              totalAvailable += availableQty;
            }
          }
        } catch (e) {
          log('⚠️ Error checking warehouse $warehouseName: $e');
        }
      }

      final hasStock = totalAvailable >= quantityRequested;
      log(hasStock
          ? '✅ Stock available: $totalAvailable total units across ${availableStock.length} locations'
          : '❌ Insufficient stock: $totalAvailable available, $quantityRequested requested');

      return {
        'has_stock': hasStock,
        'total_available': totalAvailable,
        'quantity_requested': quantityRequested,
        'warehouses_with_stock': availableStock,
        'shortage': hasStock ? 0 : (quantityRequested - totalAvailable),
      };
    } catch (e, stackTrace) {
      log('❌ Stock check error: $e');
      log('Stack trace: $stackTrace');
      return {
        'has_stock': false,
        'total_available': 0,
        'error': e.toString(),
        'warehouses_with_stock': [],
      };
    }
  }

  // ================================
  // 3. PROCESS ORDER & AUTO-GENERATE PICKLIST
  // ================================

  static Future<Map<String, dynamic>> _processOrderAndGeneratePicklist(
    String orderId
  ) async {
    try {
      log('🔄 Processing order: $orderId');

      final orderItems = await _supabase
          .from('order_items')
          .select('*')
          .eq('order_id', orderId);

      log('📋 Found ${orderItems.length} items in order');

      if (orderItems.isEmpty) {
        throw Exception('No items found for order');
      }

      List<Map<String, dynamic>> picklistItems = [];
      List<Map<String, dynamic>> failedItems = [];
      String? assignedWarehouseId;

      for (var item in orderItems) {
        final sku = item['product_sku'];
        final quantityRequested = item['quantity_requested'] as int;
        final itemId = item['id'];

        log('🔍 Processing item: $sku (Qty: $quantityRequested)');

        final stockCheck = await _checkStockAvailability(sku, quantityRequested);

        if (stockCheck['has_stock'] == true) {
          final warehousesWithStock = stockCheck['warehouses_with_stock'] as List;

          if (warehousesWithStock.isEmpty) {
            log('⚠️ No warehouse data found despite has_stock being true');
            failedItems.add({
              'sku': sku,
              'requested': quantityRequested,
              'error': 'No warehouse data',
            });
            continue;
          }

          final selectedWarehouse = warehousesWithStock.first;
          assignedWarehouseId ??= selectedWarehouse['warehouse_id'];

          log('✅ Allocating from warehouse: ${selectedWarehouse['warehouse_name']}');

          picklistItems.add({
            'item_id': itemId,
            'inventory_id': selectedWarehouse['inventory_id'],
            'sku': sku,
            'product_name': selectedWarehouse['product_name'] ?? 'Unknown Product',
            'barcode': selectedWarehouse['barcode'] ?? '',
            'location': selectedWarehouse['location'] ?? 'Unknown',
            'quantity_requested': quantityRequested,
            'warehouse_id': selectedWarehouse['warehouse_id'],
            'warehouse_name': selectedWarehouse['warehouse_name'],
          });

          log('📝 Updating order item $itemId status to allocated');
          await _supabase
              .from('order_items')
              .update({
                'item_status': 'allocated',
                'inventory_id': selectedWarehouse['inventory_id'],
                'warehouse_id': selectedWarehouse['warehouse_id'],
                'location': selectedWarehouse['location'],
                'quantity_allocated': quantityRequested,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', itemId);
          
          log('✅ Order item updated successfully');
        } else {
          log('❌ Insufficient stock for SKU: $sku');
          failedItems.add({
            'sku': sku,
            'requested': quantityRequested,
            'available': stockCheck['total_available'],
            'shortage': stockCheck['shortage'],
          });

          await _supabase
              .from('order_items')
              .update({
                'item_status': 'cancelled',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', itemId);
        }
      }

      String orderStatus = 'processing';
      if (failedItems.isNotEmpty) {
        orderStatus = picklistItems.isEmpty ? 'cancelled' : 'partial';
      }

      log('📝 Updating order status to: $orderStatus');
      await _supabase
          .from('customer_orders')
          .update({
            'order_status': orderStatus,
            'assigned_warehouse_id': assignedWarehouseId,
            'processed_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);

      if (picklistItems.isNotEmpty) {
        log('🎯 Generating picklist for ${picklistItems.length} items...');
        final picklistResult = await _generatePicklist(
          orderId: orderId,
          warehouseId: assignedWarehouseId!,
          items: picklistItems,
        );

        log('✅ Picklist generation complete');

        return {
          'success': true,
          'order_status': orderStatus,
          'picklist_generated': true,
          'picklist_result': picklistResult,
          'allocated_items': picklistItems.length,
          'failed_items': failedItems.length,
          'failures': failedItems,
        };
      } else {
        log('❌ No items could be allocated');
        return {
          'success': false,
          'order_status': 'cancelled',
          'picklist_generated': false,
          'message': 'No items could be allocated - insufficient stock',
          'failures': failedItems,
        };
      }
    } catch (e, stackTrace) {
      log('❌ Process order error: $e');
      log('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'Failed to process order',
        'details': e.toString(),
      };
    }
  }

  // ================================
  // 4. GENERATE PICKLIST
  // ================================

  static Future<Map<String, dynamic>> _generatePicklist({
    required String orderId,
    required String warehouseId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      log('🔄 Generating picklist for order: $orderId');

      final orderNumber = await _getOrderNumber(orderId);
      final waveNumber = 'WAVE_${orderNumber}_${DateTime.now().millisecondsSinceEpoch}';

      log('📋 Wave number: $waveNumber');

      List<dynamic> picklistIds = [];

      for (var item in items) {
        final picklistData = {
          'warehouse_id': warehouseId,
          'inventory_id': item['inventory_id'],
          'order_id': orderId,
          'wave_number': waveNumber,
          'picker_name': 'Auto-Assigned',
          'quantity_requested': item['quantity_requested'],
          'quantity_picked': 0,
          'location': item['location'],
          'location_check_digit': _generateLocationCheckDigit(item['location']),
          'barcode_check_digit': _generateBarcodeCheckDigit(item['barcode'] ?? ''),
          'barcode_number': item['barcode'],
          'status': 'pending',
          'priority': 'normal',
          'item_name': item['product_name'],
          'sku': item['sku'],
          'barcode': item['barcode'],
          'available_quantity': item['quantity_requested'],
          'voice_ready': true,
          'voice_instructions': 'Pick ${item['quantity_requested']} units of ${item['product_name']} from ${item['location']}',
          'created_at': DateTime.now().toIso8601String(),
        };

        log('📝 Inserting picklist item for SKU: ${item['sku']}');

        final result = await _supabase
            .from('picklist')
            .insert(picklistData)
            .select('id')
            .single();

        picklistIds.add(result['id']);
        log('✅ Picklist item created with ID: ${result['id']}');
      }

      log('🎉 Picklist generated successfully: ${picklistIds.length} items');
      return {
        'success': true,
        'picklist_ids': picklistIds,
        'wave_number': waveNumber,
        'items_count': items.length,
      };
    } catch (e, stackTrace) {
      log('❌ Generate picklist error: $e');
      log('Stack trace: $stackTrace');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Helper methods
  static Future<String> _getOrderNumber(String orderId) async {
    try {
      final order = await _supabase
          .from('customer_orders')
          .select('order_number')
          .eq('order_id', orderId)
          .single();
      return order['order_number'];
    } catch (e) {
      log('⚠️ Could not fetch order number: $e');
      return 'UNKNOWN';
    }
  }

  static String _generateLocationCheckDigit(String locationCode) {
    String numericPart = locationCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericPart.length >= 2) {
      return numericPart.substring(numericPart.length - 2);
    }
    return '00';
  }

  static String _generateBarcodeCheckDigit(String barcode) {
    String numericPart = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericPart.length >= 3) {
      return numericPart.substring(numericPart.length - 3);
    }
    return '000';
  }
}
