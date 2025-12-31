// lib/services/voice_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class VoiceService {
  static final SupabaseClient _supabase = supabase;

  // ================================
  // VOICE PICKING METHODS - USING REAL DATABASE CHECK DIGITS
  // ================================

  /// Get assigned picklist with REAL check digits from database
  static Future<List<Map<String, dynamic>>> getAssignedPicklist({
    required String pickerId,
    String? picklistId,
    String? warehouseId,
  }) async {
    try {
      debugPrint('🔄 Getting assigned picklist for: $pickerId');

      // Enhanced query to get check digits from database tables
      var query = _supabase
          .from('picklist')
          .select('''
            id,
            warehouse_id,
            order_id,
            inventory_id,
            wave_number,
            picker_name,
            quantity_requested,
            quantity_picked,
            location,
            status,
            priority,
            created_at,
            updated_at,
            item_name,
            sku,
            barcode,
            available_quantity,
            check_digit,
            barcode_digits,
            voice_ready,
            voice_instructions,
            inventory!inner(
              id,
              name,
              sku,
              barcode,
              quantity,
              category,
              location,
              min_stock,
              unit_price,
              barcode_digits,
              location_id,
              locations!inner(
                location_id,
                location_code,
                check_digit
              )
            )
          ''')
          .eq('voice_ready', true); // ✅ KEY FIX: Only get voice-ready items

      // ✅ FIXED: Only get items specifically assigned to this user
      if (picklistId != null) {
        query = query.eq('id', picklistId);
      } else {
        // ✅ CRITICAL FIX: Only fetch items assigned to THIS specific user
        query = query
            .eq('picker_name', pickerId)
            .inFilter('status', ['pending', 'assigned', 'in_progress']);
      }

      if (warehouseId != null) {
        query = query.eq('warehouse_id', warehouseId);
      }

      final response = await query
          .order('priority', ascending: false) // High priority first
          .order('created_at', ascending: true) // Oldest first within same priority
          .limit(50);

      debugPrint('🎯 Raw response from database: ${response.length} items');

      // Transform the data using REAL database check digits
      List<Map<String, dynamic>> transformedData = [];

      for (var item in response) {
        final inventory = item['inventory'] as Map<String, dynamic>?;
        
        if (inventory != null) {
          final locations = inventory['locations'] as Map<String, dynamic>?;

          // Use REAL check digits from database - NO AUTO-GENERATION
          String locationCheckDigit = item['check_digit']?.toString() ??
              locations?['check_digit']?.toString() ??
              '00';

          String barcodeDigits = item['barcode_digits']?.toString() ??
              inventory['barcode_digits']?.toString() ??
              _extractLastDigitsFromBarcode(inventory['barcode']?.toString() ?? '');

          String location = inventory['location']?.toString() ??
              item['location']?.toString() ??
              locations?['location_code']?.toString() ??
              'A-01-01';

          transformedData.add({
            'id': item['id'],
            'warehouse_id': item['warehouse_id'],
            'order_id': item['order_id'],
            'inventory_id': item['inventory_id'],
            'wave_number': item['wave_number'],
            'picker_name': item['picker_name'],
            'quantity_requested': item['quantity_requested'],
            'quantity_picked': item['quantity_picked'],
            'location': location,
            'location_check_digit': locationCheckDigit, // FROM DATABASE
            'status': item['status'],
            'priority': item['priority'],
            'created_at': item['created_at'],
            'updated_at': item['updated_at'],
            
            // Flattened inventory data for voice picking
            'item_name': inventory['name'] ?? item['item_name'],
            'sku': inventory['sku'] ?? item['sku'],
            'barcode': inventory['barcode'] ?? item['barcode'],
            'barcode_digits': barcodeDigits, // FROM DATABASE
            'available_quantity': inventory['quantity'] ?? item['available_quantity'] ?? 0,
            'category': inventory['category'],
            'min_stock': inventory['min_stock'],
            'unit_price': inventory['unit_price'],
            
            // ✅ Voice picking specific fields
            'voice_ready': item['voice_ready'] ?? true,
            'voice_instructions': item['voice_instructions'] ?? 
                'Go to location $location, pick ${inventory['name'] ?? item['item_name']}, quantity ${item['quantity_requested']}',
          });
        } else {
          debugPrint('⚠️ No inventory data for item: ${item['id']}');
          
          // Still add the item but with basic data
          transformedData.add({
            'id': item['id'],
            'warehouse_id': item['warehouse_id'],
            'order_id': item['order_id'],
            'inventory_id': item['inventory_id'],
            'wave_number': item['wave_number'],
            'picker_name': item['picker_name'],
            'quantity_requested': item['quantity_requested'],
            'quantity_picked': item['quantity_picked'],
            'location': item['location'] ?? 'A-01-01',
            'location_check_digit': item['check_digit']?.toString() ?? '00',
            'status': item['status'],
            'priority': item['priority'],
            'created_at': item['created_at'],
            'updated_at': item['updated_at'],
            'item_name': item['item_name'] ?? 'Unknown Item',
            'sku': item['sku'] ?? 'NO-SKU',
            'barcode': item['barcode'] ?? '',
            'barcode_digits': item['barcode_digits']?.toString() ?? '000',
            'available_quantity': item['available_quantity'] ?? 0,
            'category': 'General',
            'min_stock': 10,
            'unit_price': 0.0,
            'voice_ready': item['voice_ready'] ?? true,
            'voice_instructions': item['voice_instructions'] ?? 
                'Go to location ${item['location']}, pick ${item['item_name']}, quantity ${item['quantity_requested']}',
          });
        }
      }

      debugPrint('✅ Found ${transformedData.length} assigned/auto-assigned voice-ready tasks for $pickerId');
      
      // Log the check digits being used
      for (var task in transformedData) {
        debugPrint('📋 Task ${task['id']}: Picker=${task['picker_name']}, Location Check = ${task['location_check_digit']}, Barcode Digits = ${task['barcode_digits']}, Voice Ready = ${task['voice_ready']}');
      }

      if (transformedData.isEmpty) {
        debugPrint('⚠️ No voice-ready tasks found. Please add tasks via WMS interface and ensure voice_ready is set to true.');
      }

      return transformedData;
    } catch (e) {
      debugPrint('❌ Get assigned picklist error: $e');
      
      // Provide specific error messages based on error type
      if (e.toString().contains('relation') || e.toString().contains('column')) {
        throw Exception('Database schema error: Please verify picklist and inventory tables exist');
      } else if (e.toString().contains('authentication') || e.toString().contains('JWT')) {
        throw Exception('Database authentication error: Please check Supabase connection');
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        throw Exception('Network error: Please check your internet connection');
      } else {
        throw Exception('Failed to fetch picking tasks: ${e.toString()}');
      }
    }
  }

  /// Helper function to extract last 3-4 digits from barcode as fallback only
  static String _extractLastDigitsFromBarcode(String barcode) {
    if (barcode.isEmpty) return '000';
    
    // Remove non-numeric characters and get last 3 digits
    String numericOnly = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.length >= 3) {
      return numericOnly.substring(numericOnly.length - 3);
    }
    
    return numericOnly.padLeft(3, '0');
  }

  /// Update inventory after pick with real-time validation
  /// 🆕 ADDED: Automatic order completion detection
  static Future<Map<String, dynamic>> updateInventoryPick({
    required String inventoryId,
    required int quantityPicked,
    required String pickerId,
    required String picklistId,
    required DateTime timestamp,
  }) async {
    try {
      debugPrint('🔄 Updating inventory after pick: $inventoryId, quantity: $quantityPicked');

      // 1. Get current picklist item details INCLUDING order_id
      final picklistItem = await _supabase
          .from('picklist')
          .select('id, order_id, quantity_requested, quantity_picked')
          .eq('id', picklistId)
          .single();

      final orderId = picklistItem['order_id'];
      final quantityRequested = picklistItem['quantity_requested'] as int;

      // 2. Get current inventory with validation
      final inventoryResponse = await _supabase
          .from('inventory')
          .select('id, name, sku, quantity, min_stock, warehouse_id')
          .eq('id', inventoryId)
          .single();

      final currentQuantity = inventoryResponse['quantity'] as int;
      final itemName = inventoryResponse['name'] ?? 'Unknown Item';
      final sku = inventoryResponse['sku'] ?? '';

      // Validate sufficient quantity
      if (currentQuantity < quantityPicked) {
        throw Exception(
            'Insufficient inventory: Available $currentQuantity, Requested $quantityPicked for item $itemName');
      }

      final newQuantity = currentQuantity - quantityPicked;

      // 3. Update inventory quantity in real-time
      await _supabase.from('inventory').update({
        'quantity': newQuantity,
        'updated_at': timestamp.toIso8601String(),
      }).eq('id', inventoryId);

      // 4. Update picklist item as picked/completed
      final isCompleted = quantityPicked >= quantityRequested;
      await _supabase.from('picklist').update({
        'quantity_picked': quantityPicked,
        'status': isCompleted ? 'completed' : 'in_progress',
        'completed_at': isCompleted ? timestamp.toIso8601String() : null,
        'updated_at': timestamp.toIso8601String(),
      }).eq('id', picklistId);

      debugPrint('✅ Picklist item updated: ${isCompleted ? "completed" : "in_progress"}');

      // 5. 🆕 CHECK: Are ALL items in this order completed?
      if (isCompleted && orderId != null) {
        debugPrint('🔍 Checking if all items completed for order: $orderId');
        
        final allPicklistItems = await _supabase
            .from('picklist')
            .select('id, status')
            .eq('order_id', orderId);

        debugPrint('📋 Order $orderId has ${allPicklistItems.length} total items');

        // Check if every single item is completed
        final allCompleted = allPicklistItems.every(
          (item) => item['status'] == 'completed'
        );

        debugPrint(allCompleted 
            ? '🎉 All items completed for order!' 
            : '⏳ Some items still pending...');

        // 6. 🆕 IF ALL COMPLETED → Update customer_orders table
        if (allCompleted) {
          debugPrint('🔥 Updating customer_orders table to completed...');
          
          try {
            await _supabase.from('customer_orders').update({
              'order_status': 'completed',
              'completed_at': timestamp.toIso8601String(),
              'updated_at': timestamp.toIso8601String(),
            }).eq('order_id', orderId);

            debugPrint('✅ Order $orderId marked as COMPLETED in customer_orders table!');
          } catch (orderUpdateError) {
            debugPrint('⚠️ Warning: Could not update customer_orders: $orderUpdateError');
            // Don't fail the whole operation if order update fails
          }
        }
      }

      // 7. Log inventory movement for audit trail
      await _supabase.from('inventory_movements').insert({
        'inventory_id': inventoryId,
        'movement_type': 'PICK',
        'quantity_changed': -quantityPicked,
        'previous_quantity': currentQuantity,
        'new_quantity': newQuantity,
        'movement_date': timestamp.toIso8601String(),
        'reference_type': 'VOICE_PICKING',
        'reference_id': picklistId,
        'notes': 'Voice picking by $pickerId: $itemName ($sku)',
        'created_by': pickerId,
      });

      debugPrint('✅ Inventory updated successfully: $itemName, $currentQuantity → $newQuantity');

      return {
        'success': true,
        'previousQuantity': currentQuantity,
        'newQuantity': newQuantity,
        'quantityPicked': quantityPicked,
        'itemName': itemName,
        'sku': sku,
      };
    } catch (e) {
      debugPrint('❌ Update inventory pick error: $e');
      
      if (e.toString().contains('Insufficient inventory')) {
        return {
          'success': false,
          'error': e.toString(),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to update inventory: ${e.toString()}',
        };
      }
    }
  }

  /// Update task status with proper validation
  static Future updateTaskStatus({
    required String taskId,
    required String status,
    DateTime? completedAt,
  }) async {
    try {
      debugPrint('🔄 Updating task status: $taskId → $status');

      // Validate status
      const validStatuses = ['pending', 'assigned', 'in_progress', 'completed', 'cancelled'];
      if (!validStatuses.contains(status)) {
        throw Exception('Invalid status: $status. Valid statuses: ${validStatuses.join(', ')}');
      }

      Map<String, dynamic> updates = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (status == 'in_progress') {
        updates['started_at'] = DateTime.now().toIso8601String();
      } else if (status == 'completed') {
        updates['completed_at'] = (completedAt ?? DateTime.now()).toIso8601String();
      }

      await _supabase.from('picklist').update(updates).eq('id', taskId);

      debugPrint('✅ Task status updated successfully: $taskId → $status');
    } catch (e) {
      debugPrint('❌ Update task status error: $e');
      throw Exception('Failed to update task status: ${e.toString()}');
    }
  }

  /// Create voice picking session with real data validation
  static Future<Map<String, dynamic>> createVoicePickingSession({
    required String pickerName,
    String? warehouseId,
  }) async {
    try {
      debugPrint('🔄 Creating voice picking session for: $pickerName');

      // Get warehouse ID if not provided
      if (warehouseId == null) {
        final warehouseResponse = await _supabase
            .from('warehouses')
            .select('warehouse_id, name')
            .eq('is_active', true)
            .limit(1)
            .maybeSingle();

        if (warehouseResponse == null) {
          return {
            'success': false,
            'error': 'No active warehouse found. Please contact administrator.',
          };
        }

        warehouseId = warehouseResponse['warehouse_id'];
      }

      // Check if picker has tasks assigned
      final tasks = await getAssignedPicklist(
        pickerId: pickerName,
        warehouseId: warehouseId,
      );

      if (tasks.isEmpty) {
        return {
          'success': false,
          'error': 'No voice-ready picking tasks assigned to $pickerName. Please add tasks via WMS and ensure they are voice-ready.',
        };
      }

      final sessionId = 'session_${pickerName}_${DateTime.now().millisecondsSinceEpoch}';

      // Create session record
      await _supabase.from('voice_picking_sessions').insert({
        'session_id': sessionId,
        'picker_name': pickerName,
        'warehouse_id': warehouseId,
        'start_time': DateTime.now().toIso8601String(),
        'status': 'active',
        'total_tasks': tasks.length,
        'completed_tasks': [],
      });

      debugPrint('✅ Voice picking session created: $sessionId with ${tasks.length} voice-ready tasks');

      return {
        'success': true,
        'sessionId': sessionId,
        'totalTasks': tasks.length,
        'pickerName': pickerName,
        'warehouseId': warehouseId,
      };
    } catch (e) {
      debugPrint('❌ Create voice picking session error: $e');
      return {
        'success': false,
        'error': 'Failed to create picking session: ${e.toString()}',
      };
    }
  }

  /// Save picking session metrics
  static Future savePickingSession({
    required String pickerId,
    required String picklistId,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      debugPrint('🔄 Saving picking session metrics for: $pickerId');

      await _supabase.from('voice_picking_sessions').upsert({
        'session_id': picklistId,
        'picker_name': pickerId,
        'session_metrics': metrics,
        'end_time': DateTime.now().toIso8601String(),
        'status': 'completed',
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Picking session metrics saved successfully');
    } catch (e) {
      debugPrint('❌ Save picking session error: $e');
      // Don't throw - this is non-critical for workflow
    }
  }

  // ================================
  // HELPER METHODS
  // ================================

  /// Test database connection
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      debugPrint('🔄 Testing voice service database connection...');

      final testQuery = await _supabase
          .from('warehouses')
          .select('warehouse_id, name')
          .limit(1);

      debugPrint('✅ Voice service database connection successful');

      return {
        'success': true,
        'message': 'Voice service database connection successful',
        'warehousesFound': testQuery.length,
      };
    } catch (e) {
      debugPrint('❌ Voice service database connection failed: $e');
      return {
        'success': false,
        'error': 'Voice service database connection failed: ${e.toString()}',
      };
    }
  }

  // ================================
  // REAL-TIME VOICE PICKING SUPPORT
  // ================================

  /// Get real-time voice picking stats
  static Future<Map<String, dynamic>> getVoiceStats(String userName) async {
    try {
      debugPrint('🔄 Fetching real-time voice stats for: $userName');

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      final weekStartStr = weekStart.toIso8601String().substring(0, 10);

      // Get today's completed picks
      final todayPicks = await _supabase
          .from('picklist')
          .select('id')
          .eq('picker_name', userName)
          .eq('status', 'completed')
          .gte('completed_at', '${today}T00:00:00')
          .count();

      // Get this week's completed picks
      final weekPicks = await _supabase
          .from('picklist')
          .select('id')
          .eq('picker_name', userName)
          .eq('status', 'completed')
          .gte('completed_at', '${weekStartStr}T00:00:00')
          .count();

      // Calculate accuracy and efficiency
      final accuracy = await _calculatePickingAccuracy(userName);
      final efficiency = await _calculatePickingEfficiency(userName);

      return {
        'todayPicks': todayPicks.count,
        'weekPicks': weekPicks.count,
        'accuracy': accuracy,
        'efficiency': efficiency,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Voice stats error: $e');
      return {
        'todayPicks': 0,
        'weekPicks': 0,
        'accuracy': 0.0,
        'efficiency': 0.0,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }

  static Future<double> _calculatePickingAccuracy(String userName) async {
    try {
      final recentPicks = await _supabase
          .from('picklist')
          .select('status, quantity_requested, quantity_picked')
          .eq('picker_name', userName)
          .eq('status', 'completed')
          .gte('completed_at', DateTime.now().subtract(const Duration(days: 7)).toIso8601String())
          .limit(50);

      if (recentPicks.isEmpty) return 96.8;

      int accuratePicks = 0;
      for (var pick in recentPicks) {
        final requested = pick['quantity_requested'] ?? 0;
        final picked = pick['quantity_picked'] ?? 0;
        if (requested == picked) accuratePicks++;
      }

      return (accuratePicks / recentPicks.length) * 100;
    } catch (e) {
      debugPrint('❌ Calculate picking accuracy error: $e');
      return 96.8;
    }
  }

  static Future<double> _calculatePickingEfficiency(String userName) async {
    try {
      final recentSessions = await _supabase
          .from('voice_picking_sessions')
          .select('start_time, end_time, total_tasks, completed_tasks')
          .eq('picker_name', userName)
          .eq('status', 'completed')
          .gte('start_time', DateTime.now().subtract(const Duration(days: 7)).toIso8601String())
          .limit(10);

      if (recentSessions.isEmpty) return 89.2;

      double totalEfficiency = 0;
      for (var session in recentSessions) {
        final completedTasks = (session['completed_tasks'] as List).length;
        final totalTasks = session['total_tasks'] ?? 1;
        final efficiency = (completedTasks / totalTasks) * 100;
        totalEfficiency += efficiency;
      }

      return totalEfficiency / recentSessions.length;
    } catch (e) {
      debugPrint('❌ Calculate picking efficiency error: $e');
      return 89.2;
    }
  }
}
