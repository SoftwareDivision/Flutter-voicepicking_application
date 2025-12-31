// lib/controllers/voice_picking_controller.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';
import '../services/voice_service.dart';
import '../services/warehouse_service.dart'; // ✅ ADD THIS IMPORT
import '../models/voice_command_parser.dart';

// Enhanced picking states for workflow
enum PickingState {
  idle,
  ready,
  readyWait,
  locationCheck,
  itemCheck,
  barcodeScanning,
  completed
}

// Enhanced voice recognition status
enum VoiceStatus {
  idle,
  initializing,
  listening,
  processing,
  completed,
  error,
  timeout,
  retrying
}

class VoicePickingController extends ChangeNotifier {
  // ================================
  // STATE VARIABLES
  // ================================
  final String userName;

  // Enhanced State Management
  PickingState _currentState = PickingState.idle;
  VoiceStatus _voiceStatus = VoiceStatus.idle;
  String _lastInstruction = "READY FOR INSTRUCTION";
  String _userInput = "";
  String _originalVoiceInput = "";
  bool _isProcessing = false;

  // ✅ NEW: Hands-free mode properties
  bool _isHandsFreeModeActive = false;
  bool _isSessionActive = false;

  // Voice Recognition
  late SpeechToText _speechToText;
  late FlutterTts _flutterTts;
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isContinuousMode = true;
  double _soundLevel = 0.0;
  Timer? _listeningTimer;
  Timer? _restartTimer;
  Timer? _processingTimer;
  int _retryCount = 0;
  int _consecutiveErrors = 0;
  static const int _maxRetries = 5;
  static const int _maxConsecutiveErrors = 3;
  static const int _listeningTimeout = 15;

  // Voice Settings State
  bool _voiceEnabled = true;

  // Picking Data - REAL SUPABASE DATA
  List<Map<String, dynamic>> _pickingItems = [];
  int _currentItemIndex = 0;
  int _completedItems = 0;
  Duration _sessionTime = Duration.zero;
  Timer? _sessionTimer;
  bool _isDataLoaded = false;
  bool _isSystemReady = false;
  String? _currentSessionId;
  Map<String, dynamic>? _currentItemDetails;

  // EDA51 Scanner Integration
  bool _isWaitingForScan = false;
  String _lastScannedBarcode = "";

  // Real-time Data Refresh
  Timer? _dataRefreshTimer;

  // ================================
  // CONSTRUCTOR
  // ================================
  VoicePickingController({required this.userName}) {
    _initializeComponents();
  }

  // ================================
  // GETTERS
  // ================================
  PickingState get currentState => _currentState;
  VoiceStatus get voiceStatus => _voiceStatus;
  String get lastInstruction => _lastInstruction;
  String get userInput => _userInput;
  String get originalVoiceInput => _originalVoiceInput;
  bool get isProcessing => _isProcessing;
  bool get speechEnabled => _speechEnabled;
  bool get isListening => _isListening;
  bool get isContinuousMode => _isContinuousMode;
  double get soundLevel => _soundLevel;
  int get retryCount => _retryCount;
  List<Map<String, dynamic>> get pickingItems => _pickingItems;
  int get currentItemIndex => _currentItemIndex;
  int get completedItems => _completedItems;
  Duration get sessionTime => _sessionTime;
  bool get isDataLoaded => _isDataLoaded;
  bool get isSystemReady => _isSystemReady;
  Map<String, dynamic>? get currentItemDetails => _currentItemDetails;
  bool get isWaitingForScan => _isWaitingForScan;
  String get lastScannedBarcode => _lastScannedBarcode;

  // ✅ NEW: Hands-free mode getters
  bool get isHandsFreeModeActive => _isHandsFreeModeActive;
  bool get isSessionActive => _isSessionActive;

  // ================================
  // VOICE SETTINGS INTEGRATION
  // ================================
  /// Load voice settings from SharedPreferences
  Future<void> _loadVoiceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speed = prefs.getDouble('voice_speed') ?? 0.75;
      final volume = prefs.getDouble('voice_volume') ?? 0.8;
      final language = prefs.getString('selected_language') ?? 'English (US)';
      final voiceEnabled = prefs.getBool('voice_enabled') ?? true;

      debugPrint('📱 Loading voice settings - Speed: $speed, Volume: $volume, Language: $language');

      await _flutterTts.setSpeechRate(speed);
      await _flutterTts.setVolume(volume);
      await _flutterTts.setLanguage(_mapLanguageToCode(language));
      _voiceEnabled = voiceEnabled;

      debugPrint('✅ Voice settings applied successfully');
    } catch (e) {
      debugPrint('❌ Load voice settings error: $e');
      await _flutterTts.setSpeechRate(0.75);
      await _flutterTts.setVolume(0.8);
      await _flutterTts.setLanguage("en-US");
    }
  }

  /// Map language display names to TTS language codes
  String _mapLanguageToCode(String language) {
    switch (language) {
      case 'English (US)':
        return 'en-US';
      case 'English (UK)':
        return 'en-GB';
      case 'Spanish':
        return 'es-ES';
      case 'French':
        return 'fr-FR';
      case 'German':
        return 'de-DE';
      default:
        return 'en-US';
    }
  }

  /// Public method to reload voice settings (called from settings screen)
  Future<void> updateVoiceSettings() async {
    try {
      debugPrint('🔄 Updating voice settings in real-time...');
      await _loadVoiceSettings();
      notifyListeners();
      debugPrint('✅ Voice settings updated successfully');
    } catch (e) {
      debugPrint('❌ Update voice settings error: $e');
    }
  }

  /// Test voice with current settings
  Future<void> testVoiceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speed = prefs.getDouble('voice_speed') ?? 0.75;
      final volume = prefs.getDouble('voice_volume') ?? 0.8;
      await _speakMessage("Voice test at ${(speed * 100).toInt()}% speed and ${(volume * 100).toInt()}% volume.");
      debugPrint('🎤 Voice test completed');
    } catch (e) {
      debugPrint('❌ Voice test error: $e');
    }
  }

  // ================================
  // INITIALIZATION WITH REAL DATA
  // ================================
  Future<void> _initializeComponents() async {
    try {
      debugPrint('🚀 Starting voice picking initialization with REAL Supabase data...');
      _initializeSession();
      await _loadPickingDataFromSupabase();
      await _initializeVoiceServices();
      _startDataRefreshTimer();
      _isSystemReady = true;
      notifyListeners();
      debugPrint('✅ Voice picking system ready with real data!');
    } catch (e) {
      debugPrint('❌ Critical initialization error: $e');
      _voiceStatus = VoiceStatus.error;
      _lastInstruction = 'SYSTEM ERROR - RESTART REQUIRED';
      notifyListeners();
    }
  }

  void _initializeSession() {
    try {
      _sessionTime = Duration.zero;
      _completedItems = 0;
      _currentItemIndex = 0;
      _consecutiveErrors = 0;
      _retryCount = 0;

      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _sessionTime = Duration(seconds: _sessionTime.inSeconds + 1);
        notifyListeners();
      });

      debugPrint('✅ Session initialized successfully');
    } catch (e) {
      debugPrint('❌ Session initialization error: $e');
    }
  }

  // ✅ FIXED: Enhanced data loading with warehouse fallback
  Future<void> _loadPickingDataFromSupabase() async {
    try {
      _isDataLoaded = false;
      notifyListeners();

      debugPrint('🔄 Loading REAL picking data from Supabase for user: $userName');

      // Test connection first
      final connectionTest = await VoiceService.testConnection();
      if (connectionTest['success'] != true) {
        throw Exception(connectionTest['error']);
      }
      debugPrint('✅ Supabase connection verified');

      // Get current warehouse
      final warehouseId = WarehouseService.currentWarehouseId;
      debugPrint('📍 Current warehouse for voice picking: ${warehouseId ?? "All warehouses"}');

      // ✅ FIXED: Try with warehouse filter first, then fallback to all warehouses
      var assignedTasks = await VoiceService.getAssignedPicklist(
        pickerId: userName,
        warehouseId: warehouseId,  // Try current warehouse first
      );

      debugPrint('🎯 Raw response from database: ${assignedTasks.length} items');

      // ✅ ADDED: If no items in current warehouse, try all warehouses
      if (assignedTasks.isEmpty && warehouseId != null) {
        debugPrint('! No items in warehouse $warehouseId - checking all warehouses...');
        
        assignedTasks = await VoiceService.getAssignedPicklist(
          pickerId: userName,
          // No warehouse filter - get all
        );
        
        if (assignedTasks.isNotEmpty) {
          debugPrint('✅ Found ${assignedTasks.length} items in other warehouses');
        }
      }

      // ✅ Check if still empty
      if (assignedTasks.isEmpty) {
        debugPrint('! No assigned tasks found for user: $userName');
        _isDataLoaded = false;
        _pickingItems = [];
        _currentItemDetails = null;
        _lastInstruction = "NO TASKS ASSIGNED";
        notifyListeners();
        return;
      }

      // Validate tasks
      final validTasks = <Map<String, dynamic>>[];
      for (var task in assignedTasks) {
        if (_validateTaskData(task)) {
          validTasks.add(task);
        } else {
          debugPrint('⚠️ Invalid task data skipped: ${task['id']}');
        }
      }

      if (validTasks.isEmpty) {
        throw Exception('All assigned tasks have invalid data. Please check Supabase data integrity.');
      }

      _pickingItems = validTasks;
      _currentItemDetails = _pickingItems.isNotEmpty ? _pickingItems[0] : null;
      _isDataLoaded = true;
      _lastInstruction = "${_pickingItems.length} ITEMS READY";
      
      notifyListeners();
      
      debugPrint('✅ Loaded ${_pickingItems.length} valid picking items from Supabase');
    } catch (e, stackTrace) {
      debugPrint('❌ Supabase data loading error: $e');
      debugPrint('Stack trace: $stackTrace');
      _isDataLoaded = false;
      _pickingItems = [];
      _currentItemDetails = null;
      _lastInstruction = "DATA LOADING FAILED";
      notifyListeners();
    }
  }

  bool _validateTaskData(Map<String, dynamic> task) {
    try {
      final requiredFields = ['id', 'inventory_id', 'quantity_requested', 'item_name', 'barcode', 'location'];
      
      for (String field in requiredFields) {
        if (task[field] == null) {
          debugPrint('❌ Missing required field: $field in task ${task['id']}');
          return false;
        }
      }

      if (task['quantity_requested'] is! int || task['quantity_requested'] <= 0) {
        debugPrint('❌ Invalid quantity_requested in task ${task['id']}');
        return false;
      }

      if (task['barcode'].toString().isEmpty) {
        debugPrint('❌ Empty barcode in task ${task['id']}');
        return false;
      }

      if (task['location'].toString().isEmpty) {
        debugPrint('❌ Empty location in task ${task['id']}');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ Task validation error: $e');
      return false;
    }
  }

  // ✅ FIXED: Enhanced refresh method
  Future<void> refreshPicklistData() async {
    try {
      debugPrint('🔄 Refreshing voice picking data...');

      // Clear current data
      _pickingItems.clear();
      _currentItemIndex = 0;
      _currentItemDetails = null;

      // Reset state to idle
      _currentState = PickingState.idle;
      _isWaitingForScan = false;
      _userInput = "";
      _originalVoiceInput = "";

      // ✅ Reset hands-free mode
      _isHandsFreeModeActive = false;
      _isSessionActive = false;

      // Stop any active voice operations
      if (_isListening) {
        await _speechToText.stop();
        _isListening = false;
      }

      // Reload fresh data from Supabase
      await _loadPickingDataFromSupabase();

      // Update last instruction based on loaded data
      if (_pickingItems.isNotEmpty) {
        _lastInstruction = 'Refreshed - ${_pickingItems.length} items assigned';
      } else {
        _lastInstruction = 'No picking tasks assigned';
      }

      // Notify listeners
      notifyListeners();

      debugPrint('✅ Voice picking data refreshed - ${_pickingItems.length} items available');
    } catch (e) {
      debugPrint('❌ Error refreshing voice picking data: $e');
      _lastInstruction = 'Refresh failed - ${e.toString()}';
      notifyListeners();
      throw Exception('Failed to refresh picking data: $e');
    }
  }

  // Real-time data refresh timer
  void _startDataRefreshTimer() {
    _dataRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isProcessing && _currentState != PickingState.barcodeScanning) {
        _refreshPickingDataSilently();
      }
    });
  }

  // Silent refresh for background updates
  Future<void> _refreshPickingDataSilently() async {
    try {
      final refreshedTasks = await VoiceService.getAssignedPicklist(pickerId: userName);
      
      if (refreshedTasks.length != _pickingItems.length) {
        _pickingItems = refreshedTasks.where((task) => _validateTaskData(task)).toList();
        
        if (_pickingItems.isNotEmpty && _currentItemIndex < _pickingItems.length) {
          _currentItemDetails = _pickingItems[_currentItemIndex];
        }
        
        notifyListeners();
        debugPrint('🔄 Picking data refreshed silently: ${_pickingItems.length} items');
      }
    } catch (e) {
      debugPrint('❌ Silent data refresh error: $e');
    }
  }

  Future<void> _initializeVoiceServices() async {
    try {
      debugPrint('🎤 Initializing voice services...');
      _voiceStatus = VoiceStatus.initializing;
      notifyListeners();

      _speechToText = SpeechToText();
      _flutterTts = FlutterTts();

      await _requestPermissions();

      bool available = await _speechToText.initialize(
        onError: _handleSpeechError,
        onStatus: _handleSpeechStatus,
        debugLogging: true,
        finalTimeout: const Duration(seconds: 4),
        options: [SpeechToText.webDoNotAggregate],
      );

      _speechEnabled = available;
      _voiceStatus = available ? VoiceStatus.idle : VoiceStatus.error;
      notifyListeners();

      await _configureTTS();

      if (available) {
        debugPrint('✅ Voice services initialized successfully');
        _consecutiveErrors = 0;
      } else {
        throw Exception('Speech recognition service unavailable');
      }
    } catch (e) {
      debugPrint('❌ Voice services initialization error: $e');
      _speechEnabled = false;
      _voiceStatus = VoiceStatus.error;
      _consecutiveErrors++;
      notifyListeners();

      if (_consecutiveErrors < _maxConsecutiveErrors) {
        debugPrint('🔄 Attempting voice service recovery...');
        _scheduleVoiceServiceRestart();
      }
    }
  }

  Future<void> _requestPermissions() async {
    try {
      debugPrint('🔑 Requesting permissions...');
      Map<Permission, PermissionStatus> permissions = await [
        Permission.microphone,
        Permission.speech,
      ].request();

      bool allGranted = permissions.values.every(
        (status) => status == PermissionStatus.granted,
      );

      if (!allGranted) {
        throw Exception('Required permissions not granted: $permissions');
      }

      debugPrint('✅ All permissions granted successfully');
    } catch (e) {
      debugPrint('❌ Permission error: $e');
      rethrow;
    }
  }

  Future<void> _configureTTS() async {
    try {
      debugPrint('🔊 Configuring TTS with user settings...');
      await _loadVoiceSettings();
      await _flutterTts.setPitch(1.0);

      _flutterTts.setErrorHandler((msg) {
        debugPrint('❌ TTS Error: $msg');
        _handleTTSError(msg);
      });

      _flutterTts.setCompletionHandler(() {
        debugPrint('✅ TTS Completed');
        _onTTSCompleted();
      });

      debugPrint('✅ TTS configured successfully with user settings');
    } catch (e) {
      debugPrint('❌ TTS configuration error: $e');
    }
  }

  // ================================
  // ✅ ENHANCED HANDS-FREE WORKFLOW
  // ================================
  void startPickingSession() {
    try {
      if (!_isDataLoaded || _pickingItems.isEmpty) {
        _lastInstruction = "NO TASKS AVAILABLE";
        _speakMessage("No tasks available.");
        return;
      }

      if (!_speechEnabled) {
        _lastInstruction = "VOICE NOT AVAILABLE";
        _speakMessage("Voice not available.");
        return;
      }

      debugPrint('🚀 Starting hands-free picking session with ${_pickingItems.length} items from Supabase');

      _currentState = PickingState.ready;
      _currentItemIndex = 0;
      _completedItems = 0;
      _currentItemDetails = _pickingItems.isNotEmpty ? _pickingItems[0] : null;
      _lastInstruction = "Say READY to begin";
      _isContinuousMode = true;

      // ✅ Enable hands-free mode
      _isHandsFreeModeActive = true;
      _isSessionActive = true;

      notifyListeners();

      // Start listening immediately for "READY" command
      _speakMessage("Ready. You have ${_pickingItems.length} items. Say READY to start.");

      // Auto-start listening after TTS completes
      Future.delayed(const Duration(seconds: 3), () {
        if (_currentState == PickingState.ready && !_isListening) {
          startVoiceListening();
        }
      });
    } catch (e) {
      debugPrint('❌ Start picking session error: $e');
      _lastInstruction = "SESSION START FAILED";
      notifyListeners();
    }
  }

  void executeCommand(String command) {
    try {
      debugPrint('⚡ Executing command: "$command" in state: ${_currentState.name}');

      switch (_currentState) {
        case PickingState.ready:
        case PickingState.readyWait:
          if (command == "READY") {
            _proceedToLocation();
            // ✅ Continue listening after command execution
            _scheduleNextListening();
          }
          break;

        case PickingState.locationCheck:
          _verifyLocationCheckDigit(command);
          // ✅ Continue listening after command execution
          _scheduleNextListening();
          break;

        case PickingState.itemCheck:
          // Handle item verification commands
          _scheduleNextListening();
          break;

        case PickingState.barcodeScanning:
          // Barcode scanning is handled separately
          break;

        case PickingState.idle:
        case PickingState.completed:
          // Session ended - stop hands-free mode
          _isHandsFreeModeActive = false;
          _isSessionActive = false;
          break;
      }
    } catch (e) {
      debugPrint('❌ Command execution error: $e');
    }
  }

  // ✅ NEW METHOD: Schedule next listening in hands-free mode
  void _scheduleNextListening() {
    if (_isHandsFreeModeActive && _isSessionActive && !_isWaitingForScan) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!_isListening && _shouldRestartListening()) {
          debugPrint('🎤 Auto-restarting listening in hands-free mode...');
          startVoiceListening();
        }
      });
    }
  }

  void _proceedToLocation() {
    try {
      final currentItem = _getCurrentItem();
      if (currentItem == null) {
        _lastInstruction = "NO CURRENT ITEM";
        return;
      }

      _currentState = PickingState.locationCheck;
      _currentItemDetails = currentItem;
      _lastInstruction = "Go to ${currentItem['location']}";
      notifyListeners();

      // SHORT INSTRUCTION: Go To Location
      _speakMessage("Go to ${currentItem['location']}. Say check digit.");
    } catch (e) {
      debugPrint('❌ Proceed to location error: $e');
    }
  }

  Future<void> _verifyLocationCheckDigit(String userInput) async {
    try {
      final currentItem = _getCurrentItem();
      if (currentItem == null) return;

      String expectedDigit = currentItem['location_check_digit']?.toString() ?? '00';

      if (userInput.trim() == expectedDigit) {
        _currentState = PickingState.barcodeScanning;
        _lastInstruction = "Location OK. Scan barcode";
        _isWaitingForScan = true;
        notifyListeners();

        // SHORT INSTRUCTION: Confirm Location + Scan Item
        _speakMessage("Location OK. Scan barcode.");
      } else {
        // SHORT INSTRUCTION: Location Error
        _speakMessage("Wrong digit. Say $expectedDigit.");
      }
    } catch (e) {
      debugPrint('❌ Verify location check digit error: $e');
    }
  }

  void handleBarcodeInput(String scannedBarcode) {
    try {
      if (!_isWaitingForScan || scannedBarcode.trim().isEmpty) return;

      _isWaitingForScan = false;
      notifyListeners();

      debugPrint('📱 EDA51 Scanner result: $scannedBarcode');
      _lastScannedBarcode = scannedBarcode;
      _verifyScannedBarcode(scannedBarcode);
    } catch (e) {
      debugPrint('❌ Handle barcode input error: $e');
    }
  }

  Future<void> _verifyScannedBarcode(String scannedBarcode) async {
    try {
      final currentItem = _getCurrentItem();
      if (currentItem == null) return;

      debugPrint('🔍 Verifying scanned barcode: $scannedBarcode');
      String expectedBarcode = currentItem['barcode']?.toString() ?? '';

      if (scannedBarcode.trim() == expectedBarcode.trim()) {
        await _updateInventoryAndProceed(currentItem, scannedBarcode);
      } else {
        _currentState = PickingState.barcodeScanning;
        _lastInstruction = "Wrong barcode - scan again";
        _isWaitingForScan = true;
        notifyListeners();

        // SHORT INSTRUCTION: Barcode Error
        _speakMessage("Wrong barcode. Scan again.");
      }
    } catch (e) {
      debugPrint('❌ Verify scanned barcode error: $e');
    }
  }

  Future<void> _updateInventoryAndProceed(Map<String, dynamic> item, String barcode) async {
    try {
      debugPrint('📦 Updating REAL inventory in Supabase for item: ${item['item_name']}');
      _lastInstruction = "Updating inventory...";
      notifyListeners();

      final updateResult = await VoiceService.updateInventoryPick(
        inventoryId: item['inventory_id'],
        quantityPicked: item['quantity_requested'] ?? 1,
        pickerId: userName,
        picklistId: item['id'],
        timestamp: DateTime.now(),
      );

      if (updateResult['success']) {
        await VoiceService.updateTaskStatus(
          taskId: item['id'],
          status: 'completed',
          completedAt: DateTime.now(),
        );

        _completedItems++;
        _currentItemIndex++;
        notifyListeners();
        HapticFeedback.mediumImpact();

        int pickedQty = updateResult['quantityPicked'] ?? 1;

        if (_currentItemIndex >= _pickingItems.length) {
          _completePickingSession();
        } else {
          // Update current item details
          _currentItemDetails = _pickingItems[_currentItemIndex];

          // SHORT INSTRUCTION: Pick Confirm + Next Item
          _speakMessage("Barcode OK. Pick quantity $pickedQty. Next item.");

          Future.delayed(const Duration(seconds: 2), () {
            _currentState = PickingState.ready;
            notifyListeners();
            _proceedToLocation();
          });
        }
      } else {
        throw Exception(updateResult['error'] ?? 'Inventory update failed');
      }
    } catch (e) {
      debugPrint('❌ Update inventory error: $e');
      _currentState = PickingState.barcodeScanning;
      _lastInstruction = "Update failed - retry";
      _isWaitingForScan = true;
      notifyListeners();
      _speakMessage("Update failed. Scan again.");
    }
  }

  Map<String, dynamic>? _getCurrentItem() {
    try {
      if (_currentItemIndex >= 0 && _currentItemIndex < _pickingItems.length) {
        return _pickingItems[_currentItemIndex];
      }
      return null;
    } catch (e) {
      debugPrint('❌ Get current item error: $e');
      return null;
    }
  }

  void _completePickingSession() {
    try {
      _currentState = PickingState.completed;
      _lastInstruction = "All items picked";
      _isContinuousMode = false;
      _isListening = false;

      // ✅ Disable hands-free mode
      _isHandsFreeModeActive = false;
      _isSessionActive = false;
      _isWaitingForScan = false;

      notifyListeners();

      _speechToText.stop();
      _sessionTimer?.cancel();
      _dataRefreshTimer?.cancel();

      HapticFeedback.heavyImpact();

      // SHORT INSTRUCTION: Finish
      _speakMessage("All items picked. Session complete.");

      if (_currentSessionId != null) {
        VoiceService.savePickingSession(
          pickerId: userName,
          picklistId: _currentSessionId!,
          metrics: {
            'totalItems': _pickingItems.length,
            'completedItems': _completedItems,
            'sessionTime': _sessionTime.inSeconds,
            'retryCount': _retryCount,
            'completedAt': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      debugPrint('❌ Complete picking session error: $e');
    }
  }

  // ================================
  // VOICE PROCESSING METHODS
  // ================================
  void _handleSpeechError(dynamic error) {
    try {
      String errorMsg = error?.errorMsg ?? error.toString();
      debugPrint('❌ Speech error: $errorMsg');

      _isListening = false;
      _voiceStatus = VoiceStatus.error;
      notifyListeners();

      if (errorMsg.contains('network') || errorMsg.contains('connection')) {
        _scheduleVoiceRestart(5000);
      } else if (errorMsg.contains('timeout') || errorMsg.contains('no match')) {
        _scheduleVoiceRestart(800);
      } else if (errorMsg.contains('audio') || errorMsg.contains('microphone')) {
        _handleMicrophoneError();
      } else {
        _retryCount++;
        if (_retryCount <= _maxRetries) {
          int delay = min(2000 * _retryCount, 10000);
          _scheduleVoiceRestart(delay);
        } else {
          _resetVoiceRetry();
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling speech error: $e');
    }
  }

  Future<void> _handleMicrophoneError() async {
    try {
      PermissionStatus status = await Permission.microphone.status;
      if (status != PermissionStatus.granted) {
        debugPrint('❌ Microphone permission lost');
        return;
      }

      _scheduleVoiceServiceRestart();
    } catch (e) {
      debugPrint('❌ Microphone error handling failed: $e');
      _scheduleVoiceRestart(2000);
    }
  }

  void _handleSpeechStatus(String status) {
    try {
      debugPrint('🎤 Speech status: $status');

      switch (status) {
        case 'listening':
          _isListening = true;
          _voiceStatus = VoiceStatus.listening;
          _retryCount = 0;
          _consecutiveErrors = 0;
          _startListeningTimer();
          break;

        case 'notListening':
          _isListening = false;
          _voiceStatus = VoiceStatus.idle;
          _cancelListeningTimer();
          if (_isContinuousMode && _shouldRestartListening()) {
            _scheduleVoiceRestart(1000);
          }
          break;

        case 'done':
          _isListening = false;
          _voiceStatus = VoiceStatus.completed;
          _cancelListeningTimer();
          break;

        default:
          _voiceStatus = VoiceStatus.idle;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Status handling error: $e');
    }
  }

  void _handleTTSError(String error) {
    try {
      debugPrint('❌ TTS Error: $error');
    } catch (e) {
      debugPrint('❌ TTS error handling failed: $e');
    }
  }

  // ✅ UPDATED: Enhanced TTS completion with hands-free support
  void _onTTSCompleted() {
    try {
      debugPrint('✅ TTS completed - checking for hands-free auto-restart');
      
      if (_isHandsFreeModeActive && _isSessionActive && _shouldRestartListening()) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!_isListening) {
            debugPrint('🎤 Auto-starting listening after TTS in hands-free mode');
            startVoiceListening();
          }
        });
      }
    } catch (e) {
      debugPrint('❌ TTS completion handling error: $e');
    }
  }

  // ✅ UPDATED: Enhanced listening restart logic
  bool _shouldRestartListening() {
    try {
      return _speechEnabled &&
          !_isListening &&
          !_isProcessing &&
          !_isWaitingForScan &&
          _isHandsFreeModeActive && // ✅ Only restart if hands-free is active
          _isSessionActive && // ✅ Only restart if session is active
          _currentState != PickingState.idle &&
          _currentState != PickingState.completed;
    } catch (e) {
      debugPrint('❌ Restart check error: $e');
      return false;
    }
  }

  Future<void> startVoiceListening() async {
    try {
      if (!_speechEnabled || _isListening || !_isSystemReady || _isWaitingForScan) {
        debugPrint('⚠️ Cannot start listening - system not ready or waiting for scan');
        return;
      }

      debugPrint('🎤 Starting enhanced voice listening...');
      _voiceStatus = VoiceStatus.listening;
      notifyListeners();

      await _speechToText.listen(
        onResult: _handleVoiceResult,
        listenFor: Duration(seconds: _listeningTimeout),
        pauseFor: const Duration(seconds: 3),
        localeId: "en_US",
        onSoundLevelChange: (level) {
          _soundLevel = level.clamp(0.0, 1.0);
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (e) {
      debugPrint('❌ Start listening error: $e');
      _handleSpeechError(e);
    }
  }

  void _handleVoiceResult(dynamic result) {
    try {
      String recognizedWords = result.recognizedWords.trim();
      bool isFinal = result.finalResult;
      double confidence = result.confidence ?? 0.0;

      debugPrint('🎤 Voice result: "$recognizedWords" (final: $isFinal, confidence: ${(confidence * 100).toInt()}%)');

      if (isFinal && recognizedWords.isNotEmpty) {
        _originalVoiceInput = recognizedWords;
        _voiceStatus = VoiceStatus.processing;
        notifyListeners();

        _processingTimer = Timer(const Duration(milliseconds: 800), () {
          _processVoiceCommandWithParsing(recognizedWords);
        });
      }
    } catch (e) {
      debugPrint('❌ Voice result handling error: $e');
    }
  }

  void _processVoiceCommandWithParsing(String rawInput) {
    try {
      if (_isProcessing) {
        debugPrint('⚠️ Already processing, skipping');
        return;
      }

      _isProcessing = true;
      notifyListeners();
      HapticFeedback.lightImpact();

      List<String> expectedCommands = VoiceCommandParser.getExpectedCommands(
        _currentState.name,
        _getCurrentItemMap(),
      );

      debugPrint('🔍 Expected commands for ${_currentState.name}: $expectedCommands');

      String parsedCommand = VoiceCommandParser.parseCommand(rawInput, expectedCommands);
      _userInput = parsedCommand.isNotEmpty ? parsedCommand : rawInput.toUpperCase();
      notifyListeners();

      if (parsedCommand.isNotEmpty) {
        debugPrint('✅ Successfully parsed: "$rawInput" -> "$parsedCommand"');
        executeCommand(parsedCommand);
      } else {
        debugPrint('❌ Failed to parse: "$rawInput"');
        _handleUnrecognizedCommand(rawInput);
      }

      Future.delayed(const Duration(milliseconds: 1500), () {
        _isProcessing = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('❌ Command processing error: $e');
      _isProcessing = false;
      notifyListeners();
    }
  }

  void _handleUnrecognizedCommand(String rawInput) {
    try {
      List<String> expectedCommands = VoiceCommandParser.getExpectedCommands(
        _currentState.name,
        _getCurrentItemMap(),
      );

      String expectedText = expectedCommands.isNotEmpty
          ? expectedCommands.join(' or ')
          : 'valid command';

      debugPrint('❓ Unrecognized: "$rawInput" - Expected: $expectedText');
      _speakMessage('Say $expectedText');
    } catch (e) {
      debugPrint('❌ Unrecognized command handling error: $e');
    }
  }

  Map<String, dynamic>? _getCurrentItemMap() {
    try {
      final item = _getCurrentItem();
      if (item == null) return null;

      return {
        'locationCheckDigit': item['location_check_digit']?.toString() ?? '00',
        'barcodeDigits': item['barcode_digits']?.toString() ?? '',
        'quantity': item['quantity_requested'],
      };
    } catch (e) {
      debugPrint('❌ Current item map error: $e');
      return null;
    }
  }

  Future<void> _speakMessage(String message) async {
    try {
      if (!_voiceEnabled) {
        debugPrint('🔇 Voice disabled - skipping TTS: $message');
        return;
      }

      debugPrint('🔊 Speaking: $message');

      if (_isListening) {
        await _speechToText.stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('❌ TTS error: $e');
      _handleTTSError(e.toString());
    }
  }

  void _startListeningTimer() {
    try {
      _cancelListeningTimer();
      _listeningTimer = Timer(Duration(seconds: _listeningTimeout + 5), () {
        if (_isListening) {
          debugPrint('⏰ Listening timeout - auto-restart');
          _speechToText.stop();
        }
      });
    } catch (e) {
      debugPrint('❌ Listening timer error: $e');
    }
  }

  void _cancelListeningTimer() {
    try {
      _listeningTimer?.cancel();
      _listeningTimer = null;
    } catch (e) {
      debugPrint('❌ Cancel listening timer error: $e');
    }
  }

  void _scheduleVoiceRestart(int delayMs) {
    try {
      _restartTimer?.cancel();
      _voiceStatus = VoiceStatus.retrying;
      notifyListeners();

      _restartTimer = Timer(Duration(milliseconds: delayMs), () {
        if (_speechEnabled && !_isListening && _shouldRestartListening()) {
          debugPrint('🔄 Auto-restarting voice listening...');
          startVoiceListening();
        }
      });
    } catch (e) {
      debugPrint('❌ Schedule voice restart error: $e');
    }
  }

  void _scheduleVoiceServiceRestart() {
    try {
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(seconds: 3), () {
        debugPrint('🔄 Restarting voice services...');
        _initializeVoiceServices();
      });
    } catch (e) {
      debugPrint('❌ Schedule service restart error: $e');
    }
  }

  void _resetVoiceRetry() {
    try {
      _retryCount = 0;
      _restartTimer?.cancel();
      _voiceStatus = VoiceStatus.error;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Reset voice retry error: $e');
    }
  }

  // ================================
  // PUBLIC METHODS FOR UI
  // ================================
  void handleMicrophoneButtonTap() {
    try {
      HapticFeedback.lightImpact();

      if (!_speechEnabled) {
        debugPrint('⚠️ Speech not enabled - attempting reinitialization');
        _initializeVoiceServices();
        return;
      }

      if (_currentState == PickingState.idle) {
        // ✅ Start hands-free session with one tap
        debugPrint('🎤 Starting hands-free picking session...');
        startPickingSession();
      } else if (_isHandsFreeModeActive) {
        // Show status message - no need to tap again
        debugPrint('📢 Hands-free mode is already active');
      } else {
        // Fallback for manual mode
        if (_isListening) {
          debugPrint('🛑 Manually stopping listening');
          _speechToText.stop();
        } else if (!_isWaitingForScan) {
          debugPrint('🎤 Manually starting listening');
          startVoiceListening();
        }
      }
    } catch (e) {
      debugPrint('❌ Microphone button error: $e');
    }
  }

  void toggleContinuousMode() {
    _isContinuousMode = !_isContinuousMode;
    notifyListeners();
  }

  void resetSession() {
    try {
      debugPrint('🔄 Resetting picking session and refreshing real data...');

      _currentState = PickingState.idle;
      _currentItemIndex = 0;
      _completedItems = 0;
      _lastInstruction = "RESETTING";
      _userInput = "";
      _originalVoiceInput = "";
      _isProcessing = false;
      _isContinuousMode = true;
      _isListening = false;

      // ✅ Reset hands-free mode
      _isHandsFreeModeActive = false;
      _isSessionActive = false;

      _voiceStatus = VoiceStatus.idle;
      _retryCount = 0;
      _consecutiveErrors = 0;
      _currentItemDetails = null;
      _isWaitingForScan = false;

      notifyListeners();

      _speechToText.stop();
      _sessionTimer?.cancel();
      _dataRefreshTimer?.cancel();
      _cancelListeningTimer();
      _restartTimer?.cancel();
      _processingTimer?.cancel();

      _initializeSession();
      _loadPickingDataFromSupabase();

      debugPrint('✅ Session reset successfully with fresh Supabase data');
    } catch (e) {
      debugPrint('❌ Session reset error: $e');
    }
  }

  String formatDuration(Duration duration) {
    try {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      return '${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}';
    } catch (e) {
      debugPrint('❌ Format duration error: $e');
      return '00:00';
    }
  }

  // ================================
  // DISPOSE
  // ================================
  @override
  void dispose() {
    try {
      debugPrint('🧹 Disposing voice picking controller...');

      _sessionTimer?.cancel();
      _listeningTimer?.cancel();
      _restartTimer?.cancel();
      _processingTimer?.cancel();
      _dataRefreshTimer?.cancel();

      _speechToText.stop();
      _flutterTts.stop();

      debugPrint('✅ Voice picking controller disposed successfully');
    } catch (e) {
      debugPrint('❌ Dispose error: $e');
    }

    super.dispose();
  }
}
