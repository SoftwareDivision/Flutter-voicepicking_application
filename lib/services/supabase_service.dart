// ignore_for_file: unnecessary_null_comparison, duplicate_ignore

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // ✅ CONNECTION TEST - Most Important Function
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      debugPrint('🔄 Testing Supabase connection...');
      
      // Test 1: Check if client is initialized
      // ignore: unnecessary_null_comparison
      if (_client == null) {
        return {
          'connected': false,
          'error': 'Supabase client not initialized',
          'details': 'Client is null'
        };
      }

      // Test 2: Simple query to test database connection
      final response = await _client
          .from('warehouses')
          .select('warehouse_id, name')
          .limit(1);
      
      debugPrint('✅ Supabase connection successful!');
      debugPrint('📊 Response: $response');
      
      return {
        'connected': true,
        'message': 'Successfully connected to Supabase',
        'data': response,
        'timestamp': DateTime.now().toIso8601String()
      };
    } catch (e) {
      debugPrint('❌ Supabase connection failed: $e');
      return {
        'connected': false,
        'error': e.toString(),
        'details': 'Connection test failed'
      };
    }
  }

  // ✅ DETAILED CONNECTION STATUS
  static Future<Map<String, dynamic>> getConnectionStatus() async {
    try {
      final connectionTest = await testConnection();
      
      return {
        'isConnected': connectionTest['connected'],
        'clientInitialized': _client != null,
        'hasActiveSession': _client.auth.currentSession != null,
        'userId': _client.auth.currentUser?.id,
        'connectionDetails': connectionTest,
      };
    } catch (e) {
      return {
        'isConnected': false,
        'error': e.toString(),
      };
    }
  }

  // ✅ QUICK CONNECTION CHECK
  static bool get isConnected {
    try {
      return _client != null;
    } catch (e) {
      return false;
    }
  }

  // ✅ GET CLIENT INSTANCE
  static SupabaseClient get client => _client;
}
