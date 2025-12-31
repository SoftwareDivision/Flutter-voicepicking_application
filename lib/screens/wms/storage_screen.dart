// lib/screens/wms/storage_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import '../../services/warehouse_service.dart';
import '../../utils/colors.dart';

class StorageScreen extends StatefulWidget {
  final String userName;

  const StorageScreen({super.key, required this.userName});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen>
    with TickerProviderStateMixin {
  // Core State Variables
  List<Map<String, dynamic>> _storedItems = [];
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isDeleting = false;
  String _currentStep = 'location';

  // Current Session Data
  String? _scannedLocation;
  String? _scannedBarcode;

  // Controllers
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();

  // Focus nodes for auto-focus
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _barcodeFocusNode = FocusNode();

  // TTS for Voice Feedback
  FlutterTts? _flutterTts;

  // Animation Controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ✅ ENHANCED ERROR HANDLING VARIABLES
  Timer? _processingTimer;
  Timer? _debounceTimer;
  bool _isProcessingScan = false;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  static const int _maxDataLength = 10000; // Prevent memory issues
  static const int _processingTimeout = 15; // seconds
  String? _lastProcessedData;

  // ✅ NEW: UNDO FUNCTIONALITY VARIABLES
  Timer? _undoTimer;
  Map<String, dynamic>? _lastDeletedItem;
  int? _lastDeletedIndex;
  Map<String, dynamic>? _lastAddedItem;
  static const int _undoTimeoutSeconds = 10;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeTTS();
    _loadData();
    _setupControllerListeners();

    // Auto-focus location field when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _debounceTimer?.cancel();
    _undoTimer?.cancel(); // ✅ NEW: Cancel undo timer
    _fadeController.dispose();
    _pulseController.dispose();
    _locationController.dispose();
    _barcodeController.dispose();
    _locationFocusNode.dispose();
    _barcodeFocusNode.dispose();
    _flutterTts?.stop();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
  }

  Future<void> _initializeTTS() async {
    try {
      _flutterTts = FlutterTts();
      await _flutterTts?.setLanguage('en-US');
      await _flutterTts?.setSpeechRate(0.8);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
    } catch (e) {
      debugPrint('❌ TTS initialization failed: $e');
    }
  }

  Future<void> _speakMessage(String message) async {
    try {
      if (_flutterTts == null) return;
      await _flutterTts?.stop();
      await _flutterTts?.speak(message.length > 100 ? message.substring(0, 100) : message);
    } catch (e) {
      debugPrint('❌ TTS speak failed: $e');
    }
  }

  // ✅ ENHANCED CONTROLLER LISTENERS WITH ERROR HANDLING
  void _setupControllerListeners() {
    _locationController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _onLocationChanged();
      });
    });

    _barcodeController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _onBarcodeChanged();
      });
    });
  }

  void _onLocationChanged() {
    if (_isProcessingScan || _isLoading) return;
    final locationCode = _locationController.text.trim();

    // ✅ VALIDATION: Check for valid location format
    if (locationCode.length >= 6 &&
        locationCode.contains('-') &&
        _currentStep == 'location' &&
        _isValidLocationFormat(locationCode)) {
      _handleLocationScan(locationCode);
    }
  }

  void _onBarcodeChanged() {
    if (_isProcessingScan || _isLoading) return;
    final barcode = _barcodeController.text.trim();

    // ✅ VALIDATION: Check for reasonable barcode length and format
    if (barcode.length >= 8 &&
        barcode.length <= _maxDataLength &&
        _currentStep == 'item' &&
        _isValidBarcodeFormat(barcode)) {
      _handleItemScan(barcode);
    }
  }

  // ✅ VALIDATION HELPERS
  bool _isValidLocationFormat(String locationCode) {
    try {
      // Check if it matches basic location pattern (A-01-01, B-02-03, etc.)
      final pattern = RegExp(r'^[A-Z]-\d{2}-\d{2}$');
      return pattern.hasMatch(locationCode.toUpperCase());
    } catch (e) {
      debugPrint('❌ Location format validation error: $e');
      return false;
    }
  }

  bool _isValidBarcodeFormat(String barcode) {
    try {
      // Check for reasonable barcode characteristics
      if (barcode.length > _maxDataLength) return false;
      if (barcode.trim().isEmpty) return false;

      // Check if it's not just repeated characters (like "aaaaaaaaaa")
      final uniqueChars = barcode.split('').toSet();
      if (uniqueChars.length < 3 && barcode.length > 10) return false;

      return true;
    } catch (e) {
      debugPrint('❌ Barcode format validation error: $e');
      return false;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final storedItems = await WarehouseService.getStoredItems();
      if (mounted) {
        setState(() {
          _storedItems = storedItems;
          _isLoading = false;
          _consecutiveErrors = 0; // Reset error count on successful load
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _handleError('Failed to load data', e, isRecoverable: true);
      }
    }
  }

  // ✅ ENHANCED LOCATION SCAN WITH TIMEOUT AND ERROR HANDLING
  Future<void> _handleLocationScan(String locationCode) async {
    if (_isProcessingScan) {
      debugPrint('⚠️ Already processing scan, ignoring duplicate');
      return;
    }

    if (locationCode.isEmpty || locationCode.length > 50) {
      _handleError('Invalid location code format', 'Location code too long or empty', isRecoverable: true);
      return;
    }

    // Prevent duplicate processing
    if (_lastProcessedData == locationCode) {
      debugPrint('⚠️ Duplicate location scan detected, ignoring');
      return;
    }

    _lastProcessedData = locationCode;
    _isProcessingScan = true;
    setState(() => _isLoading = true);

    // ✅ SET PROCESSING TIMEOUT
    _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
      if (_isProcessingScan) {
        debugPrint('⏰ Location validation timeout');
        _handleError('Location validation timeout', 'Operation took too long', isRecoverable: true);
        _resetProcessingState();
      }
    });

    try {
      final result = await WarehouseService.validateLocation(locationCode);
      _processingTimer?.cancel();

      if (mounted && _isProcessingScan) {
        setState(() {
          _isLoading = false;
          _scannedLocation = locationCode.toUpperCase();
        });

        if (result['exists']) {
          _showMessage('Location validated ✓', isSuccess: true);
          await _speakMessage('Location confirmed. Scan item now.');
          _moveToItemScanning();
          _consecutiveErrors = 0; // Reset error count
        } else {
          await _speakMessage('Location not found');
          _showAddLocationDialog(locationCode);
        }
      }
    } catch (e) {
      _processingTimer?.cancel();
      if (mounted) {
        _handleError('Location validation failed', e, isRecoverable: true);
      }
    } finally {
      _resetProcessingState();
    }
  }

  // ✅✅✅ CRITICAL FIX: USE WAREHOUSE SERVICE PARSER DIRECTLY ✅✅✅
  // ❌ REMOVED: Local _parseProductDetails() function
  // ✅ NOW USING: WarehouseService.parseProductDetailsFromBarcode()

  // ✅ ENHANCED ITEM SCAN WITH COMPREHENSIVE ERROR HANDLING
  Future<void> _handleItemScan(String barcode) async {
    if (_isProcessingScan) {
      debugPrint('⚠️ Already processing scan, ignoring duplicate');
      return;
    }

    if (barcode.isEmpty) {
      _handleError('Empty barcode', 'Please scan an item barcode', isRecoverable: true);
      return;
    }

    if (barcode.length > _maxDataLength) {
      _handleError('Barcode data too large', 'Scanned data is too large to process', isRecoverable: true);
      return;
    }

    // Prevent duplicate processing
    if (_lastProcessedData == barcode) {
      debugPrint('⚠️ Duplicate barcode scan detected, ignoring');
      return;
    }

    _lastProcessedData = barcode;
    _isProcessingScan = true;
    setState(() => _isLoading = true);

    // ✅ SET PROCESSING TIMEOUT
    _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
      if (_isProcessingScan) {
        debugPrint('⏰ Item processing timeout');
        _handleError('Item processing timeout', 'Operation took too long', isRecoverable: true);
        _resetProcessingState();
      }
    });

    try {
      debugPrint('🔄 Processing item scan: ${barcode.length} characters');

      // ✅✅✅ CRITICAL FIX: Use WarehouseService Universal Parser directly
      final productDetails = WarehouseService.parseProductDetailsFromBarcode(barcode);
      
      debugPrint('✅ Parsed product details successfully');

      // ✅ Send ORIGINAL barcode to warehouse service (it will parse it there too)
      final result = await WarehouseService.storeItemInLocation(
        locationCode: _scannedLocation!,
        barcode: barcode, // ✅ Send original barcode, not pre-parsed
        quantity: productDetails['quantity'] as int,
        scannedBy: widget.userName,
        description: productDetails['description'] as String,
        category: productDetails['category'] as String,
        unitPrice: productDetails['unitprice'] as double,
        itemName: productDetails['name'] as String,
        sku: productDetails['sku'] as String,
        finalSku: productDetails['sku'] as String,
        brand: productDetails['brand'] as String?,
      );

      _processingTimer?.cancel();

      if (mounted && _isProcessingScan) {
        setState(() => _isLoading = false);

        if (result['success']) {
          final itemName = productDetails['name'] as String;
          final syncMsg = result['synced_to_inventory'] ? ' and synced to inventory' : '';
          
          // ✅ NEW: Show undo snackbar for additions
          _showUndoSnackbar(
            message: '$itemName stored successfully$syncMsg',
            onUndo: () {
              // Undo will be implemented if needed
              _showMessage('Undo not yet implemented for additions', isError: true);
            },
          );
          
          await _speakMessage('Item stored successfully. Ready for next scan.');

          _resetForNextCycle();
          await _loadData();
          _consecutiveErrors = 0; // Reset error count
        } else {
          // ✅ NEW: Enhanced error handling for validation failures
          final errorMessage = result['message'] ?? 'Unknown storage error';
          final voiceMessage = result['voice_message'] ?? 'Storage failed';
          
          // Check if it's a validation error (wrong item or duplicate location)
          if (result.containsKey('location_contents') || result.containsKey('existing_location')) {
            // Show detailed error dialog instead of simple message
            _showValidationErrorDialog(result);
            await _speakMessage(voiceMessage);
            _resetProcessingState();
          } else {
            _handleError('Storage failed', errorMessage, isRecoverable: true);
          }
        }
      }
    } catch (e) {
      _processingTimer?.cancel();
      if (mounted) {
        _handleError('Item scan processing failed', e, isRecoverable: true);
      }
    } finally {
      _resetProcessingState();
    }
  }

  // ✅ CENTRALIZED ERROR HANDLING
  void _handleError(String title, dynamic error, {bool isRecoverable = false}) {
    _consecutiveErrors++;
    String errorMessage = error.toString();
    if (errorMessage.length > 200) {
      errorMessage = '${errorMessage.substring(0, 200)}...';
    }

    debugPrint('❌ Error ($title): $errorMessage');
    setState(() => _isLoading = false);

    // Show user-friendly error message
    _showMessage('$title: $errorMessage', isError: true);
    _speakMessage('Error occurred. Please try again.');

    // ✅ AUTOMATIC RECOVERY LOGIC
    if (isRecoverable) {
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _showErrorRecoveryDialog();
      } else {
        // Auto-reset after a few seconds
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _resetForNextCycle();
          }
        });
      }
    }

    _resetProcessingState();
  }

  void _resetProcessingState() {
    _isProcessingScan = false;
    _processingTimer?.cancel();
    _lastProcessedData = null;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // ✅ ERROR RECOVERY DIALOG
  void _showErrorRecoveryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Multiple Errors Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Multiple scanning errors detected. This may be due to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Damaged or unreadable barcodes\n'
                    '• Incorrect data format\n'
                    '• Scanner hardware issues\n'
                    '• Network connectivity problems',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForNextCycle();
              _consecutiveErrors = 0;
            },
            child: const Text('Reset & Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _consecutiveErrors = 0;
              _loadData(); // Refresh data
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPink,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restart Scanner'),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Show detailed validation error dialog
  void _showValidationErrorDialog(Map<String, dynamic> result) {
    final message = result['message'] as String;
    final locationContents = result['location_contents'] as Map<String, dynamic>?;
    final existingLocation = result['existing_location'] as String?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Cannot Store Item'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (locationContents != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Current Location Contents:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Item: ${locationContents['name']}',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'SKU: ${locationContents['sku']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Qty: ${locationContents['quantity']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (existingLocation != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, color: Colors.orange, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Product is in: $existingLocation',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForNextCycle();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAddLocationDialog(String locationCode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.add_location, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Location Not Found',
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.location_off, color: Colors.orange, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Location "$locationCode" not found in database.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Would you like to add this location?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForNextCycle(); // Reset on cancel
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => _addLocationToDatabase(locationCode),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Location'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addLocationToDatabase(String locationCode) async {
    Navigator.pop(context);

    if (_isProcessingScan) return;

    _isProcessingScan = true;
    setState(() => _isLoading = true);

    _processingTimer = Timer(Duration(seconds: _processingTimeout), () {
      if (_isProcessingScan) {
        _handleError('Location creation timeout', 'Operation took too long', isRecoverable: true);
        _resetProcessingState();
      }
    });

    try {
      final result = await WarehouseService.addLocation(locationCode);
      _processingTimer?.cancel();

      if (mounted && _isProcessingScan) {
        setState(() => _isLoading = false);

        if (result['success']) {
          setState(() => _scannedLocation = locationCode.toUpperCase());
          _showMessage('Location added successfully ✓', isSuccess: true);
          await _speakMessage('Location added. Scan item now.');
          _moveToItemScanning();
        } else {
          _handleError('Failed to add location', result['message'], isRecoverable: true);
        }
      }
    } catch (e) {
      _processingTimer?.cancel();
      if (mounted) {
        _handleError('Location creation failed', e, isRecoverable: true);
      }
    } finally {
      _resetProcessingState();
    }
  }

  void _moveToItemScanning() {
    setState(() => _currentStep = 'item');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
    _pulseController.repeat(reverse: true);
  }

  void _resetForNextCycle() {
    setState(() {
      _currentStep = 'location';
      _scannedLocation = null;
      _scannedBarcode = null;
    });

    _locationController.clear();
    _barcodeController.clear();
    _pulseController.stop();
    _pulseController.reset();
    _resetProcessingState();

    // Auto-focus location field for next cycle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationFocusNode.requestFocus();
    });
  }

  // ✅ NEW DELETE FUNCTIONALITY
  void _showDeleteConfirmationDialog(Map<String, dynamic> item, int index) {
    final itemName = item['description'] ?? item['item_no'] ?? 'Unknown Item';
    final itemLocation = item['location'] ?? 'Unknown Location';
    final itemQuantity = item['qty'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Item'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Are you sure you want to permanently delete this item?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Item: $itemName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('Location: $itemLocation'),
                        Text('Quantity: $itemQuantity'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This action cannot be undone!',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => _deleteStorageItem(item, index),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete Permanently'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStorageItem(Map<String, dynamic> item, int index) async {
    Navigator.pop(context); // Close confirmation dialog

    if (_isDeleting) return;

    setState(() => _isDeleting = true);

    try {
      final itemId = item['id']?.toString();
      if (itemId == null) {
        throw Exception('Item ID not found');
      }

      final success = await WarehouseService.removeItemFromStorage(itemId, widget.userName);

      if (success) {
        // ✅ NEW: Store deleted item for undo
        _lastDeletedItem = Map<String, dynamic>.from(item);
        _lastDeletedIndex = index;
        
        setState(() {
          _storedItems.removeAt(index);
          _isDeleting = false;
        });

        final itemName = item['description'] ?? item['item_no'] ?? 'Item';
        
        // ✅ NEW: Show undo snackbar
        _showUndoSnackbar(
          message: '$itemName deleted',
          onUndo: () => _undoDelete(),
        );
        
        await _speakMessage('Item deleted successfully');
        
        // ✅ NEW: Clear undo data after timeout
        _undoTimer?.cancel();
        _undoTimer = Timer(Duration(seconds: _undoTimeoutSeconds), () {
          _lastDeletedItem = null;
          _lastDeletedIndex = null;
        });
      } else {
        setState(() => _isDeleting = false);
        _showMessage('Failed to delete item', isError: true);
        await _speakMessage('Delete failed');
      }
    } catch (e) {
      setState(() => _isDeleting = false);
      _showMessage('Error deleting item: ${e.toString()}', isError: true);
      await _speakMessage('Delete error occurred');
      debugPrint('❌ Delete error: $e');
    }
  }

  // ✅ NEW: Undo delete operation
  Future<void> _undoDelete() async {
    if (_lastDeletedItem == null || _lastDeletedIndex == null) return;

    try {
      // Re-insert the item to database
      final result = await WarehouseService.storeItemInLocation(
        locationCode: _lastDeletedItem!['location'] ?? '',
        barcode: _lastDeletedItem!['barcode'] ?? '',
        quantity: (_lastDeletedItem!['qty'] ?? 0) as int,
        scannedBy: widget.userName,
        description: _lastDeletedItem!['description'] ?? '',
        category: _lastDeletedItem!['category'] ?? '',
        unitPrice: (_lastDeletedItem!['unit_price'] ?? 0.0) as double,
        itemName: _lastDeletedItem!['description'] ?? '',
        sku: _lastDeletedItem!['item_no'] ?? '',
        finalSku: _lastDeletedItem!['item_no'] ?? '',
        brand: _lastDeletedItem!['brand'] ?? '',
      );

      if (result['success']) {
        setState(() {
          _storedItems.insert(_lastDeletedIndex!, _lastDeletedItem!);
        });
        
        _showMessage('Delete undone successfully ✓', isSuccess: true);
        await _speakMessage('Delete undone');
      }
    } catch (e) {
      _showMessage('Failed to undo delete: ${e.toString()}', isError: true);
      debugPrint('❌ Undo delete error: $e');
    } finally {
      _lastDeletedItem = null;
      _lastDeletedIndex = null;
      _undoTimer?.cancel();
    }
  }

  void _showItemOptionsBottomSheet(Map<String, dynamic> item, int index) {
    final itemName = item['description'] ?? item['item_no'] ?? 'Unknown Item';
    final itemLocation = item['location'] ?? 'Unknown Location';
    final itemQuantity = item['qty'] ?? 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: AppColors.primaryPink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$itemLocation • Qty: $itemQuantity',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.blue),
                  title: const Text('View Details'),
                  onTap: () {
                    Navigator.pop(context);
                    _showItemDetailsDialog(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.orange),
                  title: const Text('Edit Quantity'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditQuantityDialog(item, index);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Delete Permanently'),
                  subtitle: const Text('This action cannot be undone'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(item, index);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showItemDetailsDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text('Item Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Description', item['description'] ?? 'N/A'),
              _buildDetailRow('Item Number', item['item_no'] ?? 'N/A'),
              _buildDetailRow('Location', item['location'] ?? 'N/A'),
              _buildDetailRow('Quantity', '${item['qty'] ?? 0}'),
              _buildDetailRow('Category', item['category'] ?? 'N/A'),
              _buildDetailRow('Brand', item['brand'] ?? 'N/A'),
              _buildDetailRow('Barcode', item['barcode'] ?? 'N/A'),
              _buildDetailRow('Unit Price', '₹${(item['unit_price'] ?? 0.0).toStringAsFixed(2)}'),
              _buildDetailRow('Scanned By', item['scanned_by'] ?? 'N/A'),
              _buildDetailRow('Date Added', item['date_added']?.toString().split('T')[0] ?? 'N/A'),
              _buildDetailRow('Last Updated', item['updated_at']?.toString().split('T')[0] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditQuantityDialog(Map<String, dynamic> item, int index) {
    final TextEditingController quantityController = TextEditingController(
      text: '${item['qty'] ?? 0}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Edit Quantity'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Item: ${item['description'] ?? item['item_no'] ?? 'Unknown Item'}',
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                hintText: 'Enter new quantity',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.numbers),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _updateItemQuantity(item, index, quantityController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateItemQuantity(Map<String, dynamic> item, int index, String newQuantityStr) async {
    Navigator.pop(context);

    final newQuantity = int.tryParse(newQuantityStr);
    if (newQuantity == null || newQuantity < 0) {
      _showMessage('Invalid quantity entered', isError: true);
      return;
    }

    try {
      final itemId = item['id']?.toString();
      if (itemId == null) {
        throw Exception('Item ID not found');
      }

      final success = await WarehouseService.updateStorageItemQuantity(itemId, newQuantity);

      if (success) {
        setState(() {
          _storedItems[index]['qty'] = newQuantity;
        });
        _showMessage('Quantity updated successfully ✓', isSuccess: true);
        await _speakMessage('Quantity updated');
      } else {
        _showMessage('Failed to update quantity', isError: true);
      }
    } catch (e) {
      _showMessage('Error updating quantity: ${e.toString()}', isError: true);
      debugPrint('❌ Update quantity error: $e');
    }
  }

  Future<void> _exportStorageToExcel() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      // Create comprehensive Excel data with proper structure
      List<List<dynamic>> excelData = [];

      // Header Section
      excelData.addAll([
        ['WAREHOUSE STORAGE REPORT'],
        ['=' * 50],
        ['Generated on:', DateTime.now().toString().split('.')[0]],
        ['Generated by:', widget.userName],
        ['Warehouse:', 'Main Warehouse'],
        ['Total Items:', _storedItems.length.toString()],
        ['Report Type:', 'Storage Inventory Export'],
        [], // Empty row for spacing
      ]);

      // Summary Statistics
      int totalQuantity = 0;
      double totalValue = 0.0;
      Map<String, int> categoryCount = {};
      Map<String, int> locationCount = {};

      for (var item in _storedItems) {
        final qty = (item['qty'] ?? 0) as int;
        final price = (item['unit_price'] ?? 0.0) as double;
        final category = item['category']?.toString() ?? 'General';
        final location = item['location']?.toString() ?? 'Unknown';

        totalQuantity += qty;
        totalValue += qty * price;

        categoryCount[category] = (categoryCount[category] ?? 0) + 1;
        locationCount[location] = (locationCount[location] ?? 0) + 1;
      }

      excelData.addAll([
        ['SUMMARY STATISTICS:'],
        ['Total Quantity:', totalQuantity.toString()],
        ['Total Value:', '₹${totalValue.toStringAsFixed(2)}'],
        ['Unique Categories:', categoryCount.length.toString()],
        ['Unique Locations:', locationCount.length.toString()],
        [], // Empty row
      ]);

      // Category Breakdown
      excelData.add(['CATEGORY BREAKDOWN:']);
      excelData.add(['Category', 'Item Count', 'Percentage']);
      categoryCount.forEach((category, count) {
        final percentage = (_storedItems.length > 0
            ? (count / _storedItems.length * 100).toStringAsFixed(1)
            : '0.0');
        excelData.add([category, count.toString(), '$percentage%']);
      });
      excelData.add([]); // Empty row

      // Location Breakdown
      excelData.add(['LOCATION BREAKDOWN:']);
      excelData.add(['Location', 'Item Count', 'Percentage']);
      locationCount.forEach((location, count) {
        final percentage = (_storedItems.length > 0
            ? (count / _storedItems.length * 100).toStringAsFixed(1)
            : '0.0');
        excelData.add([location, count.toString(), '$percentage%']);
      });
      excelData.add([]); // Empty row

      // Main Data Table Headers
      excelData.addAll([
        ['DETAILED STORAGE INVENTORY:'],
        ['=' * 80],
        [
          'ID',
          'Item Number',
          'Description',
          'Category',
          'Brand',
          'Location',
          'Quantity',
          'Unit Price',
          'Total Value',
          'Barcode',
          'Date Added',
          'Last Updated',
          'Scanned By',
          'Status'
        ],
      ]);

      // Main Data Rows
      for (int i = 0; i < _storedItems.length; i++) {
        final item = _storedItems[i];
        final qty = (item['qty'] ?? 0) as int;
        final unitPrice = (item['unit_price'] ?? 0.0) as double;
        final totalItemValue = qty * unitPrice;

        // Determine status based on quantity
        String status = 'Available';
        if (qty == 0) {
          status = 'Out of Stock';
        } else if (qty <= 5) {
          status = 'Low Stock';
        }

        excelData.add([
          (i + 1).toString(), // Row number
          item['item_no']?.toString() ?? 'N/A',
          item['description']?.toString() ?? 'No Description',
          item['category']?.toString() ?? 'General',
          item['brand']?.toString() ?? 'N/A',
          item['location']?.toString() ?? 'Unknown',
          qty.toString(),
          '₹${unitPrice.toStringAsFixed(2)}',
          '₹${totalItemValue.toStringAsFixed(2)}',
          item['barcode']?.toString() ?? 'No Barcode',
          item['date_added']?.toString().split('T')[0] ?? 'N/A',
          item['updated_at']?.toString().split('T')[0] ?? 'N/A',
          item['scanned_by']?.toString() ?? widget.userName,
          status,
        ]);
      }

      // Footer Section
      excelData.addAll([
        [], // Empty row
        ['REPORT FOOTER:'],
        ['Total Records:', _storedItems.length.toString()],
        ['Export Format:', 'CSV (Excel Compatible)'],
        ['File Generated:', DateTime.now().toString().split('.')[0]],
        ['Software:', 'WMS Storage Manager v1.0'],
        ['Contact:', 'warehouse@company.com'],
        [], // Empty row
        ['Note: This report contains all storage items at the time of export.'],
        ['Values are calculated based on current unit prices and quantities.'],
      ]);

      // Convert to CSV string (Excel compatible)
      String csvString = const ListToCsvConverter().convert(excelData);

      // Save to file with timestamp
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
      final fileName = 'Storage_Report_${timestamp.replaceAll(' ', '_')}.csv';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(csvString);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Warehouse Storage Report\n'
            'Generated: ${DateTime.now().toString().split('.')[0]}\n'
            'Total Items: ${_storedItems.length}\n'
            'Total Quantity: $totalQuantity\n'
            'Total Value: ₹${totalValue.toStringAsFixed(2)}\n'
            'Generated by: ${widget.userName}',
        subject: 'Warehouse Storage Export Report - $fileName',
      );

      _showMessage('Storage report exported successfully!', isSuccess: true);
      await _speakMessage('Storage report exported');
    } catch (e) {
      _handleError('Export failed', e, isRecoverable: false);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _showMessage(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;

    Color backgroundColor = Colors.blue;
    if (isError) backgroundColor = Colors.red;
    if (isSuccess) backgroundColor = Colors.green;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.length > 100 ? '${message.substring(0, 100)}...' : message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: isError ? 6 : 3),
        action: isError
            ? SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white70,
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              )
            : null,
      ),
    );
  }

  // ✅ NEW: Show undo snackbar
  void _showUndoSnackbar({required String message, required VoidCallback onUndo}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: _undoTimeoutSeconds),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Colors.white,
          backgroundColor: Colors.white.withOpacity(0.2),
          onPressed: onUndo,
        ),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    if (_currentStep == 'location') {
      return _buildLocationScanningStep();
    } else {
      return _buildItemScanningStep();
    }
  }

  Widget _buildLocationScanningStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              Icon(
                Icons.location_on,
                size: 64,
                color: _isLoading ? Colors.grey : AppColors.primaryPink,
              ),
              const SizedBox(height: 16),
              Text(
                _isLoading ? 'Validating Location...' : 'Scan Location Code',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLoading ? 'Please wait...' : 'Use scanner to scan location (A-01-01 format)',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textLight,
                ),
                textAlign: TextAlign.center,
              ),
              if (_consecutiveErrors > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Errors: $_consecutiveErrors/$_maxConsecutiveErrors',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                enabled: !_isLoading && !_isProcessingScan,
                decoration: InputDecoration(
                  labelText: 'Location Code',
                  hintText: 'Scan location (e.g., A-01-01)',
                  prefixIcon: Icon(
                    Icons.qr_code_scanner,
                    color: _isLoading ? Colors.grey : AppColors.primaryPink,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: 'Format: A-01-01 (Zone-Aisle-Shelf)',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 10, // Prevent overly long input
                onSubmitted: (value) {
                  if (!_isLoading && !_isProcessingScan) {
                    _handleLocationScan(value);
                  }
                },
              ),
              if (_isLoading) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryPink),
                ),
              ],
            ],
          ),
        ),
        if (_scannedLocation != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location: $_scannedLocation',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text(
                        'Location validated',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemScanningStep() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Column(


            
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                    Icon(
                      Icons.qr_code,
                      size: 64,
                      color: _isLoading ? Colors.grey : Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isLoading ? 'Processing Item...' : 'Scan Item Barcode',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoading ? 'Please wait...' : 'Use scanner to scan item',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textLight,
                      ),
                    ),
                    if (_consecutiveErrors > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Scan errors: $_consecutiveErrors/$_maxConsecutiveErrors',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocusNode,
                      enabled: !_isLoading && !_isProcessingScan,
                      maxLines: null,  // ✅ CHANGED: Was 1, now null (unlimited)
                      minLines: 1,     // ✅ ADDED: Minimum 1 line
                      keyboardType: TextInputType.multiline,  // ✅ ADDED: Multi-line support
                      decoration: InputDecoration(
                        labelText: 'Item Barcode',
                        hintText: 'Scan item barcode',
                        prefixIcon: Icon(
                          Icons.qr_code_scanner,
                          color: _isLoading ? Colors.grey : Colors.green,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        helperText: 'Supports QR codes and barcodes',
                      ),
                      maxLength: null,  // ✅ CHANGED: Remove character limit
                      onSubmitted: (value) {
                        if (!_isLoading && !_isProcessingScan) {
                          _handleItemScan(value);
                        }
                      },
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Colors.green),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryPink.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryPink.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: AppColors.primaryPink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Location: $_scannedLocation confirmed\nReady to scan item...',
                        style: const TextStyle(
                          color: AppColors.primaryPink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStorageItemsList() {
    if (_storedItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No items stored yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Start scanning to store items',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _storedItems.length,
        itemBuilder: (context, index) {
          final item = _storedItems[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryPink.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: AppColors.primaryPink,
                ),
              ),
              title: Text(
                item['description'] ?? item['item_no'] ?? 'Unknown Item',
                style: const TextStyle(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location: ${item['location']} • Qty: ${item['qty']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item['date_added'] != null)
                    Text(
                      'Added: ${DateTime.parse(item['date_added']).toString().substring(0, 16)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showItemOptionsBottomSheet(item, index),
              ),
              onTap: () => _showItemDetailsDialog(item),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📦 Storage Manager'),
          backgroundColor: AppColors.primaryPink,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner'),
              Tab(icon: Icon(Icons.list), text: 'Stored Items'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _isLoading ? null : _loadData,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: _isExporting || _isLoading ? null : _exportStorageToExcel,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.file_download),
              tooltip: 'Export to Excel',
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primaryPink.withOpacity(0.1),
                Colors.white,
              ],
            ),
          ),
          child: TabBarView(
            children: [
              // Scanner Tab
              FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildCurrentStepContent(),
                ),
              ),
              // Stored Items Tab
              _buildStorageItemsList(),
            ],
          ),
        ),
        floatingActionButton: _currentStep == 'location' || _isLoading
            ? null
            : FloatingActionButton(
                onPressed: _isProcessingScan ? null : _resetForNextCycle,
                backgroundColor: _isProcessingScan ? Colors.grey : AppColors.primaryPink,
                child: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Start New Cycle',
              ),
      ),
    );
  }
}
