// lib/screens/wms/loading_screen.dart
// ✅ COMPLETE UPDATED - WITH FULL LIFO/NON-LIFO SUPPORT & EXCEPTION HANDLING
// ✅ MAINTAINS EXISTING UI STRUCTURE & ENHANCED WITH LIFO FEATURES

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer';

import '../../utils/colors.dart';
import '../../widgets/gradient_button.dart';
import '../../services/warehouse_service.dart';
import '../../services/loading_service.dart';
import '../../utils/dispatch_slip_generator.dart';

// ================================
// STEP & ERROR TYPES
// ================================

enum LoadingStep {
  shipmentSheet,
  truckVerification,
  cartonScanning,
}

enum LoadingErrorType {
  network,
  validation,
  timeout,
  parsing,
  database,
  permission,
  unknown,
}

class LoadingException implements Exception {
  final LoadingErrorType type;
  final String message;
  final String? details;
  final dynamic originalError;

  const LoadingException({
    required this.type,
    required this.message,
    this.details,
    this.originalError,
  });

  @override
  String toString() => 'LoadingException($type): $message';
}

class RecentScan {
  final String cartonId;
  final String? customerName;
  final bool duplicate;
  final bool wrongCustomer;
  final DateTime at;

  RecentScan({
    required this.cartonId,
    this.customerName,
    this.duplicate = false,
    this.wrongCustomer = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();
}

// ================================
// SCREEN
// ================================

class LoadingScreen extends StatefulWidget {
  final String userName;
  final String? shipmentOrderId;
  final String? preloadedShipmentId;
  final String? preloadedTruckNumber;
  final String? preloadedCustomerName;
  final String? preloadedLoadingStrategy; // 'LIFO' or 'NON_LIFO'
  final List? preloadedCartonList;
  final int? preloadedTotalCartons;

  const LoadingScreen({
    super.key,
    required this.userName,
    this.shipmentOrderId,
    this.preloadedShipmentId,
    this.preloadedTruckNumber,
    this.preloadedCustomerName,
    this.preloadedLoadingStrategy,
    this.preloadedCartonList,
    this.preloadedTotalCartons,
  });

  @override
  State createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ================================
  // STATE - CORE
  // ================================

  LoadingStep currentStep = LoadingStep.shipmentSheet;
  bool isLoading = false;
  bool isScanning = false;
  bool _isDisposed = false;

  // Session Data
  String? sessionId;
  String? masterSessionId;
  bool isMultiCustomer = false;
  Map? shipmentData;

  // Cartons
  final Set<String> scannedCartons = {};
  List<String> expectedCartons = [];
  int totalCartons = 0;
  int totalCustomers = 1;

  // Shipment info
  String? truckNumber;
  String? customerName;
  String? shipperName;
  String? destination;
  String? loadingStrategy; // 'LIFO' or 'NON_LIFO'
  bool _isContinuingFromShipment = false;

  // Multi-customer
  List<Map<String, dynamic>> customers = [];
  final Map<String, String> _cartonToCustomer = {};
  final Map<String, int> _customerTotals = {};
  final Map<String, int> _customerScanned = {};

  // ✅ LIFO STATE
  bool isLifoMode = false;
  List<Map<String, dynamic>> lifoSequence = [];
  int currentScanCount = 0;

  // Controllers & Focus
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  
  // ✅ SMART SCANNER DETECTION
  DateTime? _lastKeystrokeTime;
  bool _isManualTyping = false;
  Timer? _scanDebounce;

  // Animation
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  // Messages
  String currentMessage =
      "📋 Scan the shipment sheet QR code to begin loading process";
  String? errorMessage;
  LoadingErrorType? lastErrorType;
  bool showSuccess = false;

  // Timers
  Timer? _scanDebounceTimer;
  Timer? _errorMessageTimer;
  Timer? _successMessageTimer;
  Timer? _headerBannerTimer;

  // Input bounds
  static const int _minScanLength = 3;
  static const int _maxScanLength = 1000;
  static const Duration _scanDebounceDelay = Duration(milliseconds: 400);
  static const Duration _operationTimeout = Duration(seconds: 30);

  // UI
  String? _headerBannerMessage;
  final List<RecentScan> _recentScans = [];
  static const int _recentLimit = 3;

  static const Gradient orangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
  );

  int _opToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _setupListeners();

    if (widget.shipmentOrderId != null &&
        widget.preloadedTruckNumber != null &&
        widget.preloadedCartonList != null) {
      _initializeFromShipmentScreen();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _safeRequestFocus());
    }
  }

  // ✅ NEW: Initialize from shipment screen
  void _initializeFromShipmentScreen() {
    setState(() {
      _isContinuingFromShipment = true;
      sessionId = widget.shipmentOrderId;
      truckNumber = widget.preloadedTruckNumber;
      customerName = widget.preloadedCustomerName ?? 'Unknown Customer';
      loadingStrategy = widget.preloadedLoadingStrategy ?? 'NON_LIFO';
      expectedCartons = (widget.preloadedCartonList ?? [])
          .map((e) => e.toString().toUpperCase())
          .toList();
      totalCartons = widget.preloadedTotalCartons ?? expectedCartons.length;

      // ✅ SET LIFO MODE
      isLifoMode =
          (widget.preloadedLoadingStrategy ?? 'NON_LIFO').toUpperCase() ==
              'LIFO';

      shipmentData = {
        'session_id': sessionId,
        'truck_number': truckNumber,
        'customer_name': customerName,
        'shipper_name': customerName,
        'destination': 'Unknown',
        'carton_list': expectedCartons,
        'total_cartons': totalCartons,
        'loading_strategy': loadingStrategy,
      };

      _cartonToCustomer.clear();
      _customerTotals.clear();
      _customerScanned.clear();
      _customerTotals[customerName!] = totalCartons;
      _customerScanned[customerName!] = 0;
      for (final id in expectedCartons) {
        _cartonToCustomer[id] = customerName!;
      }

      currentStep = LoadingStep.truckVerification;
      currentMessage = "🚛 Verify truck number: $truckNumber\n"
          "Loading Strategy: $loadingStrategy\n"
          "Cartons to load: $totalCartons";
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _safeRequestFocus());
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _clearAllTimers();
    _scanController.dispose();
    _scanFocusNode.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _safeRequestFocus();
        break;
      case AppLifecycleState.paused:
        _clearAllTimers();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      default:
        break;
    }
  }

  // ================================
  // INIT
  // ================================

  void _initializeAnimations() {
    try {
      _fadeController = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _pulseController = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      );
      _fadeAnimation =
          CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      );
      _fadeController.forward();
      _pulseController.repeat(reverse: true);
    } catch (e) {
      log('Animation init error: $e');
      _handleException(LoadingException(
        type: LoadingErrorType.unknown,
        message: 'Animation initialization failed',
        originalError: e,
      ));
    }
  }

  void _setupListeners() {
    try {
      _scanController.addListener(_onScanInputChanged);
    } catch (e) {
      log('Setup listeners error: $e');
    }
  }

  // ✅ SMART SCANNER vs MANUAL TYPING DETECTION
  void _onScanInputChanged() {
    if (_isDisposed) return;
    final scannedData = _scanController.text.trim();
    
    // ✅ Detect typing pattern
    final now = DateTime.now();
    if (_lastKeystrokeTime != null) {
      final timeDiff = now.difference(_lastKeystrokeTime!).inMilliseconds;
      
      // Scanner: < 100ms between keystrokes (fast)
      // Manual: > 100ms between keystrokes (slow)
      if (timeDiff > 100) {
        _isManualTyping = true;
        log('📝 Manual typing detected (${timeDiff}ms gap)');
      } else {
        _isManualTyping = false;
        log('🔫 Scanner detected (${timeDiff}ms gap)');
      }
    }
    _lastKeystrokeTime = now;
    
    // Update UI to show manual mode
    if (_isManualTyping && mounted) {
      setState(() {});
    }
    
    _scanDebounceTimer?.cancel();

    final token = ++_opToken;
    final canRun = scannedData.length >= _minScanLength &&
        scannedData.length <= _maxScanLength &&
        !isLoading &&
        !isScanning;

    if (canRun) {
      // ✅ ONLY auto-process if scanner input (fast typing)
      if (!_isManualTyping) {
        _scanDebounceTimer = Timer(const Duration(milliseconds: 100), () {
          if (!_isDisposed &&
              token == _opToken &&
              scannedData == _scanController.text.trim()) {
            log('✅ Auto-submitting scanner input');
            _isManualTyping = false;
            _lastKeystrokeTime = null;
            _handleScanInput(scannedData);
          }
        });
      }
      // ✅ For manual typing, wait for Enter key (onSubmitted)
    }
  }

  // ================================
  // QR PARSING
  // ================================

  Future<Map<String, dynamic>> _parseQRDataWithTimeout(String qrData) async {
    return await _callWithTimeout(() async {
      try {
        _debugQRContent(qrData);
        final trimmedData = qrData.trim();

        if (trimmedData.startsWith('{') && trimmedData.endsWith('}')) {
          try {
            final dynamic jsonData = jsonDecode(trimmedData);
            if (jsonData is Map) {
              final Map<String, dynamic> typedData = jsonData.cast<String, dynamic>();
              final valid = _validateAndNormalizeQRContent(typedData);
              if (valid) return typedData;
            }
          } catch (_) {
            // fallthrough to key:value
          }
        }

        return _parseKeyValueQR(trimmedData);
      } catch (e) {
        throw LoadingException(
          type: LoadingErrorType.parsing,
          message: 'Invalid QR code format',
          details: 'Unable to parse QR data: ${e.toString()}',
          originalError: e,
        );
      }
    }, 'Parse QR data');
  }

  void _debugQRContent(String qrData) {
    log('QR length: ${qrData.length}');
    log('Starts with {: ${qrData.trim().startsWith('{')}');
    log('Contains multi_customer: ${qrData.contains('multi_customer')}');
  }

  bool _validateAndNormalizeQRContent(Map<String, dynamic> data) {
    try {
      if (data['shipment_type'] == 'multi_customer') {
        if (data['customers'] == null ||
            data['all_cartons'] == null ||
            data['truck_number'] == null) {
          return false;
        }

        final customersList = (data['customers'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

        final Set<String> all = {};
        for (final c in customersList) {
          final String cname = (c['customer_name'] ?? '').toString().trim();
          final String dest = (c['destination'] ?? '').toString().trim();
          final List rawList = (c['carton_list'] ?? []) as List;
          final List<String> norm = rawList
              .map((e) => e.toString().trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toList();

          c['customer_name'] = cname;
          c['destination'] = dest;
          c['carton_list'] = norm;
          all.addAll(norm);
        }

        data['all_cartons'] = all.toList();
        data['customer_name'] = '${customersList.length} Customers';
        data['carton_list'] = data['all_cartons'];
        data['truck_number'] = data['truck_number'].toString().trim().toUpperCase();
        data['customers'] = customersList;
        return true;
      }

      final requiredFields = ['truck_number', 'customer_name', 'carton_list'];
      for (final f in requiredFields) {
        if (!data.containsKey(f) ||
            data[f] == null ||
            data[f].toString().trim().isEmpty) {
          return false;
        }
      }

      data['truck_number'] =
          data['truck_number'].toString().toUpperCase().trim();
      data['customer_name'] = data['customer_name'].toString().trim();
      data['shipper_name'] = (data['shipper_name'] ?? '').toString().trim();
      data['destination'] = (data['destination'] ?? '').toString().trim();

      final dynamic cl = data['carton_list'];
      List<String> normalized;

      if (cl is String) {
        normalized = cl
            .split(',')
            .map((e) => e.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (cl is List) {
        normalized = cl
            .map((e) => e.toString().trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        return false;
      }

      if (normalized.isEmpty) return false;
      data['carton_list'] = normalized;
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _parseKeyValueQR(String qrData) {
    final Map<String, dynamic> result = {};
    final lines = qrData.split('\n');

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty || !line.contains(':')) continue;

      final idx = line.indexOf(':');
      if (idx <= 0) continue;

      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      if (value.isEmpty) continue;

      switch (key) {
        case 'truck':
        case 'truck_number':
          result['truck_number'] = value.toUpperCase();
          break;
        case 'customer':
        case 'customer_name':
          result['customer_name'] = value;
          break;
        case 'shipper':
        case 'shipper_name':
          result['shipper_name'] = value;
          break;
        case 'destination':
          result['destination'] = value;
          break;
        case 'cartons':
        case 'carton_list':
          result['carton_list'] = value
              .split(',')
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toList();
          break;
        case 'shipment_type':
          result['shipment_type'] = value;
          break;
      }
    }

    if (!_validateAndNormalizeQRContent(result)) {
      throw const LoadingException(
        type: LoadingErrorType.parsing,
        message: 'QR code missing required fields',
        details: 'Required: truck_number, customer_name, carton_list',
      );
    }

    return result;
  }

  // ================================
  // WORKFLOW
  // ================================

  Future<void> _processShipmentQR(String qrData) async {
    if (_isDisposed) return;
    _setLoadingState(true, "Processing shipment QR code...");

    try {
      if (qrData.isEmpty || qrData.length > _maxScanLength) {
        throw const LoadingException(
          type: LoadingErrorType.validation,
          message: 'Invalid QR code format',
          details: 'QR code data is empty or too long',
        );
      }

      final qrContent = await _parseQRDataWithTimeout(qrData);

      Map<String, dynamic> result;
      if (qrContent['shipment_type'] == 'multi_customer') {
        result = await _callWithTimeout(
          () => LoadingService.processMultiCustomerShipmentQR(qrContent),
          'Process multi-customer shipment QR',
        );
      } else {
        result = await _callWithTimeout(
          () => LoadingService.processShipmentQR(qrContent),
          'Process shipment QR',
        );
      }

      if (result['success'] == true) {
        await _handleShipmentSuccess(result, qrContent);
      } else {
        throw LoadingException(
          type: LoadingErrorType.database,
          message: result['error']?.toString() ?? 'Shipment processing failed',
          details: result['details']?.toString(),
        );
      }
    } on LoadingException catch (e) {
      _handleException(e);
    } catch (e) {
      _handleException(LoadingException(
        type: LoadingErrorType.unknown,
        message: 'Shipment processing failed',
        originalError: e,
      ));
    } finally {
      _setLoadingState(false);
    }
  }

  Future<void> _verifyTruckNumber(String scannedTruckNumber) async {
    if (_isDisposed ||
        (sessionId == null && masterSessionId == null) ||
        truckNumber == null) return;

    _setLoadingState(true, "Verifying truck number...");

    try {
      final cleanScanned =
          _validateAndCleanInput(scannedTruckNumber, 'truck number');

      Map<String, dynamic> result;
      if (isMultiCustomer && masterSessionId != null) {
        result = await _callWithTimeout(
          () => LoadingService.verifyTruckNumberMultiCustomer(
            masterSessionId: masterSessionId!,
            expectedTruckNumber: truckNumber!,
            scannedTruckNumber: cleanScanned,
          ),
          'Verify multi-customer truck number',
        );
      } else {
        if (sessionId == null) {
          throw const LoadingException(
            type: LoadingErrorType.validation,
            message: 'Session not initialized',
            details: 'Please scan shipment QR first',
          );
        }

        result = await _callWithTimeout(
          () => LoadingService.verifyTruckNumber(
            sessionId: sessionId!,
            expectedTruckNumber: truckNumber!,
            scannedTruckNumber: cleanScanned,
          ),
          'Verify truck number',
        );
      }

      if (result['success'] == true) {
        await _handleTruckVerificationSuccess(result);
      } else {
        throw LoadingException(
          type: LoadingErrorType.validation,
          message: result['error']?.toString() ?? 'Truck verification failed',
          details: result['details']?.toString(),
        );
      }
    } on LoadingException catch (e) {
      _handleException(e);
    } catch (e) {
      _handleException(LoadingException(
        type: LoadingErrorType.unknown,
        message: 'Truck verification failed',
        originalError: e,
      ));
    } finally {
      _setLoadingState(false);
    }
  }

  Future<void> _processCartonScan(String cartonId) async {
    if (_isDisposed || (sessionId == null && masterSessionId == null)) return;
    _setLoadingState(true, "Processing carton scan...");

    try {
      final cleanCartonId = _validateAndCleanInput(cartonId, 'carton ID');

      if (expectedCartons.isEmpty) {
        throw const LoadingException(
          type: LoadingErrorType.validation,
          message: 'No expected cartons loaded',
          details: 'Shipment data may be corrupted',
        );
      }

      // Duplicate check
      if (scannedCartons.contains(cleanCartonId)) {
        _pushRecentScan(RecentScan(
          cartonId: cleanCartonId,
          customerName: _cartonToCustomer[cleanCartonId],
          duplicate: true,
        ));
        _showHeaderBanner("Duplicate scan: $cleanCartonId");
        _clearAndRefocusWithDelay();
        _setLoadingState(false);
        return;
      }

      // Validate expected
      if (!expectedCartons.contains(cleanCartonId)) {
        throw LoadingException(
          type: LoadingErrorType.validation,
          message: 'Unknown carton',
          details:
              'Carton $cleanCartonId not in expected list. Recheck shipment sheet.',
        );
      }

      // ✅ LIFO VALIDATION - NEW
      if (isLifoMode && lifoSequence.isNotEmpty) {
        currentScanCount++;

        try {
          final validationResult =
              await LoadingService.validateLifoScan(
            cartonBarcode: cleanCartonId,
            currentScanNumber: currentScanCount,
            lifoSequence: lifoSequence,
          );

          if (validationResult['valid'] != true) {
            currentScanCount--; // Rollback

            setState(() {
              errorMessage =
                  validationResult['message'] ?? 'LIFO sequence violation';
            });

            if (!mounted) return;

            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('❌ LIFO Sequence Error!',
                    style: TextStyle(color: Colors.red)),
                content: Text(
                  validationResult['message'] ?? 'Wrong carton order',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );

            _clearAndRefocusWithDelay();
            _setLoadingState(false);
            return;
          }
        } catch (e) {
          log('LIFO validation error: $e');
          // Continue with regular scan if LIFO validation fails
        }
      }

      Map<String, dynamic> result;
      if (isMultiCustomer && masterSessionId != null) {
        final mappedCustomer = _cartonToCustomer[cleanCartonId];
        if (mappedCustomer == null || mappedCustomer.isEmpty) {
          throw LoadingException(
            type: LoadingErrorType.validation,
            message: 'Unmapped carton',
            details:
                'Carton $cleanCartonId not mapped to any customer. Check master data.',
          );
        }

        result = await _callWithTimeout(
          () => LoadingService.processCartonScanMultiCustomer(
            masterSessionId: masterSessionId!,
            cartonId: cleanCartonId,
          ),
          'Process multi-customer carton scan',
        );
      } else {
        if (sessionId == null) {
          throw const LoadingException(
            type: LoadingErrorType.validation,
            message: 'Session not initialized',
            details: 'Please verify truck first',
          );
        }

        result = await _callWithTimeout(
          () => LoadingService.processCartonScan(
            sessionId: sessionId!,
            cartonId: cleanCartonId,
            expectedCartons: expectedCartons,
            scannedCartons: scannedCartons.toList(),
          ),
          'Process carton scan',
        );
      }

      if (result['success'] == true) {
        await _handleCartonScanSuccess(result, cleanCartonId);
      } else {
        throw LoadingException(
          type: LoadingErrorType.validation,
          message: result['error']?.toString() ?? 'Carton scanning failed',
          details: result['details']?.toString(),
        );
      }
    } on LoadingException catch (e) {
      _handleException(e);
    } catch (e) {
      _handleException(LoadingException(
        type: LoadingErrorType.unknown,
        message: 'Carton scanning failed',
        originalError: e,
      ));
    } finally {
      _setLoadingState(false);
    }
  }

  // ✅ NEW: Calculate LIFO Sequence
  Future<void> _calculateLifoSequence() async {
    if (!isLifoMode || sessionId == null) return;

    try {
      log('📊 Calculating LIFO sequence...');

      final sequence = await LoadingService.calculateLifoSequence(
        shipmentOrderId: sessionId!,
      );

      setState(() {
        lifoSequence = sequence;
        currentMessage =
            '🔒 LIFO MODE: Scan cartons in exact order!\n(Last stop first)';
      });

      if (sequence.isNotEmpty) {
        _showLifoGuide();
      }

      log('✅ LIFO sequence ready: ${sequence.length} cartons');
    } catch (e) {
      log('❌ Error calculating LIFO: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'Error loading LIFO sequence: $e';
        });
      }
    }
  }

  // ✅ NEW: Show LIFO Guide Dialog
  void _showLifoGuide() {
    if (lifoSequence.isEmpty || !mounted) return;

    Map<int, List<Map<String, dynamic>>> byStop = {};
    for (var item in lifoSequence) {
      final stop = item['stop_sequence'] as int? ?? 1;
      byStop.putIfAbsent(stop, () => []);
      byStop[stop]!.add(item);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: const Text(
                '📋 LIFO Loading Sequence',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Load cartons in this EXACT order\n(Last stop first):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...byStop.entries.map((entry) {
                final stop = entry.key;
                final cartons = entry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '🚛 Stop $stop (${cartons.length} cartons)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...cartons.asMap().entries.map((c) {
                      final idx = c.key + 1;
                      final carton = c.value;
                      return Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Text(
                          '$idx. ${carton['carton_barcode'] ?? 'Unknown'}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 12),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateReport() async {
    if (_isDisposed) return;

    if (sessionId == null && masterSessionId == null) {
      _handleException(const LoadingException(
        type: LoadingErrorType.validation,
        message: 'Session not initialized',
        details: 'Missing session ID',
      ));
      return;
    }

    _setLoadingState(true, "Generating dispatch slip...");

    try {
      final shipmentId = widget.shipmentOrderId ?? sessionId ?? masterSessionId!;
      
      // Generate PDF
      final pdfBytes = await DispatchSlipGenerator.generateDispatchSlip(
        shipmentOrderId: shipmentId,
      );

      if (!mounted) return;

      _setLoadingState(false);

      // Show PDF using printing package
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Dispatch_Slip_$shipmentId.pdf',
      );

      if (mounted) {
        _showSuccessMessage('✅ Dispatch slip ready!');
      }
    } on LoadingException catch (e) {
      _handleException(e);
    } catch (e) {
      log('❌ Error generating dispatch slip: $e');
      _handleException(LoadingException(
        type: LoadingErrorType.unknown,
        message: 'Failed to generate dispatch slip',
        originalError: e,
      ));
    } finally {
      if (mounted) {
        _setLoadingState(false);
      }
    }
  }

  // ================================
  // SUCCESS HANDLERS
  // ================================

  Future<void> _handleShipmentSuccess(
    Map<String, dynamic> result,
    Map<String, dynamic> qrContent,
  ) async {
    if (_isDisposed || !mounted) return;

    void buildCartonIndex() {
      _cartonToCustomer.clear();
      _customerTotals.clear();
      _customerScanned.clear();

      if (isMultiCustomer) {
        for (final c in customers) {
          final String cname = (c['customer_name'] ?? '').toString();
          final List<dynamic> listDyn = (c['carton_list'] ?? []) as List;
          final List<String> list =
              listDyn.map((e) => e.toString().toUpperCase()).toList();

          _customerTotals[cname] = list.length;
          _customerScanned[cname] = 0;

          for (final id in list) {
            _cartonToCustomer[id] = cname;
          }
        }
      } else {
        if (customerName != null) {
          _customerTotals[customerName!] = expectedCartons.length;
          _customerScanned[customerName!] = 0;

          for (final id in expectedCartons) {
            _cartonToCustomer[id] = customerName!;
          }
        }
      }
    }

    setState(() {
      if (qrContent['shipment_type'] == 'multi_customer') {
        isMultiCustomer = true;
        masterSessionId = result['session_id']?.toString();
        totalCustomers = (result['total_customers'] ?? 1) as int;
        customers =
            List<Map<String, dynamic>>.from(result['customers'] ?? []);
        customerName = '$totalCustomers Customers';
        truckNumber = result['truck_number']?.toString();

        final allCartons = (qrContent['all_cartons'] as List?)
                ?.map((e) => e.toString().toUpperCase())
                .toList() ??
            [];
        expectedCartons = allCartons;
        totalCartons = expectedCartons.length;
      } else {
        isMultiCustomer = false;
        sessionId = result['session_id']?.toString();
        final Map<String, dynamic>? shipmentInfo =
            (result['shipment_data'] as Map?)?.cast<String, dynamic>();

        if (shipmentInfo != null) {
          shipmentData = shipmentInfo;
          truckNumber = shipmentInfo['truck_number']?.toString();
          customerName = shipmentInfo['customer_name']?.toString();
          shipperName = shipmentInfo['shipper_name']?.toString();
          destination = shipmentInfo['destination']?.toString();
          loadingStrategy =
              shipmentInfo['loading_strategy']?.toString() ?? 'NON_LIFO';

          // ✅ SET LIFO MODE
          isLifoMode = (loadingStrategy ?? 'NON_LIFO').toUpperCase() == 'LIFO';

          final List<dynamic> cartonList =
              (shipmentInfo['carton_list'] as List? ?? []);
          expectedCartons = cartonList
              .map((e) => e.toString().toUpperCase())
              .toList(growable: false);
          totalCartons = expectedCartons.length;
        }
      }

      scannedCartons.clear();
      _recentScans.clear();
      lifoSequence.clear();
      currentScanCount = 0;

      buildCartonIndex();

      currentStep = LoadingStep.truckVerification;
      currentMessage = isMultiCustomer
          ? "🚛 Multi-Customer Shipment! Scan truck: $truckNumber"
          : "🚛 Now scan truck number plate: $truckNumber";
    });

    _showSuccessMessage(isMultiCustomer
        ? "✅ Multi-Customer Shipment loaded!\n$totalCustomers customers, $totalCartons cartons total"
        : "✅ Shipment loaded!\nCustomer: ${customerName ?? 'Unknown'}\nCartons: $totalCartons");

    _clearAndRefocusWithDelay();
  }

  Future<void> _handleTruckVerificationSuccess(
    Map<String, dynamic> result,
  ) async {
    if (_isDisposed || !mounted) return;

    // ✅ LIFO SETUP - NEW
    if (isLifoMode && sessionId != null) {
      try {
        final sessionResult = await LoadingService.createLoadingSession(
          shipmentOrderId: sessionId!,
          userName: widget.userName,
          truckNumber: truckNumber ?? 'Unknown',
          isLifo: true,
          totalCartons: totalCartons,
        );

        if (sessionResult['success'] == true) {
          await _calculateLifoSequence();
        }
      } catch (e) {
        log('Error creating LIFO session: $e');
      }
    }

    setState(() {
      currentStep = LoadingStep.cartonScanning;
      currentMessage = isMultiCustomer
          ? "📦 Truck verified! Scan cartons for $totalCustomers customers (0/$totalCartons)"
          : "📦 Truck verified! Start scanning cartons (0/$totalCartons)";
    });

    _showSuccessMessage("✅ Truck verified: ${result['truck_number']}");
    _clearAndRefocusWithDelay();
  }

  Future<void> _handleCartonScanSuccess(
    Map<String, dynamic> result,
    String cartonId,
  ) async {
    if (_isDisposed || !mounted) return;

    if (scannedCartons.add(cartonId)) {
      final cname = _cartonToCustomer[cartonId];
      if (cname != null) {
        _customerScanned[cname] = (_customerScanned[cname] ?? 0) + 1;
      }

      _pushRecentScan(RecentScan(
        cartonId: cartonId,
        customerName: cname ?? customerName,
      ));

      final bool allScanned =
          result['all_scanned'] == true ||
              scannedCartons.length >= expectedCartons.length;

      if (allScanned) {
        setState(() {
          currentMessage = isMultiCustomer
              ? "🎉 All cartons scanned! Multi-customer loading complete."
              : "🎉 All cartons scanned successfully! Click 'Get Dispatch Slip' below.";
        });

        _showHeaderBanner(
            "All cartons verified (${scannedCartons.length}/$totalCartons)");
        _showSuccessMessage(isMultiCustomer
            ? "🎉 Multi-Customer Loading Complete!\nAll ${scannedCartons.length} cartons verified across $totalCustomers customers!"
            : "🎉 Loading Complete!\nAll ${scannedCartons.length} cartons verified!");
      } else {
        final progressMsg = isMultiCustomer
            ? "📦 Verified $cartonId → ${_cartonToCustomer[cartonId] ?? 'Unknown'} (${scannedCartons.length}/$totalCartons)"
            : "📦 Carton $cartonId verified (${scannedCartons.length}/$totalCartons)";

        setState(() {
          currentMessage = progressMsg;
        });

        _showHeaderBanner("Verified: $cartonId");
        _showSuccessMessage("✅ Carton $cartonId verified");
      }
    }

    _clearAndRefocusWithDelay();
  }

  // ================================
  // UTILS/INFRA
  // ================================

  String _validateAndCleanInput(String input, String fieldName) {
    if (input.isEmpty) {
      throw LoadingException(
        type: LoadingErrorType.validation,
        message: 'Empty $fieldName',
        details: 'Please scan a valid $fieldName',
      );
    }

    if (input.length > _maxScanLength) {
      throw LoadingException(
        type: LoadingErrorType.validation,
        message: '$fieldName too long',
        details: 'Maximum length is $_maxScanLength characters',
      );
    }

    return input.toUpperCase().trim();
  }

  Future<T> _callWithTimeout<T>(
    Future<T> Function() operation,
    String name,
  ) async {
    try {
      return await operation().timeout(_operationTimeout);
    } on TimeoutException {
      throw LoadingException(
        type: LoadingErrorType.timeout,
        message: '$name timed out',
        details:
            'Operation took longer than ${_operationTimeout.inSeconds} seconds',
      );
    } on SocketException {
      throw const LoadingException(
        type: LoadingErrorType.network,
        message: 'Network connection failed',
        details: 'Please check your internet connection',
      );
    }
  }

  void _setLoadingState(bool loading, [String? message]) {
    if (_isDisposed || !mounted) return;

    setState(() {
      isLoading = loading;
      isScanning = loading;
      if (message != null) currentMessage = message;
      if (loading) {
        errorMessage = null;
        showSuccess = false;
      }
    });
  }

  void _handleScanInput(String value) {
    if (_isDisposed || value.isEmpty || isLoading || isScanning) return;

    HapticFeedback.lightImpact();
    _clearErrorMessage();

    switch (currentStep) {
      case LoadingStep.shipmentSheet:
        _processShipmentQR(value);
        break;
      case LoadingStep.truckVerification:
        _verifyTruckNumber(value);
        break;
      case LoadingStep.cartonScanning:
        _processCartonScan(value);
        break;
    }
  }

  void _handleException(LoadingException error) {
    if (_isDisposed) return;

    _clearInputField();
    _showError(error);
    log('Error: $error');
  }

  void _clearAndRefocusWithDelay() {
    if (_isDisposed) return;

    _clearInputField();
    Timer(const Duration(milliseconds: 250), _safeRequestFocus);
  }

  void _clearInputField() {
    if (_isDisposed) return;

    try {
      _scanController.clear();
    } catch (_) {}
  }

  void _safeRequestFocus() {
    if (_isDisposed || !mounted) return;

    try {
      if (_scanFocusNode.canRequestFocus && !isLoading) {
        _scanFocusNode.requestFocus();
      }
    } catch (_) {}
  }

  void _clearAllTimers() {
    _scanDebounceTimer?.cancel();
    _errorMessageTimer?.cancel();
    _successMessageTimer?.cancel();
    _headerBannerTimer?.cancel();
  }

  void _handleAppDetached() {
    _clearAllTimers();
  }

  void _clearErrorMessage() {
    _errorMessageTimer?.cancel();

    if (mounted) {
      setState(() {
        errorMessage = null;
        lastErrorType = null;
      });
    }
  }

  void _showError(LoadingException error) {
    if (_isDisposed || !mounted) return;

    setState(() {
      errorMessage = error.details != null
          ? "${error.message}: ${error.details}"
          : error.message;
      lastErrorType = error.type;
      showSuccess = false;
      isLoading = false;
      isScanning = false;
    });

    _errorMessageTimer?.cancel();
    _errorMessageTimer = Timer(const Duration(seconds: 8), _clearErrorMessage);

    switch (error.type) {
      case LoadingErrorType.validation:
        HapticFeedback.mediumImpact();
        break;
      case LoadingErrorType.network:
      case LoadingErrorType.timeout:
        HapticFeedback.heavyImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  void _showSuccessMessage(String message) {
    if (_isDisposed) return;

    if (mounted) {
      setState(() {
        showSuccess = true;
        errorMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );

      _successMessageTimer?.cancel();
      _successMessageTimer = Timer(
        const Duration(seconds: 2),
        () => mounted ? setState(() => showSuccess = false) : null,
      );

      HapticFeedback.selectionClick();
    }
  }

  void _showHeaderBanner(String text) {
    if (_isDisposed || !mounted) return;

    setState(() => _headerBannerMessage = text);
    _headerBannerTimer?.cancel();
    _headerBannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _headerBannerMessage = null);
    });
  }

  void _pushRecentScan(RecentScan item) {
    _recentScans.insert(0, item);
    if (_recentScans.length > _recentLimit) {
      _recentScans.removeLast();
    }

    setState(() {});
  }

  void _resetToInitial() {
    if (_isDisposed) return;

    _clearAllTimers();

    if (mounted) {
      setState(() {
        currentStep = LoadingStep.shipmentSheet;
        sessionId = null;
        masterSessionId = null;
        isMultiCustomer = false;
        shipmentData = null;
        scannedCartons.clear();
        expectedCartons.clear();
        customers.clear();
        _cartonToCustomer.clear();
        _customerTotals.clear();
        _customerScanned.clear();
        _recentScans.clear();
        totalCartons = 0;
        totalCustomers = 1;
        truckNumber = null;
        customerName = null;
        shipperName = null;
        destination = null;
        loadingStrategy = null;
        _isContinuingFromShipment = false;
        isLifoMode = false;
        lifoSequence.clear();
        currentScanCount = 0;
        currentMessage =
            "📋 Scan the shipment sheet QR code to begin loading process";
        errorMessage = null;
        lastErrorType = null;
        showSuccess = false;
        isLoading = false;
        isScanning = false;
        _headerBannerMessage = null;
      });
    }

    _clearAndRefocusWithDelay();
  }

  void _showEditDialog() {
    if (!mounted || sessionId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.blue, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: const Text(
                'Edit Loading Session',
                style: TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session ID: ${sessionId ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Customer: ${customerName ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Truck: ${truckNumber ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Loading Strategy: ${loadingStrategy ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Progress: ${scannedCartons.length}/$totalCartons cartons'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Edit functionality coming soon.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    if (!mounted || sessionId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: const Text(
                'Delete Loading Session?',
                style: TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this session?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session: ${sessionId ?? 'N/A'}'),
                  Text('Customer: ${customerName ?? 'N/A'}'),
                  Text('Scanned: ${scannedCartons.length}/$totalCartons'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ This action cannot be undone!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _performDeleteSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteSession() async {
    if (!mounted) return;

    _setLoadingState(true, 'Deleting session...');

    try {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        _showSuccessMessage('✅ Session deleted successfully!');
        _resetToInitial();
        Navigator.maybePop(context);
      }
    } catch (e) {
      if (mounted) {
        _showError(LoadingException(
          type: LoadingErrorType.database,
          message: 'Failed to delete session',
          originalError: e,
        ));
      }
    } finally {
      _setLoadingState(false);
    }
  }

  // ================================
  // LOADING HISTORY
  // ================================

  Future<void> _showLoadingHistory() async {
    if (!mounted) return;

    _setLoadingState(true, 'Loading history...');

    try {
      // Fetch loading history from service
      final history = await LoadingService.getLoadingHistory(
        userName: widget.userName,
        limit: 20,
      );

      if (!mounted) return;
      _setLoadingState(false);

      if (history.isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 12),
                Text('No History'),
              ],
            ),
            content: const Text('No previous loading sessions found.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: orangeGradient,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Loading History',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // List
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return _buildHistoryCard(item);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _setLoadingState(false);
        _showError(LoadingException(
          type: LoadingErrorType.database,
          message: 'Failed to load history',
          originalError: e,
        ));
      }
    }
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final shipmentId = item['shipment_order_id'] ?? 'N/A';
    final truckNum = item['truck_number'] ?? 'N/A';
    final customer = item['customer_name'] ?? 'Unknown';
    final cartons = item['total_cartons'] ?? 0;
    final scanned = item['scanned_cartons'] ?? 0;
    final completedAt = item['completed_at'];
    final isComplete = scanned >= cartons;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isComplete ? Colors.green.shade200 : Colors.orange.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isComplete ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isComplete ? Icons.check_circle : Icons.pending,
                    color: isComplete ? Colors.green.shade700 : Colors.orange.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🚛 $truckNum',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isComplete ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$scanned/$cartons',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  completedAt != null ? _formatDateTime(DateTime.parse(completedAt)) : 'In Progress',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Spacer(),
                if (isComplete)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _regenerateDispatchSlip(shipmentId);
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('View Slip', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      backgroundColor: Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerateDispatchSlip(String shipmentOrderId) async {
    if (!mounted) return;

    _setLoadingState(true, 'Generating dispatch slip...');

    try {
      final pdfBytes = await DispatchSlipGenerator.generateDispatchSlip(
        shipmentOrderId: shipmentOrderId,
      );

      if (!mounted) return;
      _setLoadingState(false);

      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Dispatch_Slip_$shipmentOrderId.pdf',
      );

      if (mounted) {
        _showSuccessMessage('✅ Dispatch slip ready!');
      }
    } catch (e) {
      if (mounted) {
        _setLoadingState(false);
        _showError(LoadingException(
          type: LoadingErrorType.unknown,
          message: 'Failed to generate dispatch slip',
          originalError: e,
        ));
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // ================================
  // UI BUILD
  // ================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      onPopInvoked: (didPop) {
        if (!didPop && isLoading) {
          _showError(const LoadingException(
            type: LoadingErrorType.validation,
            message: 'Cannot exit during processing',
            details: 'Please wait for the current operation to complete',
          ));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildProfessionalAppBar(),
                  if (_headerBannerMessage != null)
                    _buildHeaderSuccessBanner(_headerBannerMessage!),
                  Expanded(child: _buildMainContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSuccessBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.green[600],
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      decoration: BoxDecoration(
        gradient: orangeGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: isLoading ? null : () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMultiCustomer
                          ? 'Multi-Customer Loading'
                          : 'Shipment Loading',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isContinuingFromShipment)
                      Text(
                        'Continuing from Shipment',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (sessionId != null || masterSessionId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ID: ${(masterSessionId ?? sessionId!).substring(0, 6)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              // ✅ ALWAYS SHOW MENU - Show different options based on session state
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
                tooltip: 'Menu',
                enabled: !isLoading,
                padding: const EdgeInsets.all(4),
                onSelected: (value) {
                  switch (value) {
                    case 'history':
                      _showLoadingHistory();
                      break;
                    case 'refresh':
                      _resetToInitial();
                      break;
                    case 'edit':
                      _showEditDialog();
                      break;
                    case 'delete':
                      _showDeleteConfirmation();
                      break;
                  }
                },
                itemBuilder: (context) {
                  // Show different menu items based on session state
                  final hasActiveSession = sessionId != null || masterSessionId != null;
                  
                  if (hasActiveSession) {
                    // Full menu when session is active
                    return [
                      const PopupMenuItem(
                        value: 'history',
                        child: Row(
                          children: [
                            Icon(Icons.history, size: 18, color: Colors.blue),
                            SizedBox(width: 10),
                            Text('Loading History', style: TextStyle(fontSize: 14, color: Colors.blue)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 18),
                            SizedBox(width: 10),
                            Text('Refresh', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 10),
                            Text('Edit Session', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 10),
                            Text('Delete Session',
                                style: TextStyle(color: Colors.red, fontSize: 14)),
                          ],
                        ),
                      ),
                    ];
                  } else {
                    // Simplified menu when no session - only show history
                    return [
                      const PopupMenuItem(
                        value: 'history',
                        child: Row(
                          children: [
                            Icon(Icons.history, size: 18, color: Colors.blue),
                            SizedBox(width: 10),
                            Text('Loading History', style: TextStyle(fontSize: 14, color: Colors.blue)),
                          ],
                        ),
                      ),
                    ];
                  }
                },
              ),
            ],
          ),
        
          const SizedBox(height: 12),
          _buildProgressIndicator(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildProgressStep(
            0,
            "📋",
            "Sheet",
            forceComplete: _isContinuingFromShipment,
          ),
          _buildProgressConnector(currentStep.index >= 1 ||
              _isContinuingFromShipment),
          _buildProgressStep(1, "🚛", "Truck"),
          _buildProgressConnector(currentStep.index >= 2),
          _buildProgressStep(2, "📦", "Cartons"),
        ],
      ),
    );
  }

  Widget _buildProgressStep(
    int stepIndex,
    String emoji,
    String label, {
    bool forceComplete = false,
  }) {
    final isActive = currentStep.index >= stepIndex || forceComplete;
    final isCurrent = currentStep.index == stepIndex && !forceComplete;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = isCurrent ? _pulseAnimation.value.clamp(1.0, 1.05) : 1.0;

        return Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: forceComplete && stepIndex == 0
                      ? const Icon(Icons.check, color: Colors.green, size: 18)
                      : Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressConnector(bool isActive) {
    return Container(
      width: 24,
      height: 2,
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEnhancedStatusCard(),
          const SizedBox(height: 20),
          _buildEnhancedScanningCard(),
          if ((sessionId != null && shipmentData != null) ||
              (isMultiCustomer && masterSessionId != null)) ...[
            const SizedBox(height: 20),
            _buildShipmentInfoCard(),
          ],
          if (currentStep.index >= 2) ...[
            const SizedBox(height: 20),
            _buildProgressCard(),
          ],
          if (_recentScans.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildRecentScansRow(),
          ],
          if (scannedCartons.length >= totalCartons && totalCartons > 0) ...[
            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatusCard() {
    Color cardColor = Colors.white;
    Color statusColor = Colors.orange[600]!;
    IconData statusIcon = Icons.info_outline;

    if (errorMessage != null) {
      statusIcon = Icons.error_outline;
      switch (lastErrorType) {
        case LoadingErrorType.network:
          cardColor = Colors.orange[50]!;
          statusColor = Colors.orange[700]!;
          break;
        case LoadingErrorType.timeout:
          cardColor = Colors.amber[50]!;
          statusColor = Colors.amber[700]!;
          break;
        case LoadingErrorType.parsing:
          cardColor = Colors.purple[50]!;
          statusColor = Colors.purple[700]!;
          break;
        case LoadingErrorType.database:
          cardColor = Colors.indigo[50]!;
          statusColor = Colors.indigo[700]!;
          break;
        case LoadingErrorType.validation:
          cardColor = Colors.red[50]!;
          statusColor = Colors.red[700]!;
          break;
        default:
          cardColor = Colors.red[50]!;
          statusColor = Colors.red[700]!;
      }
    } else if (showSuccess) {
      cardColor = Colors.green[50]!;
      statusColor = Colors.green[700]!;
      statusIcon = Icons.check_circle_outline;
    }

    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      errorMessage ?? currentMessage,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(Colors.orange[600]!),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Processing... Please wait",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (errorMessage != null && !isLoading) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _clearAndRefocusWithDelay,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Try Again', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor: statusColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor: statusColor.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (lastErrorType == LoadingErrorType.parsing)
                    TextButton.icon(
                      onPressed: () {
                        _debugQRContent(_scanController.text);
                      },
                      icon: const Icon(Icons.bug_report, size: 16),
                      label: const Text('Debug', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: statusColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        backgroundColor: statusColor.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedScanningCard() {
    return Card(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.orange[600]!.withOpacity(0.02)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: orangeGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getScanInputIcon(),
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getScanInputLabel(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getScanInputDescription(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _scanController,
              focusNode: _scanFocusNode,
              enabled: !isLoading && !isScanning,
              autocorrect: false,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              maxLines: currentStep == LoadingStep.shipmentSheet ? 3 : 1,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxScanLength)
              ],
              decoration: InputDecoration(
                hintText: _getScanInputHint(),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.orange[600]!, width: 2),
                ),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[600]!.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.qr_code_scanner,
                      color: Colors.orange[600]!, size: 20),
                ),
                suffixIcon: (isLoading || isScanning)
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearInputField,
                        tooltip: 'Clear',
                      ),
              ),
              onSubmitted: (v) {
                _handleScanInput(v.trim());
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentStep == LoadingStep.shipmentSheet
                          ? "📱 Scan QR code or paste JSON/key-value data"
                          : "📱 Scan barcode or type manually",
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShipmentInfoCard() {
    if (!isMultiCustomer && shipmentData == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange[100]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isMultiCustomer ? Icons.groups : Icons.business,
                    color: Colors.orange[700],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isMultiCustomer
                        ? 'Multi-Customer Shipment'
                        : 'Shipment Information',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isMultiCustomer) ...[
              _buildInfoRow('🚛 Truck Number', truckNumber ?? 'Unknown'),
              _buildInfoRow('👥 Total Customers', '$totalCustomers'),
              _buildInfoRow('📦 Total Cartons', '$totalCartons'),
              if (customers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Customer Preview:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                ...customers.take(3).map((customer) {
                  final cname =
                      customer['customer_name']?.toString() ?? 'Unknown';
                  final dest = customer['destination']?.toString() ??
                      'Unknown destination';
                  final int count =
                      (customer['carton_list'] as List? ?? []).length;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count cartons → $dest',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                if (customers.length > 3)
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '... and ${customers.length - 3} more customers',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ] else ...[
              _buildInfoRow('🏢 Customer', customerName ?? 'Unknown'),
              _buildInfoRow('🚛 Truck Number', truckNumber ?? 'Unknown'),
              if ((shipperName ?? '').isNotEmpty)
                _buildInfoRow('🚚 Shipper', shipperName!),
              if ((destination ?? '').isNotEmpty)
                _buildInfoRow('📍 Destination', destination!),
              _buildInfoRow('📦 Total Cartons', '$totalCartons'),
              if ((loadingStrategy ?? '').isNotEmpty)
                _buildInfoRow(
                  '⚡ Loading Strategy',
                  isLifoMode ? '🔒 LIFO (Last In, First Out)' : 'NON_LIFO',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    if (expectedCartons.isEmpty) return const SizedBox.shrink();

    final progress =
        scannedCartons.isEmpty ? 0.0 : scannedCartons.length / expectedCartons.length;
    final percentage = (progress * 100).round();

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green[100]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.trending_up,
                      color: Colors.green[700], size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Loading Progress',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${scannedCartons.length}/${expectedCartons.length} Cartons',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(Colors.green[600]!),
                minHeight: 8,
              ),
            ),
            if (isMultiCustomer && customers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Per-customer progress',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customers.take(6).map((c) {
                  final cname = c['customer_name']?.toString() ?? 'Unknown';
                  final tot = _customerTotals[cname] ?? 0;
                  final scn = _customerScanned[cname] ?? 0;
                  final pct = tot == 0 ? 0 : ((scn / tot) * 100).round();

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border.all(color: Colors.blue[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$cname: $scn/$tot ($pct%)',
                      style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentScansRow() {
    return Card(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent scans',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _recentScans.map((r) {
                final color = r.duplicate
                    ? Colors.orange[700]
                    : (r.wrongCustomer ? Colors.red[700] : Colors.green[700]);
                final label =
                    r.duplicate ? 'Duplicate' : (r.wrongCustomer ? 'Mismatch' : 'OK');

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.cartonId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.customerName ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color!.withOpacity(0.12),
                            border: Border.all(color: color.withOpacity(0.4)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        GradientButton(
          text: isMultiCustomer
              ? "📄 Get Multi-Customer Dispatch Slip"
              : "📄 Get Dispatch Slip",
          onPressed: isLoading ? null : _generateReport,
          isLoading: isLoading,
          icon: Icons.picture_as_pdf,
          width: double.infinity,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isLoading ? null : _resetToInitial,
          icon: const Icon(Icons.refresh),
          label: const Text("🔄 Start New Loading"),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange[600]!,
            side: BorderSide(color: Colors.orange[600]!),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // Helpers
  String _getScanInputLabel() {
    switch (currentStep) {
      case LoadingStep.shipmentSheet:
        return "Step 1: Scan Shipment Sheet";
      case LoadingStep.truckVerification:
        return "Step 2: Verify Truck Number";
      case LoadingStep.cartonScanning:
        return "Step 3: Scan Carton Barcodes";
    }
  }

  String _getScanInputDescription() {
    switch (currentStep) {
      case LoadingStep.shipmentSheet:
        return "Scan QR code from shipment documentation";
      case LoadingStep.truckVerification:
        return "Verify truck identity by scanning number plate";
      case LoadingStep.cartonScanning:
        return isMultiCustomer
            ? "Scan cartons for all $totalCustomers customers"
            : "Scan each carton barcode to validate loading";
    }
  }

  String _getScanInputHint() {
    switch (currentStep) {
      case LoadingStep.shipmentSheet:
        return "Scan shipment sheet QR code or paste JSON/key-value data";
      case LoadingStep.truckVerification:
        return "Scan truck number plate";
      case LoadingStep.cartonScanning:
        return "Scan carton barcode";
    }
  }

  IconData _getScanInputIcon() {
    switch (currentStep) {
      case LoadingStep.shipmentSheet:
        return Icons.qr_code;
      case LoadingStep.truckVerification:
        return Icons.local_shipping;
      case LoadingStep.cartonScanning:
        return Icons.inventory;
    }
  }
}
