// lib/services/warehouse_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:convert'; // ✅ ADDED: For JSON parsing
import 'dart:math' as math; // ✅ ADDED: For min function (aliased to avoid conflict with log)

class WarehouseService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ✅ CHANGE 1: Make supabase client publicly accessible
  static SupabaseClient get supabaseClient => _supabase;

  // Current warehouse tracking
  static String? _currentWarehouseId;

  // ✅ CHANGE 2: Public getter (already exists, keeping it)
  static String? get currentWarehouseId => _currentWarehouseId;

  // ================================
  // WAREHOUSE MANAGEMENT
  // ================================

  /// Get list of active warehouses
  static Future<List<Map<String, dynamic>>> getActiveWarehouses() async {
    try {
      log('🔄 Fetching active warehouses...');
      final response = await _supabase
          .from('warehouses')
          .select('*')
          .eq('is_active', true)
          .order('name');

      log('✅ Found ${response.length} active warehouses');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Error fetching active warehouses: $e');
      return [
        {
          'warehouse_id': 'default',
          'name': 'Main Warehouse',
          'location': 'Default Location',
          'is_active': true
        }
      ];
    }
  }

  /// Set current warehouse for operations
  static Future<bool> setCurrentWarehouse(String warehouseId) async {
    try {
      log('🔄 Setting current warehouse: $warehouseId');
      final warehouse = await _supabase
          .from('warehouses')
          .select()
          .eq('warehouse_id', warehouseId)
          .maybeSingle();

      if (warehouse != null) {
        _currentWarehouseId = warehouseId;
        log('✅ Current warehouse set: ${warehouse['name']}');
        return true;
      }

      log('❌ Warehouse not found: $warehouseId');
      return false;
    } catch (e) {
      log('❌ Error setting warehouse: $e');
      return false;
    }
  }

  // ✅ CHANGE 3: ADD NEW FUNCTION - Auto-initialize warehouse if not set
  static Future<String?> ensureWarehouseIsSet() async {
    if (_currentWarehouseId != null) {
      log('✅ Warehouse already set: $_currentWarehouseId');
      return _currentWarehouseId;
    }

    log('⚠️ No warehouse set, attempting auto-initialization...');
    try {
      final warehouses = await getActiveWarehouses();
      if (warehouses.isNotEmpty) {
        final firstWarehouse = warehouses[0];
        final warehouseId = firstWarehouse['warehouse_id'] as String?;
        if (warehouseId != null) {
          await setCurrentWarehouse(warehouseId);
          log('✅ Auto-selected warehouse: ${firstWarehouse['name']}');
          return warehouseId;
        }
      }
      log('❌ No active warehouses available');
      return null;
    } catch (e) {
      log('❌ Failed to auto-initialize warehouse: $e');
      return null;
    }
  }

  /// Get default warehouse ID
  static Future<String?> _getDefaultWarehouseId() async {
    try {
      if (_currentWarehouseId != null) {
        return _currentWarehouseId;
      }

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

  /// Test database connection
  static Future<bool> testConnection() async {
    try {
      log('🔄 Testing database connection...');
      await _supabase.from('warehouses').select('warehouse_id').limit(1);
      log('✅ Database connection successful');
      return true;
    } catch (e) {
      log('❌ Database connection failed: $e');
      return false;
    }
  }

  // ================================
  // LOCATION MANAGEMENT
  // ================================

  /// Generate location check digit
  static String _generateLocationCheckDigit(String locationCode) {
    try {
      String numericPart = locationCode.replaceAll(RegExp(r'[^0-9]'), '');
      if (numericPart.length >= 2) {
        return numericPart.substring(numericPart.length - 2);
      }

      int sum = 0;
      for (int i = 0; i < locationCode.length; i++) {
        sum += locationCode.codeUnitAt(i);
      }

      return (sum % 100).toString().padLeft(2, '0');
    } catch (e) {
      log('Error generating location check digit: $e');
      return '00';
    }
  }

  /// Generate barcode check digit
  static String _generateBarcodeCheckDigit(String barcode) {
    try {
      String numericPart = barcode.replaceAll(RegExp(r'[^0-9]'), '');
      if (numericPart.length >= 3) {
        return numericPart.substring(numericPart.length - 3);
      }

      int sum = 0;
      for (int i = 0; i < barcode.length; i++) {
        sum += barcode.codeUnitAt(i);
      }

      return (sum % 1000).toString().padLeft(3, '0');
    } catch (e) {
      log('Error generating barcode check digit: $e');
      return '000';
    }
  }

  /// Validate location with check digit generation
  static Future<Map<String, dynamic>> validateLocation(String locationCode) async {
    try {
      log('🔄 Validating location: $locationCode');
      final upperLocationCode = locationCode.trim().toUpperCase();

      final locationExists = await _supabase
          .from('locations')
          .select('location_id, location_code, check_digit, zone, aisle, shelf, warehouse_id')
          .eq('location_code', upperLocationCode)
          .eq('is_active', true)
          .maybeSingle();

      if (locationExists != null) {
        return {
          'exists': true,
          'location': locationExists,
          'check_digit': locationExists['check_digit'] ?? _generateLocationCheckDigit(upperLocationCode),
          'message': 'Location $upperLocationCode validated',
          'voice_message': 'Location confirmed'
        };
      }

      // Check legacy table
      final legacyLocation = await _supabase
          .from('location_table')
          .select('location_id, location_code, check_digit')
          .eq('location_code', upperLocationCode)
          .maybeSingle();

      if (legacyLocation != null) {
        return {
          'exists': true,
          'location': legacyLocation,
          'check_digit': legacyLocation['check_digit'] ?? _generateLocationCheckDigit(upperLocationCode),
          'message': 'Location $upperLocationCode validated (legacy)',
          'voice_message': 'Location confirmed'
        };
      }

      return {
        'exists': false,
        'suggested_check_digit': _generateLocationCheckDigit(upperLocationCode),
        'message': 'Location $upperLocationCode not found',
        'voice_message': 'Location not found'
      };
    } catch (e) {
      log('❌ Location validation error: $e');
      return {
        'exists': false,
        'error': e.toString(),
        'message': 'Database error during validation',
        'voice_message': 'Validation error'
      };
    }
  }

  /// Add new location
  static Future<Map<String, dynamic>> addLocation(String locationCode) async {
    try {
      log('🔄 Adding new location: $locationCode');
      final warehouseId = await _getDefaultWarehouseId();
      if (warehouseId == null) {
        throw Exception('No active warehouse found');
      }

      final upperLocationCode = locationCode.trim().toUpperCase();
      final locationParts = upperLocationCode.split('-');

      String zone = locationParts.isNotEmpty ? locationParts[0] : 'A';
      String aisle = locationParts.length > 1 ? locationParts[1] : '01';
      String shelf = locationParts.length > 2 ? locationParts[2] : '01';

      final checkDigit = _generateLocationCheckDigit(upperLocationCode);

      final newLocation = {
        'location_code': upperLocationCode,
        'zone': zone,
        'aisle': aisle,
        'shelf': shelf,
        'check_digit': checkDigit,
        'warehouse_id': warehouseId,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      };

      final result = await _supabase
          .from('locations')
          .insert(newLocation)
          .select()
          .single();

      // Also add to legacy table
      try {
        await _supabase.from('location_table').insert({
          'location_code': upperLocationCode,
          'check_digit': checkDigit,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (legacyError) {
        log('⚠️ Legacy table insert failed (non-critical): $legacyError');
      }

      return {
        'success': true,
        'location': result,
        'check_digit': checkDigit,
        'message': 'Location $upperLocationCode added successfully',
        'voice_message': 'Location added'
      };
    } catch (e) {
      log('❌ Add location error: $e');
      return _handleDatabaseError(e, 'add location');
    }
  }

  // ================================
  // PRODUCT PARSING & MANAGEMENT
  // ================================

  /// Generate professional product name
  static String _generateProfessionalProductName(String barcode, String? description) {
    try {
      if (description != null &&
          description.isNotEmpty &&
          !description.contains('Scanned Item') &&
          !description.contains('Item scanned via')) {
        String name = description.split(' (')[0].split(' |')[0].trim();
        if (name.length >= 3 && name.length <= 100) {
          return name;
        }
      }

      String cleanBarcode = barcode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (cleanBarcode.length >= 6) {
        return "Product-${cleanBarcode.substring(cleanBarcode.length - 6)}";
      } else {
        return "Product-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
      }
    } catch (e) {
      log('Error generating professional product name: $e');
      return "Product-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    }
  }

  // ✅✅✅ UPDATED: UNIVERSAL QR PARSER - PRODUCTION READY ✅✅✅
  /// Parse product details from barcode/QR - UNIVERSAL PARSER v3.0
  /// Handles: JSON, Pipe-separated, Key-Value, Line-by-line, Simple barcode formats
  static Map<String, dynamic> parseProductDetailsFromBarcode(String scannedData) {
    try {
      // ✅✅✅ CRITICAL DEBUG - ADD THIS FIRST ✅✅✅
      log('🔍 RAW SCANNED DATA RECEIVED:');
      log('Length: ${scannedData.length} characters');
      log('First 200 chars: ${scannedData.substring(0, min(200, scannedData.length))}');
      log('Contains "Product Details": ${scannedData.contains('Product Details')}');
      log('Contains "Price:": ${scannedData.contains('Price:')}');
      log('Contains "Unit Price:": ${scannedData.contains('Unit Price:')}');
      log('Contains newlines: ${scannedData.contains('\n')}');
      log('Full data:\n$scannedData');
      log('=' * 80);
      // ✅✅✅ END DEBUG ✅✅✅
      
      log('🔍 Parsing scanned data: ${scannedData.length} chars');
      
      String cleanData = scannedData.trim();
      
      // Initialize result with defaults
      Map<String, dynamic> result = {
        'barcode': '',
        'name': 'Unknown Product',
        'sku': '',
        'description': 'Professional warehouse product',
        'itemid': '',
        'itemno': '',
        'quantity': 1,
        'category': 'General',
        'brand': '',
        'unitprice': 0.0,
      };

      // **DETECTION 1: JSON Format**
      if (cleanData.startsWith('{') && cleanData.endsWith('}')) {
        try {
          final Map<String, dynamic> jsonData = json.decode(cleanData);
          
          result['name'] = jsonData['name'] ?? jsonData['productName'] ?? result['name'];
          result['sku'] = jsonData['sku'] ?? jsonData['itemNo'] ?? '';
          result['barcode'] = jsonData['barcode'] ?? jsonData['productId'] ?? '';
          result['description'] = jsonData['description'] ?? result['description'];
          result['category'] = jsonData['category'] ?? result['category'];
          result['brand'] = jsonData['brand'] ?? '';
          result['quantity'] = jsonData['quantity'] ?? 1;
          result['unitprice'] = (jsonData['unitPrice'] ?? jsonData['price'] ?? 0.0).toDouble();
          
          log('✅ JSON format detected and parsed');
          return _finalizeParseResult(result);
        } catch (e) {
          log('⚠️ JSON parsing failed: $e');
        }
      }

      // **DETECTION 2: Pipe-Separated Format (PRODUCTID|NAME|SKU|BARCODE)**
      if (cleanData.contains('|')) {
        return _parsePipeSeparatedFormat(cleanData, result);
      }

      // **DETECTION 3: Key-Value Pair Format (NAME:value, SKU:value)**
      if (cleanData.contains(':') || cleanData.contains('=')) {
        return _parseKeyValueFormat(cleanData, result);
      }

      // **DETECTION 4: Line-by-Line Format (Your current expected format)**
      if (cleanData.contains('\n') || cleanData.contains('Product Details')) {
        return _parseLineByLineFormat(cleanData, result);
      }

      // **DETECTION 5: Simple Barcode (just numbers/letters)**
      return _parseSimpleBarcodeFormat(cleanData, result);

    } catch (e, stackTrace) {
      log('❌ Critical parser error: $e');
      log('Stack trace: $stackTrace');
      return _generateFallbackResult(scannedData);
    }
  }

  // Helper: Parse PRODUCTID|NAME|SKU|BARCODE format
  static Map<String, dynamic> _parsePipeSeparatedFormat(String data, Map<String, dynamic> result) {
    try {
      log('📋 Parsing pipe-separated format');
      
      // Extract field pairs
      final parts = data.split('|');
      
      for (String part in parts) {
        part = part.trim();
        
        if (part.toUpperCase().startsWith('PRODUCTID')) {
          result['barcode'] = part.replaceFirst(RegExp(r'PRODUCTID', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('NAME')) {
          result['name'] = part.replaceFirst(RegExp(r'NAME', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('SKU')) {
          result['sku'] = part.replaceFirst(RegExp(r'SKU', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('BARCODE')) {
          result['barcode'] = part.replaceFirst(RegExp(r'BARCODE', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('CATEGORY')) {
          result['category'] = part.replaceFirst(RegExp(r'CATEGORY', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('BRAND')) {
          result['brand'] = part.replaceFirst(RegExp(r'BRAND', caseSensitive: false), '').trim();
        }
        else if (part.toUpperCase().startsWith('PRICE')) {
          String priceStr = part.replaceFirst(RegExp(r'PRICE', caseSensitive: false), '').trim();
          result['unitprice'] = double.tryParse(priceStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
        }
      }
      
      return _finalizeParseResult(result);
    } catch (e) {
      log('⚠️ Pipe parsing failed: $e');
      return result;
    }
  }

  // Helper: Parse Key:Value or Key=Value format
  static Map<String, dynamic> _parseKeyValueFormat(String data, Map<String, dynamic> result) {
    try {
      log('🔑 Parsing key-value format');
      
      // Split by comma or newline
      final pairs = data.split(RegExp(r'[,\n]'));
      
      for (String pair in pairs) {
        pair = pair.trim();
        if (pair.isEmpty) continue;
        
        // Split by : or =
        final parts = pair.split(RegExp(r'[:=]'));
        if (parts.length != 2) continue;
        
        String key = parts[0].trim().toUpperCase();
        String value = parts[1].trim();
        
        switch (key) {
          case 'NAME':
          case 'PRODUCTNAME':
            result['name'] = value;
            break;
          case 'SKU':
          case 'ITEMNO':
            result['sku'] = value;
            break;
          case 'BARCODE':
          case 'PRODUCTID':
            result['barcode'] = value;
            break;
          case 'CATEGORY':
            result['category'] = value;
            break;
          case 'BRAND':
            result['brand'] = value;
            break;
          case 'PRICE':
          case 'UNITPRICE':
            result['unitprice'] = double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
            break;
          case 'DESCRIPTION':
            result['description'] = value;
            break;
        }
      }
      
      return _finalizeParseResult(result);
    } catch (e) {
      log('⚠️ Key-value parsing failed: $e');
      return result;
    }
  }

  // Helper: Parse line-by-line format (EXISTING LOGIC - PRESERVED)
  static Map<String, dynamic> _parseLineByLineFormat(String data, Map<String, dynamic> result) {
    try {
      log('📄 Parsing line-by-line format');
      
      final lines = data.split('\n');
      
      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('-') || line == 'Product Details:') continue;
        
        try {
          // Parse Name
          if (line.startsWith('Name:')) {
            String tempName = line.replaceFirst('Name:', '').trim();
            if (tempName.isNotEmpty && tempName.length >= 3 && tempName.length <= 255) {
              result['name'] = tempName;
              log('  ✅ Name: ${result['name']}');
            }
          }
          // Parse Description
          else if (line.startsWith('Description:')) {
            String tempDesc = line.replaceFirst('Description:', '').trim();
            if (tempDesc.contains(' | Barcode Check Digit:')) {
              tempDesc = tempDesc.split(' | Barcode Check Digit:')[0];
            }
            if (tempDesc.isNotEmpty) {
              result['description'] = tempDesc;
              log('  ✅ Description: ${result['description']}');
            }
          }
          // Parse SKU
          else if (line.startsWith('SKU:') || line.startsWith('Item No:')) {
            String tempSku = line.replaceFirst(RegExp(r'(SKU:|Item No:)'), '').trim();
            if (tempSku.isNotEmpty && tempSku.length <= 100) {
              result['sku'] = tempSku;
              log('  ✅ SKU: ${result['sku']}');
            }
          }
          // Parse Barcode
          else if (line.startsWith('Barcode:')) {
            String tempBarcode = line.replaceFirst('Barcode:', '').trim();
            if (tempBarcode.isNotEmpty && tempBarcode.length >= 8 && tempBarcode.length <= 50) {
              result['barcode'] = tempBarcode;
              log('  ✅ Barcode: ${result['barcode']}');
            }
          }
          // Parse Category
          else if (line.startsWith('Category:')) {
            String tempCategory = line.replaceFirst('Category:', '').trim();
            if (tempCategory.isNotEmpty && tempCategory.length <= 100) {
              result['category'] = tempCategory;
              log('  ✅ Category: ${result['category']}');
            }
          }
          // Parse Brand
          else if (line.startsWith('Brand:')) {
            String tempBrand = line.replaceFirst('Brand:', '').trim();
            if (tempBrand.isNotEmpty && tempBrand.length <= 100) {
              result['brand'] = tempBrand;
              log('  ✅ Brand: ${result['brand']}');
            }
          }
          // Parse Price
          else if (line.startsWith('Unit Price:') || line.startsWith('Price:')) {
            log('  🔍 Found price line: "$line"');
            String priceStr = line.replaceFirst(RegExp(r'(Unit Price:|Price:)'), '').trim();
            log('  🔍 After removing label: "$priceStr"');
            priceStr = priceStr.replaceAll(RegExp(r'[^\d\.]'), '');
            log('  🔍 After removing non-numeric: "$priceStr"');
            double? parsedPrice = double.tryParse(priceStr);
            log('  🔍 Parsed price value: $parsedPrice');
            if (parsedPrice != null && parsedPrice >= 0 && parsedPrice <= 9999999) {
              result['unitprice'] = parsedPrice;
              log('  ✅ Unit Price SET TO: ${result['unitprice']}');
            } else {
              log('  ❌ Price parsing failed or out of range');
            }
          }
          // Parse Quantity
          else if (line.startsWith('Quantity:')) {
            String qtyStr = line.replaceFirst('Quantity:', '').trim();
            int? parsedQty = int.tryParse(qtyStr);
            if (parsedQty != null && parsedQty >= 1 && parsedQty <= 9999) {
              result['quantity'] = parsedQty;
              log('  ✅ Quantity: ${result['quantity']}');
            }
          }
        } catch (lineError) {
          log('  ⚠️ Error parsing line "$line": $lineError');
          continue;
        }
      }
      
      log('📊 Final parsed result before finalize: unitprice=${result['unitprice']}');
      return _finalizeParseResult(result);
    } catch (e) {
      log('⚠️ Line-by-line parsing failed: $e');
      return result;
    }
  }

  // Helper: Parse simple barcode (just a number/code)
  static Map<String, dynamic> _parseSimpleBarcodeFormat(String data, Map<String, dynamic> result) {
    try {
      log('🔢 Parsing simple barcode format');
      
      String cleanBarcode = data.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      
      result['barcode'] = cleanBarcode;
      
      // Generate fallback name from barcode
      if (cleanBarcode.length >= 6) {
        String suffix = cleanBarcode.substring(cleanBarcode.length - 6);
        result['name'] = 'Product-$suffix';
      } else {
        result['name'] = 'Product-$cleanBarcode';
      }
      
      log('⚠️ Simple barcode fallback triggered for: $cleanBarcode');
      
      return _finalizeParseResult(result);
    } catch (e) {
      log('⚠️ Simple barcode parsing failed: $e');
      return result;
    }
  }

  // Helper: Finalize and validate parsed result
  static Map<String, dynamic> _finalizeParseResult(Map<String, dynamic> result) {
    // Generate SKU if missing
    if (result['sku'].toString().isEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      result['sku'] = 'SKU_$timestamp';
      result['itemno'] = 'SKU_$timestamp';
      log('⚠️ Generated fallback SKU: ${result['sku']}');
    } else {
      result['itemno'] = result['sku'];
    }
    
    // Generate barcode if missing
    if (result['barcode'].toString().isEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      result['barcode'] = 'ITEM_$timestamp';
      log('⚠️ Generated fallback barcode: ${result['barcode']}');
    }
    
    // Sanitize barcode
    result['barcode'] = result['barcode'].toString().replaceAll(RegExp(r'[^\w\-]'), '');
    if (result['barcode'].toString().length > 50) {
      result['barcode'] = result['barcode'].toString().substring(0, 50);
    }
    
    // Validate and truncate strings
    if (result['name'].toString().length > 255) {
      result['name'] = result['name'].toString().substring(0, 255);
    }
    if (result['description'].toString().length > 500) {
      result['description'] = result['description'].toString().substring(0, 500);
    }
    if (result['brand'].toString().length > 100) {
      result['brand'] = result['brand'].toString().substring(0, 100);
    }
    
    // Set itemid
    result['itemid'] = result['barcode'];
    
    log('✅ Parse complete: Name="${result['name']}", SKU="${result['sku']}", Brand="${result['brand']}", Barcode="${result['barcode']}"');
    
    return result;
  }

  // Helper: Generate fallback data on complete failure
  static Map<String, dynamic> _generateFallbackResult(String scannedData) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    String cleanBarcode = scannedData.trim().replaceAll(RegExp(r'[^\w\-]'), '');
    
    if (cleanBarcode.isEmpty || cleanBarcode.length > 50) {
      cleanBarcode = 'PROD_$timestamp';
    }
    
    log('⚠️ Using complete fallback data');
    
    return {
      'barcode': cleanBarcode,
      'name': 'Product-${timestamp.substring(7)}',
      'sku': 'SKU_$timestamp',
      'description': 'Professional warehouse product',
      'itemid': timestamp,
      'itemno': 'SKU_$timestamp',
      'quantity': 1,
      'category': 'General',
      'brand': '',
      'unitprice': 0.0,
    };
  }

  /// Validate item
  static Future<Map<String, dynamic>> validateItem(String barcode) async {
    try {
      log('🔄 Validating item: $barcode');
      final cleanBarcode = barcode.trim();

      final existingItem = await _supabase
          .from('inventory')
          .select('*')
          .eq('barcode', cleanBarcode)
          .eq('is_active', true)
          .maybeSingle();

      if (existingItem != null) {
        return {
          'exists': true,
          'item': existingItem,
          'message': 'Product ${existingItem['name']} found',
          'voice_message': 'Product found'
        };
      }

      final newItemData = parseProductDetailsFromBarcode(barcode);
      return {
        'exists': false,
        'item': newItemData,
        'is_new': true,
        'message': 'New item data prepared for ${newItemData['barcode']}',
        'voice_message': 'New item created'
      };
    } catch (e) {
      log('❌ Item validation error: $e');
      return _handleDatabaseError(e, 'validate item');
    }
  }

  /// ✅ NEW: Check what items are currently in a location
  static Future<Map<String, dynamic>> checkLocationContents(String locationCode) async {
    try {
      log('🔍 Checking location contents: $locationCode');
      
      final items = await _supabase
          .from('storage_table')
          .select('barcode, item_no, description, qty, category')
          .eq('location', locationCode.toUpperCase())
          .limit(1);

      if (items.isEmpty) {
        return {
          'is_empty': true,
          'message': 'Location is empty',
        };
      }

      final firstItem = items[0];
      return {
        'is_empty': false,
        'barcode': firstItem['barcode'],
        'sku': firstItem['item_no'],
        'name': firstItem['description'],
        'quantity': firstItem['qty'],
        'category': firstItem['category'],
        'message': 'Location contains ${firstItem['description']}',
      };
    } catch (e) {
      log('❌ Error checking location contents: $e');
      return {
        'is_empty': true,
        'error': e.toString(),
      };
    }
  }

  /// ✅ NEW: Check if product exists in any other location
  static Future<Map<String, dynamic>> checkProductLocation(String barcode, String sku, String productName) async {
    try {
      log('🔍 Checking if product exists elsewhere: $barcode');
      
      final existingLocation = await _supabase
          .from('storage_table')
          .select('location, description, qty')
          .eq('barcode', barcode)
          .limit(1);

      if (existingLocation.isEmpty) {
        return {
          'exists_elsewhere': false,
          'message': 'Product not found in any location',
        };
      }

      final item = existingLocation[0];
      return {
        'exists_elsewhere': true,
        'location': item['location'],
        'name': item['description'],
        'quantity': item['qty'],
        'message': 'Product already exists in location ${item['location']}',
      };
    } catch (e) {
      log('❌ Error checking product location: $e');
      return {
        'exists_elsewhere': false,
        'error': e.toString(),
      };
    }
  }

  /// Store item in location with validation
  static Future<Map<String, dynamic>> storeItemInLocation({
    required String locationCode,
    required String barcode,
    required int quantity,
    required String scannedBy,
    String? description,
    String? category,
    double? unitPrice,
    required String itemName,
    required String sku,
    required dynamic finalSku,
    String? brand,
  }) async {
    try {
      log('🔄 Storing item in location...');

      // Validate location
      final locationResult = await validateLocation(locationCode);
      String? locationId;

      if (!locationResult['exists']) {
        final addLocationResult = await addLocation(locationCode);
        if (!addLocationResult['success']) {
          return {
            'success': false,
            'message': 'Location validation failed and could not create new location',
            'voice_message': 'Storage failed'
          };
        }
        locationId = addLocationResult['location']?['location_id'];
      } else {
        locationId = locationResult['location']?['location_id'];
      }

      // ✅ UPDATED: Parse barcode data using new Universal Parser
      final productDetails = parseProductDetailsFromBarcode(barcode);
      final cleanBarcode = productDetails['barcode'] as String;
      final baseSku = productDetails['sku'] as String;
      final productName = productDetails['name'] as String;

      // ✅ NEW: VALIDATION STEP 1 - Check if location has items
      final locationContents = await checkLocationContents(locationCode);
      
      if (!locationContents['is_empty']) {
        // Location has items - validate they match
        final existingBarcode = (locationContents['barcode'] as String?) ?? '';
        final existingSku = (locationContents['sku'] as String?) ?? '';
        final existingName = (locationContents['name'] as String?) ?? '';
        
        // ✅ DEBUG: Log ALL location contents
        log('🔍 VALIDATION CHECK - Location Contents:');
        log('  Full contents: $locationContents');
        log('  Existing Barcode: "$existingBarcode"');
        log('  Existing SKU: "$existingSku"');
        log('  Existing Name: "$existingName"');
        log('🔍 VALIDATION CHECK - Scanned Product:');
        log('  Scanned Barcode: "$cleanBarcode"');
        log('  Scanned SKU: "$baseSku"');
        log('  Scanned Name: "$productName"');
        
        // ✅ FIXED: Primary match by BARCODE (most reliable)
        // Secondary match by SKU (if both have SKU)
        final barcodeMatch = existingBarcode.trim() == cleanBarcode.trim();
        final skuMatch = existingSku.trim() == baseSku.trim();
        
        log('🔍 VALIDATION RESULTS:');
        log('  Barcode Match: $barcodeMatch (${existingBarcode.trim()} == ${cleanBarcode.trim()})');
        log('  SKU Match: $skuMatch (${existingSku.trim()} == ${baseSku.trim()})');
        
        // ✅ CRITICAL FIX: Match by barcode AND SKU only (name can vary)
        // Barcode is the unique identifier, SKU is secondary
        if (!barcodeMatch || !skuMatch) {
          log('❌ Product mismatch in location $locationCode');
          log('  Barcode mismatch: "$existingBarcode" != "$cleanBarcode"');
          log('  SKU mismatch: "$existingSku" != "$baseSku"');
          return {
            'success': false,
            'message': 'Wrong item! This location contains "$existingName" (SKU: $existingSku, Barcode: $existingBarcode). You can only add more of the same item to this location.',
            'voice_message': 'Wrong item. This location contains $existingName',
            'location_contents': locationContents,
          };
        }
        log('✅ Product matches existing items in location (Barcode & SKU match)');
      }

      // ✅ NEW: VALIDATION STEP 2 - Check if product exists in another location
      final productLocationCheck = await checkProductLocation(cleanBarcode, baseSku, productName);
      
      if (productLocationCheck['exists_elsewhere']) {
        final existingLocation = productLocationCheck['location'] as String;
        
        // If product exists in a DIFFERENT location, block it
        if (existingLocation.toUpperCase() != locationCode.toUpperCase()) {
          log('❌ Product already exists in location $existingLocation');
          return {
            'success': false,
            'message': 'This product is already stored in location $existingLocation. Please add to that location instead.',
            'voice_message': 'Product already in location $existingLocation',
            'existing_location': existingLocation,
          };
        }
      }

      // Check existing item by barcode
      final existingItem = await _supabase
          .from('inventory')
          .select('*')
          .eq('barcode', cleanBarcode)
          .eq('is_active', true)
          .maybeSingle();

      final warehouseId = await _getDefaultWarehouseId();
      bool inventorySynced = false;
      String? inventoryId;

      final locationCheckDigit = _generateLocationCheckDigit(locationCode);
      final barcodeCheckDigit = _generateBarcodeCheckDigit(cleanBarcode);

      // ✅ UPDATED: Use parsed data for storage
      final storageData = {
        'item_no': baseSku,
        'qty': quantity,
        'location': locationCode.toUpperCase(),
        'location_check_digit': locationCheckDigit,
        'description': description ?? productDetails['description'],
        'category': category ?? productDetails['category'],
        'barcode': cleanBarcode,
        'barcode_check_digit': barcodeCheckDigit,
        'unit_price': unitPrice ?? productDetails['unitprice'],
        'scanned_by': scannedBy,
        'date_added': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final storageResult = await _supabase
          .from('storage_table')
          .insert(storageData)
          .select()
          .single();

      if (existingItem != null) {
        // Update existing inventory
        final newQty = (existingItem['quantity'] ?? 0) + quantity;

        await _supabase.from('inventory').update({
          'quantity': newQty,
          'location': locationCode.toUpperCase(),
          'location_id': locationId,
          'barcode_digits': barcodeCheckDigit,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingItem['id']);

        inventoryId = existingItem['id'];
        inventorySynced = true;

        await _recordInventoryMovement(
          inventoryId: existingItem['id'],
          movementType: 'STORAGE_IN',
          quantityChanged: quantity,
          previousQuantity: existingItem['quantity'] ?? 0,
          newQuantity: newQty,
          createdBy: scannedBy,
          notes: 'Item stored in location $locationCode',
        );
      } else {
        // Create new inventory
        String finalSkuValue = baseSku;
        int attempts = 0;
        const maxAttempts = 10;

        while (attempts < maxAttempts) {
          try {
            final skuExists = await _supabase
                .from('inventory')
                .select('id')
                .eq('sku', finalSkuValue)
                .eq('warehouse_id', warehouseId as Object)
                .eq('is_active', true)
                .maybeSingle();

            if (skuExists == null) break;

            attempts++;
            finalSkuValue = '${baseSku}_$attempts';
          } catch (checkError) {
            log('⚠️ SKU existence check failed, using SKU: $checkError');
            break;
          }
        }

        // ✅ CRITICAL FIX: Use parsed brand from productDetails
        final inventoryData = {
          'name': productName,
          'sku': finalSkuValue,
          'barcode': cleanBarcode,
          'description': description ?? productDetails['description'],
          'category': category ?? productDetails['category'],
          'brand': brand ?? productDetails['brand'] ?? '', // ✅ NOW CORRECTLY USES PARSED BRAND
          'quantity': quantity,
          'min_stock': 10,
          'unit_price': unitPrice ?? productDetails['unitprice'],
          'location': locationCode.toUpperCase(),
          'location_id': locationId,
          'warehouse_id': warehouseId,
          'barcode_digits': barcodeCheckDigit,
          'is_active': true,
          'created_by': scannedBy,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        try {
          final inventoryResult = await _supabase
              .from('inventory')
              .insert(inventoryData)
              .select('id')
              .single();

          inventoryId = inventoryResult['id'];
          inventorySynced = true;

          await _recordInventoryMovement(
            inventoryId: inventoryId as String,
            movementType: 'INITIAL_STOCK',
            quantityChanged: quantity,
            previousQuantity: 0,
            newQuantity: quantity,
            createdBy: scannedBy,
            notes: 'New item created and stored in location $locationCode',
          );
        } catch (inventoryError) {
          log('⚠️ Inventory sync failed (non-critical): $inventoryError');
          inventorySynced = false;
        }
      }

      return {
        'success': true,
        'item': {
          'name': productName,
          'sku': existingItem?['sku'] ?? finalSku,
          'barcode': cleanBarcode,
          'brand': brand ?? productDetails['brand'], // ✅ Include brand in response
        },
        'location': locationResult['location'] ?? {'location_code': locationCode.toUpperCase()},
        'quantity': quantity,
        'synced_to_inventory': inventorySynced,
        'inventory_id': inventoryId,
        'storage_id': storageResult['id'],
        'check_digits': {
          'location': locationCheckDigit,
          'barcode': barcodeCheckDigit,
        },
        'message': '$productName stored in $locationCode successfully${inventorySynced ? ' and synced to inventory' : ''}',
        'voice_message': 'Item stored successfully'
      };
    } catch (e) {
      log('❌ Store item error: $e');
      return _handleDatabaseError(e, 'store item');
    }
  }

  // ================================
  // ERROR HANDLING
  // ================================

  static Map<String, dynamic> _handleDatabaseError(dynamic error, String operation) {
    String errorMessage = 'Unknown error occurred';
    String voiceMessage = 'Operation failed';

    try {
      if (error is PostgrestException) {
        switch (error.code) {
          case '23505':
            if (error.message.contains('sku')) {
              errorMessage = 'SKU already exists. Product may already be in inventory.';
              voiceMessage = 'Duplicate product detected';
            } else if (error.message.contains('barcode')) {
              errorMessage = 'Barcode already exists in system.';
              voiceMessage = 'Duplicate barcode detected';
            } else {
              errorMessage = 'Duplicate data detected: ${error.details ?? error.message}';
              voiceMessage = 'Duplicate data found';
            }
            break;
          case '23503':
            errorMessage = 'Invalid reference data. Please check location or warehouse settings.';
            voiceMessage = 'Invalid reference data';
            break;
          case '42P01':
            errorMessage = 'Database table missing. Please contact administrator.';
            voiceMessage = 'Database configuration error';
            break;
          default:
            errorMessage = 'Database error: ${error.message}';
            voiceMessage = 'Database error occurred';
        }
      } else if (error.toString().contains('network') || error.toString().contains('connection')) {
        errorMessage = 'Network connection failed. Please check your internet connection.';
        voiceMessage = 'Connection failed';
      } else {
        errorMessage = 'Failed to $operation: ${error.toString()}';
        voiceMessage = 'Operation failed';
      }
    } catch (e) {
      log('Error in error handler: $e');
      errorMessage = 'Critical error occurred';
      voiceMessage = 'System error';
    }

    log('❌ $operation error: $errorMessage');
    return {
      'success': false,
      'error': errorMessage,
      'message': errorMessage,
      'voice_message': voiceMessage,
    };
  }

  // ================================
  // SHIPMENT & LOADING METHODS
  // ================================
  // ✅ MOVED TO loading_service.dart
  // All loading-related methods have been extracted to LoadingService

  // ================================
  // INVENTORY MANAGEMENT
  // ================================

  /// Fetch inventory with filters
  static Future<List<Map<String, dynamic>>> fetchInventory({
    String? warehouseId,
    int limit = 1000,
    String? category,
    String? searchQuery,
  }) async {
    try {
      log('🔄 Fetching inventory data...');

      var query = _supabase.from('inventory').select('''
        *,
        locations!inventory_location_id_fkey(
          location_code,
          zone,
          aisle,
          shelf
        )
      ''').eq('is_active', true);

      if (warehouseId != null) {
        query = query.eq('warehouse_id', warehouseId);
      }

      if (category != null && category.isNotEmpty && category != 'All') {
        query = query.eq('category', category);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('name.ilike.%$searchQuery%,sku.ilike.%$searchQuery%,barcode.ilike.%$searchQuery%');
      }

      final response = await query.limit(limit).order('name');

      log('✅ Found ${response.length} inventory items');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Fetch inventory error: $e');
      throw Exception('Failed to fetch inventory: $e');
    }
  }

  /// Update inventory
  static Future<bool> updateInventory(String itemId, Map<String, dynamic> updates) async {
    try {
      log('🔄 Updating inventory item: $itemId');

      final currentItem = await _supabase
          .from('inventory')
          .select('quantity')
          .eq('id', itemId)
          .single();

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('inventory').update(updates).eq('id', itemId);

      if (updates.containsKey('quantity')) {
        final oldQty = currentItem['quantity'] ?? 0;
        final newQty = updates['quantity'];

        if (oldQty != newQty) {
          await _recordInventoryMovement(
            inventoryId: itemId,
            movementType: 'MANUAL_ADJUSTMENT',
            quantityChanged: newQty - oldQty,
            previousQuantity: oldQty,
            newQuantity: newQty,
            createdBy: 'System',
            notes: 'Manual inventory update',
          );
        }
      }

      log('✅ Inventory item updated successfully');
      return true;
    } catch (e) {
      log('❌ Update inventory error: $e');
      return false;
    }
  }

  /// Insert inventory
  static Future<bool> insertInventory(Map<String, dynamic> itemData, {String? warehouseId}) async {
    try {
      log('🔄 Inserting new inventory item...');

      final warehouseId = await _getDefaultWarehouseId();

      itemData['warehouse_id'] = warehouseId;
      itemData['is_active'] = true;
      itemData['created_at'] = DateTime.now().toIso8601String();
      itemData['updated_at'] = DateTime.now().toIso8601String();

      if (itemData['barcode'] != null && itemData['barcode_digits'] == null) {
        itemData['barcode_digits'] = _generateBarcodeCheckDigit(itemData['barcode']);
      }

      final result = await _supabase
          .from('inventory')
          .insert(itemData)
          .select('id')
          .single();

      if (itemData['quantity'] != null && itemData['quantity'] > 0 && result['id'] != null) {
        await _recordInventoryMovement(
          inventoryId: result['id'] as String,
          movementType: 'INITIAL_STOCK',
          quantityChanged: itemData['quantity'],
          previousQuantity: 0,
          newQuantity: itemData['quantity'],
          createdBy: itemData['created_by'] ?? 'System',
          notes: 'Initial inventory creation',
        );
      }

      log('✅ New inventory item inserted successfully');
      return true;
    } catch (e) {
      log('❌ Insert inventory error: $e');
      return false;
    }
  }

  /// Delete inventory (soft delete)
  static Future<bool> deleteInventory(String itemId) async {
    try {
      log('🔄 Soft deleting inventory item: $itemId');

      final currentItem = await _supabase
          .from('inventory')
          .select('quantity')
          .eq('id', itemId)
          .single();

      await _supabase.from('inventory').update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', itemId);

      if (currentItem['quantity'] > 0) {
        await _recordInventoryMovement(
          inventoryId: itemId,
          movementType: 'DELETION',
          quantityChanged: -currentItem['quantity'],
          previousQuantity: currentItem['quantity'],
          newQuantity: 0,
          createdBy: 'System',
          notes: 'Item soft deleted',
        );
      }

      log('✅ Inventory item deleted successfully');
      return true;
    } catch (e) {
      log('❌ Delete inventory error: $e');
      return false;
    }
  }

  /// Search inventory
  static Future<List<Map<String, dynamic>>> searchInventory(String searchTerm) async {
    try {
      log('🔄 Searching inventory: $searchTerm');

      final response = await _supabase
          .from('inventory')
          .select('*')
          .or('name.ilike.%$searchTerm%,sku.ilike.%$searchTerm%,barcode.ilike.%$searchTerm%')
          .eq('is_active', true)
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Search inventory error: $e');
      return [];
    }
  }

  // ================================
  // PICKLIST MANAGEMENT
  // ================================

  // NOTE: Manual "Add to Picklist" functions REMOVED
  // Picklists are now auto-generated from customer orders via picklist_service.dart

  /// Fetch picklists
  static Future<List<Map<String, dynamic>>> fetchPicklist({
    String? assignedTo,
    String? status,
    String? warehouseId,
    int limit = 100,
  }) async {
    try {
      log('🔄 Fetching picklist data...');

      var query = _supabase.from('picklist').select('''
        *,
        inventory!picklist_inventory_id_fkey(
          name,
          sku,
          barcode,
          quantity,
          unit_price
        )
      ''');

      if (assignedTo != null) {
        query = query.eq('picker_name', assignedTo);
      }

      if (status != null) {
        query = query.eq('status', status);
      }

      if (warehouseId != null) {
        query = query.eq('warehouse_id', warehouseId);
      }

      final response = await query.limit(limit).order('created_at', ascending: false);

      log('✅ Found ${response.length} picklist items');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Fetch picklist error: $e');
      return [];
    }
  }

  /// Update pick status
  static Future<bool> updatePickStatus(String picklistId, String newStatus) async {
    try {
      log('🔄 Updating pick status...');

      final updateData = {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newStatus == 'completed') {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      } else if (newStatus == 'in_progress') {
        updateData['started_at'] = DateTime.now().toIso8601String();
      }

      await _supabase.from('picklist').update(updateData).eq('id', picklistId);

      log('✅ Pick status updated successfully');
      return true;
    } catch (e) {
      log('❌ Update pick status error: $e');
      return false;
    }
  }

  /// Delete picklist item (hard delete)
  static Future<bool> deletePicklistItem(String picklistId) async {
    try {
      log('🔄 Permanently deleting picklist item: $picklistId');

      await _supabase.from('picklist').delete().eq('id', picklistId);

      log('✅ Picklist item permanently deleted successfully');
      return true;
    } catch (e) {
      log('❌ Delete picklist item error: $e');
      return false;
    }
  }

  /// Get completed picklist operations
  static Future<List<Map<String, dynamic>>> getCompletedPicklistOperations() async {
    try {
      log('🔄 Fetching completed picklist operations...');

      final response = await _supabase.from('picklist').select('''
        *,
        inventory!picklist_inventory_id_fkey(
          name,
          sku,
          barcode,
          quantity,
          unit_price
        )
      ''').eq('status', 'completed').not('completed_at', 'is', null).order('completed_at', ascending: false).limit(500);

      log('✅ Found ${response.length} completed operations');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Get completed operations error: $e');
      return [];
    }
  }

  /// Get picker performance stats
  static Future<Map<String, dynamic>> getPickerPerformanceStats(String pickerName) async {
    try {
      log('🔄 Fetching picker performance stats for: $pickerName');

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      final weekStartStr = weekStart.toIso8601String().substring(0, 10);

      final todayStats = await _supabase
          .from('picklist')
          .select('quantity_requested, quantity_picked, status')
          .eq('picker_name', pickerName)
          .eq('status', 'completed')
          .gte('completed_at', '${today}T00:00:00');

      final weekStats = await _supabase
          .from('picklist')
          .select('quantity_requested, quantity_picked, status')
          .eq('picker_name', pickerName)
          .eq('status', 'completed')
          .gte('completed_at', '${weekStartStr}T00:00:00');

      int accurateToday = 0;
      int totalToday = todayStats.length;

      for (var stat in todayStats) {
        if (stat['quantity_requested'] == stat['quantity_picked']) {
          accurateToday++;
        }
      }

      int accurateWeek = 0;
      int totalWeek = weekStats.length;

      for (var stat in weekStats) {
        if (stat['quantity_requested'] == stat['quantity_picked']) {
          accurateWeek++;
        }
      }

      return {
        'today_picks': totalToday,
        'today_accuracy': totalToday > 0 ? (accurateToday / totalToday * 100) : 100.0,
        'week_picks': totalWeek,
        'week_accuracy': totalWeek > 0 ? (accurateWeek / totalWeek * 100) : 100.0,
      };
    } catch (e) {
      log('❌ Get picker performance stats error: $e');
      return {
        'today_picks': 0,
        'today_accuracy': 100.0,
        'week_picks': 0,
        'week_accuracy': 100.0,
      };
    }
  }

  // ================================
  // VOICE PICKING SUPPORT
  // ================================

  /// Get voice-ready picklist items
  static Future<List<Map<String, dynamic>>> getVoiceReadyPicklist({
    String? pickerName,
    String? waveNumber,
  }) async {
    try {
      log('🔄 Fetching voice-ready picklist items...');

      var query = _supabase
          .from('picklist')
          .select('*')
          .eq('status', 'pending')
          .eq('voice_ready', true);

      if (pickerName != null) {
        query = query.eq('picker_name', pickerName);
      }

      if (waveNumber != null) {
        query = query.eq('wave_number', waveNumber);
      }

      final response = await query
          .order('priority', ascending: false)
          .order('created_at', ascending: true);

      log('✅ Found ${response.length} voice-ready items');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      log('❌ Get voice-ready picklist error: $e');
      return [];
    }
  }

  /// Start voice picking session
  static Future<Map<String, dynamic>> startVoicePickingSession({
    required String pickerName,
    String? waveNumber,
  }) async {
    try {
      log('🔄 Starting voice picking session for $pickerName...');

      final warehouseId = await _getDefaultWarehouseId();
      final sessionId = 'VP_${DateTime.now().millisecondsSinceEpoch}';

      var query = _supabase
          .from('picklist')
          .select('*')
          .eq('status', 'pending')
          .eq('voice_ready', true)
          .eq('picker_name', pickerName);

      if (waveNumber != null) {
        query = query.eq('wave_number', waveNumber);
      }

      final voiceItems = await query
          .order('priority', ascending: false)
          .order('created_at', ascending: true);

      if (voiceItems.isEmpty) {
        return {
          'success': false,
          'message': 'No items available for voice picking',
          'voice_message': 'No picks available'
        };
      }

      await _supabase.from('voice_picking_sessions').insert({
        'session_id': sessionId,
        'picker_name': pickerName,
        'warehouse_id': warehouseId,
        'start_time': DateTime.now().toIso8601String(),
        'status': 'active',
        'total_tasks': voiceItems.length,
        'session_metrics': {'started_items': voiceItems.length},
        'created_at': DateTime.now().toIso8601String(),
      });

      for (var item in voiceItems) {
        await _supabase.from('picklist').update({
          'status': 'in_progress',
          'started_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', item['id']);
      }

      return {
        'success': true,
        'items': voiceItems,
        'total_items': voiceItems.length,
        'session_id': sessionId,
        'message': 'Voice picking session started with ${voiceItems.length} items',
        'voice_message': 'Session started. ${voiceItems.length} items to pick'
      };
    } catch (e) {
      log('❌ Start voice picking session error: $e');
      return _handleDatabaseError(e, 'start voice picking session');
    }
  }

  /// Update pick with voice confirmation
  static Future<Map<String, dynamic>> updatePickWithVoice({
    required String picklistId,
    required int quantityPicked,
    required String pickerName,
    String? voiceConfirmation,
  }) async {
    try {
      log('🔄 Updating pick with voice confirmation...');

      final pickItem = await _supabase
          .from('picklist')
          .select('*')
          .eq('id', picklistId)
          .single();

      final quantityRequested = pickItem['quantity_requested'] ?? 0;
      final newStatus = quantityPicked >= quantityRequested ? 'completed' : 'partial';

      await _supabase.from('picklist').update({
        'quantity_picked': quantityPicked,
        'status': newStatus,
        'voice_confirmation': voiceConfirmation,
        'completed_at': newStatus == 'completed' ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', picklistId);

      if (newStatus == 'completed' && pickItem['inventory_id'] != null) {
        final inventoryItem = await _supabase
            .from('inventory')
            .select('quantity')
            .eq('id', pickItem['inventory_id'])
            .single();

        final currentQty = inventoryItem['quantity'] ?? 0;
        final newQty = currentQty - quantityPicked;

        await _supabase.from('inventory').update({
          'quantity': newQty,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', pickItem['inventory_id']);

        await _recordInventoryMovement(
          inventoryId: pickItem['inventory_id'],
          movementType: 'PICK_OUT',
          quantityChanged: -quantityPicked,
          previousQuantity: currentQty,
          newQuantity: newQty,
          createdBy: pickerName,
          notes: 'Voice picking completed for wave ${pickItem['wave_number']}',
        );
      }

      return {
        'success': true,
        'status': newStatus,
        'message': 'Pick updated successfully',
        'voice_message': newStatus == 'completed' ? 'Pick completed' : 'Partial pick recorded'
      };
    } catch (e) {
      log('❌ Update pick with voice error: $e');
      return _handleDatabaseError(e, 'update pick with voice');
    }
  }

  // ================================
  // STORAGE & REPORTING
  // ================================

  /// Get stored items
  static Future<List<Map<String, dynamic>>> getStoredItems() async {
    try {
      log('🔄 Fetching stored items...');

      final result = await _supabase
          .from('storage_table')
          .select('*')
          .order('date_added', ascending: false);

      log('✅ Found ${result.length} stored items');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      log('❌ Get stored items error: $e');
      return [];
    }
  }

  /// Update storage item quantity
  static Future<bool> updateStorageItemQuantity(String itemId, int newQuantity) async {
    try {
      log('🔄 Updating storage item quantity: $itemId');

      await _supabase.from('storage_table').update({
        'qty': newQuantity,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', itemId);

      log('✅ Storage item quantity updated successfully');
      return true;
    } catch (e) {
      log('❌ Update storage item quantity error: $e');
      return false;
    }
  }

  /// Remove item from storage
  static Future<bool> removeItemFromStorage(String itemId, String removedBy) async {
    try {
      log('🔄 Removing item from storage: $itemId');

      await _supabase.from('storage_table').delete().eq('id', itemId);

      log('✅ Item removed from storage successfully');
      return true;
    } catch (e) {
      log('❌ Remove item from storage error: $e');
      return false;
    }
  }

  /// Get dashboard statistics
  static Future<Map<String, dynamic>> getDashboardStats({String? warehouseId}) async {
    try {
      final storageItems = await _supabase.from('storage_table').select('*');
      final inventoryItems = await fetchInventory(warehouseId: warehouseId);
      final locations = await _supabase.from('locations').select('*').eq('is_active', true);

      final activeWavesData = await _supabase
          .from('picklist')
          .select('wave_number')
          .neq('status', 'completed')
          .neq('status', 'cancelled');

      final uniqueWaves = Set.from(
          activeWavesData.map((w) => w['wave_number']?.toString() ?? '').where((w) => w.isNotEmpty));

      final pendingOrdersData = await _supabase
          .from('picklist')
          .select('id')
          .eq('status', 'pending');

      final totalPicksToday = await _supabase
          .from('picklist')
          .select('id, status')
          .gte('created_at', DateTime.now().toIso8601String().substring(0, 10) + 'T00:00:00');

      final completedPicksToday = totalPicksToday.where((p) => p['status'] == 'completed').length;
      final totalPicksTodayCount = totalPicksToday.length;

      double realEfficiency = totalPicksTodayCount > 0 ? (completedPicksToday / totalPicksTodayCount * 100) : 100.0;

      // ✅ Loading sessions moved to LoadingService
      final activeSessions = <Map<String, dynamic>>[];

      int lowStockCount = 0;
      int outOfStockCount = 0;
      double totalValue = 0.0;

      for (var item in inventoryItems) {
        final quantity = item['quantity'] ?? 0;
        final minStock = item['min_stock'] ?? 10;
        final unitPrice = (item['unit_price'] ?? 0.0).toDouble();

        if (quantity == 0) {
          outOfStockCount++;
        } else if (quantity <= minStock) {
          lowStockCount++;
        }

        totalValue += quantity * unitPrice;
      }

      return {
        'success': true,
        'data': {
          'totalProducts': inventoryItems.length,
          'storageItems': storageItems.length,
          'activeWaves': uniqueWaves.length,
          'pendingOrders': pendingOrdersData.length,
          'systemEfficiency': realEfficiency,
          'lowStockAlerts': lowStockCount,
          'outOfStockItems': outOfStockCount,
          'inventoryValue': totalValue,
          'warehouseName': 'Main Warehouse',
          'totalLocations': locations.length,
          'activeLoadingSessions': activeSessions.length,
          'completedPicksToday': completedPicksToday,
          'totalPicksToday': totalPicksTodayCount,
        },
      };
    } catch (e) {
      log('❌ Dashboard stats error: $e');
      return {
        'success': false,
        'error': 'Could not fetch dashboard data: ${e.toString()}',
        'data': {
          'totalProducts': 0,
          'storageItems': 0,
          'activeWaves': 0,
          'pendingOrders': 0,
          'systemEfficiency': 85.0,
          'lowStockAlerts': 0,
          'outOfStockItems': 0,
          'inventoryValue': 0.0,
          'warehouseName': 'Main Warehouse',
          'totalLocations': 0,
          'activeLoadingSessions': 0,
          'completedPicksToday': 0,
          'totalPicksToday': 0,
        },
      };
    }
  }

  /// Generate comprehensive inventory report
  static Future<Map<String, dynamic>> generateInventoryReport() async {
    try {
      log('🔄 Generating comprehensive inventory report...');

      final inventory = await fetchInventory();

      int totalItems = inventory.length;
      int lowStockItems = 0;
      int outOfStockItems = 0;
      double totalValue = 0.0;
      Map<String, int> categoryBreakdown = {};

      for (var item in inventory) {
        final quantity = item['quantity'] ?? 0;
        final minStock = item['min_stock'] ?? 10;
        final unitPrice = (item['unit_price'] ?? 0.0).toDouble();
        final category = item['category'] ?? 'General';

        if (quantity == 0) {
          outOfStockItems++;
        } else if (quantity <= minStock) {
          lowStockItems++;
        }

        totalValue += quantity * unitPrice;
        categoryBreakdown[category] = (categoryBreakdown[category] ?? 0) + 1;
      }

      return {
        'total_items': totalItems,
        'low_stock_items': lowStockItems,
        'out_of_stock_items': outOfStockItems,
        'total_inventory_value': totalValue,
        'category_breakdown': categoryBreakdown,
        'inventory_data': inventory,
        'generated_at': DateTime.now().toIso8601String(),
        'summary': 'Comprehensive inventory report with $totalItems items, total value: \$${totalValue.toStringAsFixed(2)}',
      };
    } catch (e) {
      log('❌ Generate inventory report error: $e');
      return {'error': e.toString()};
    }
  }

  // ================================
  // LOADING REPORTS MANAGEMENT
  // ================================
  // ✅ MOVED TO loading_service.dart
  // All loading report methods have been extracted to LoadingService

  // ================================
  // INVENTORY MOVEMENT TRACKING
  // ================================

  static Future<void> _recordInventoryMovement({
    required String inventoryId,
    required String movementType,
    required int quantityChanged,
    required int previousQuantity,
    required int newQuantity,
    required String createdBy,
    String? notes,
  }) async {
    try {
      await _supabase.from('inventory_movements').insert({
        'inventory_id': inventoryId,
        'movement_type': movementType,
        'quantity_changed': quantityChanged,
        'previous_quantity': previousQuantity,
        'new_quantity': newQuantity,
        'created_by': createdBy,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      log('⚠️ Failed to record inventory movement: $e');
    }
  }

  // ================================
  // UTILITY METHODS
  // ================================
  // ✅ _getAvailableDock moved to loading_service.dart

  // ================================
  // REPORT METHODS (ADD THESE)
  // ================================

  /// Get inventory reports
  static Future<Map<String, dynamic>> getInventoryReports() async {
    try {
      log('🔄 Fetching inventory reports...');

      final response = await _supabase
          .from('inventory')
          .select('*')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      log('✅ Found ${response.length} inventory items for report');

      return {
        'success': true,
        'data': List<Map<String, dynamic>>.from(response),
      };
    } catch (e) {
      log('❌ Get inventory reports error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
      };
    }
  }

  /// Get storage reports
  static Future<Map<String, dynamic>> getStorageReports() async {
    try {
      log('🔄 Fetching storage reports...');

      final response = await _supabase
          .from('storage_table')
          .select('*')
          .order('date_added', ascending: false)
          .limit(500);

      log('✅ Found ${response.length} storage entries for report');

      return {
        'success': true,
        'data': List<Map<String, dynamic>>.from(response),
      };
    } catch (e) {
      log('❌ Get storage reports error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
      };
    }
  }

  /// Get picklist reports
  static Future<Map<String, dynamic>> getPicklistReports() async {
    try {
      log('🔄 Fetching picklist reports...');

      final response = await _supabase
          .from('picklist')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);

      log('✅ Found ${response.length} picklist items for report');

      return {
        'success': true,
        'data': List<Map<String, dynamic>>.from(response),
      };
    } catch (e) {
      log('❌ Get picklist reports error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
      };
    }
  }

  /// Get inventory movement reports
  static Future<Map<String, dynamic>> getInventoryMovementReports() async {
    try {
      log('🔄 Fetching inventory movement reports...');

      final response = await _supabase
          .from('inventory_movements')
          .select('''
        *,
        inventory!inventory_movements_inventory_id_fkey (
          name,
          sku,
          barcode
        )
      ''')
          .order('created_at', ascending: false)
          .limit(500);

      // Flatten the data
      final movements = List<Map<String, dynamic>>.from(response).map((movement) {
        final inventory = movement['inventory'];
        return {
          ...movement,
          'item_name': inventory?['name'] ?? 'Unknown',
          'sku': inventory?['sku'] ?? '',
          'barcode': inventory?['barcode'] ?? '',
        };
      }).toList();

      log('✅ Found ${movements.length} movement records for report');

      return {
        'success': true,
        'data': movements,
      };
    } catch (e) {
      log('❌ Get inventory movement reports error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'data': [],
      };
    }
  }

  static Future<void> updateLoadingReport(dynamic report, Map<String, dynamic> updates) async {}
  
  static int? min(int i, int length) {}

  static Future getLoadingReports() async {}

  static Future deleteLoadingReport(String reportId) async {}

  static Future addInventoryToPicklist({required inventoryId, required String waveNumber, required String pickerName, required int quantityRequested, required String location, required String priority, String? locationCheckDigit, String? barcodeCheckDigit, required barcodeNumber}) async {}
}
